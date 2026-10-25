# php2shell — lab findings

Target: `php:8.4.26-apache` (mod_php, arm64), production-shaped ini
(`display_errors=Off`, single prefork child).
Control: identical build on `php:8.4.27-apache`.
Driver: `exploit/compare.py`, three scenarios, one unauthenticated client.
Raw run: `out/compare.json`, `out/compare.txt`.

## Result table (last run)

| scenario / measurement | 8.4.26 | 8.4.27 |
| --- | --- | --- |
| **A** OOM upload, status | 500 | 500 |
| **A** OOM fatal in server log | sometimes | sometimes |
| **A** session record destroyed | no | **yes** |
| **A** handler wrote progress key before dying | **yes** | no |
| **A** attacker record intact afterwards | **yes** | no |
| **B** plain upload, `$_SESSION` global at script start | **present** | absent |
| **B** attacker data (`user=admin`) visible at script start | **yes** | no |
| **B** `session_status()` at script start | 1 (none) | 1 (none) |
| **C** same, after an OOM on that worker | **present / yes** | absent / no |
| **C** progress key landed in the session record | yes | yes |

"At script start" = the first line of application code, before the app calls
`session_start()`. On 8.4.26 the app sees:

```json
{"session_status": 1, "globals_SESSION": true,
 "SESSION": {"user": "admin", "upload_progress_stgB": {...}}}
```

A session that the module insists is not open, populated with data the client
never sent through the app. On 8.4.27 both are gone.

## What is actually demonstrated

1. **Unauthenticated parse-time session write.** A multipart POST with
   `PHP_SESSION_UPLOAD_PROGRESS` makes the server resolve a chosen session id,
   merge `upload_progress_<key>` into that record and write it to disk, with no
   application code involved. Verified by reading
   `/var/lib/php/sessions/sess_<id>` out of the container.

2. **OOM interrupt inside that window.** A plain field larger than
   `memory_limit` aborts parsing (`Fatal error: Allowed memory size ... in
   Unknown on line 0`, "line 0" = startup). Response is a bodiless 500, which
   is exactly what a production host with `display_errors=Off` shows.

3. **Request-owned state outliving the request.** After the interrupt, the
   next upload-progress request on the same worker sees a `$_SESSION` array
   already populated with the attacker's record, with `session_status()`
   reporting *none*. This is the 109619 observable and it dies at 8.4.27.

4. **A behaviour delta worth knowing before you patch-blindly.** On the patched
   build the OOM path can `s_destroy` the session record (files handler
   unlinks `sess_<id>`) when the interrupt lands during
   `php_session_rfc1867_update`, and the progress key is no longer written
   first. So an interrupted upload on 8.4.27 can lose the session, while on
   8.4.26 it keeps the poisoned one. Patch, but do not read "no record" as
   "no attack" in your telemetry.


## RCE — chain and result

Goal reached on the vulnerable build with the public pure-HTTP chain by 9bie
(`exploit/rce/`, attribution in `exploit/rce/NOTICE.md`). Target: stock
`php:8.4.26-apache`, official `php.ini-production`, `display_errors=Off`,
`memory_limit=128M`, official 150-worker prefork, page is `<?php echo "OK\n"; ?>`.

```
[t try 1] A1: END-cleanup send_cookie OOM
[t try 1] B1: stale-id OOB read (chunk base + libphp)
      arch=aarch64 decoded=819208 zval_ptr_dtor=0xffffa9e6812b -> libphp=0xffffa9830000
      chunk buckets: [('0xffff9f000000', 7495), ('0xffffa9e00000', 1095), ('0xffffa7800000', 87), ...]
[t try 1] A2 + B2: main=0xffffa7800000 S=0xffffa78f8398 zif_system=0xffffa9c5cd70
[4/4] RCE OK; proof: uid=33(www-data) gid=33(www-data)
```

Same run against `php:8.4.27-apache`: leak step fails ("no heap pointers in leak
window") on all three attempts, no RCE. Logs: `out/rce/`.

How the chain works:

* **A1** — OOM fired inside the multipart `END` cleanup (`send_cookie` path), so
  shutdown dies with request-owned state still referenced.
* **B1** — the stale session id is dereferenced and decoded as a session record,
  reading out of bounds past the freed chunk. The decoded garbage carries heap
  pointers; counting bucket hits in that window identifies the main heap chunk,
  and one leaked `zval_ptr_dtor` pointer gives the `libphp.so` base.
* **A2** — a cheap OOM leaves `PS(http_session_vars)` dangling.
* **B2** — a fake reference plus fake `zend_array` are planted through the
  session, and the array's destructor slot is overwritten with `zif_system`.
  When a zval is destroyed the destructor runs `system(<cmd>)`.

Why it lands where our earlier primitive work did not: the official
`php.ini-production` ships `session.use_strict_mode=Off`, so a nonexistent
attacker-supplied session id is accepted instead of being replaced — that is
what lets the stale id survive the decode. Our tight lab has strict mode `On`,
which is why it showed the leak-precursor but never the reuse.

Offsets are build-specific: the leak step prints the arch and refuses to
continue on a mismatch (aarch64 offsets for image digest `e160c9d1…`, see
`exploit/rce/offsets/README.md`). A different image digest needs re-calibration.

Chains A and B in the ikow repo (`exploit/chain_a_session_lfi.py`,
`exploit/chain_b_uaf_rce.php`) cover the app-cooperation variants — LFI sink, or
an app that calls `unserialize()` — and are not wired up here.

## Why the primitives stopped short

The primitives above are what the crash-only view shows; the full chain needs
the leak plus heap shaping. Remaining questions worth poking at:

* The corruption is a heap/type confusion on state that `php_request_shutdown()`
  and the session `RSHUTDOWN` walk after the bailout. Getting controlled bytes
  into `PS(session_vars)`, `PS(id)` or `PG(rfc1867_protected_variables)` at the
  moment the allocation fails is the whole game; the parser's part ordering
  (fields, file parts, nesting depth) is the knob.
* `PS(id)` after cleanup is a dangling `zend_string`. Whether the next parse
  reuses it is decided by whether the freed chunk still looks like a string —
  in our runs it usually does not, so the handler creates a fresh id instead.
  Forcing reuse (heap grooming via part structure, or a session id in a size
  class that is not recycled by shutdown's small allocations) is the next
  experiment.
* Full exploit needs an ASLR story. Public reporting agrees: reliable RCE was
  seen on ARM64, and on x86-64 only for specific versions/heap layouts;
  everything else is a crash plus a leak.
* Worth testing next: `memory_limit` values where the *failed* allocation is
  huge (leaving the shutdown itself starved, which is where 109619 bites), and
  `php_admin_value` vs `php.ini` placement (per-directory INI is re-applied
  during parsing and adds another allocation source).

## Mitigation checks against this lab

| setting | effect here |
| --- | --- |
| `memory_limit` 128M + `post_max_size` 8M (stock) | no OOM from body size at all |
| `post_max_size` 64M / `memory_limit` 32M (tight) | OOM, every time |
| `session.upload_progress.enabled=0` | carrier gone; A still 500s, B/C leak disappears |
| `memory_limit=-1`, `php_admin_value` | removes the controllable failure |

## Detection

`rules/php2shell.rules` (Suricata) and `rules/modsecurity.conf`: multipart POST
+ `PHP_SESSION_UPLOAD_PROGRESS` + large body, plus the forced-`PHPSESSID`
variant. Log-side, the server line to alert on is the startup fatal:

```
PHP Fatal error:  Allowed memory size of <N> bytes exhausted ... in Unknown on line 0
```

with `Unknown on line 0` as the discriminator — OOMs in application code carry
a real filename.

## Behind nginx?

Tested `nginx -> mod_php` (both `proxy_request_buffering on` and `off`) and
`nginx -> PHP-FPM`, stock official ini (`lab-proxy/`, `lab-fpm/`).

**nginx dechunks and sets `Content-Length` regardless of buffering mode.** Echo
endpoint behind both configs shows `CONTENT_LENGTH: 162`,
`HTTP_TRANSFER_ENCODING: null`, `php://input` empty. `proxy_request_buffering
off` does not help; the dechunk happens on the way in.

Consequences:

1. `post_max_size` applies again, so with stock 128M / 8M the body caps at 8M
   and nothing ever OOMs — the chain cannot even start. Both buffering modes
   fail at the leak step.
2. `content_length = 0` was also doing silent work for the chain: `update_step`
   becomes 0, so the progress handler runs for *every* part. Restoring that
   behind nginx needs `session.upload_progress.freq=0` plus a large
   `post_max_size`. With `freq=0`, `post_max_size=256M`, A1 reaches the
   `send_cookie` OOM again (500, 309-byte response), so the corruption is
   reachable through a proxy.
3. But B1 still fails: the OOB window is empty or misaligned. The multipart
   read buffer size follows `content_length`, so the heap geometry the
   `0x137`-page fake-`zend_string` offsets assume does not hold on the
   `Content-Length` path. A sweep of page offsets 0x100-0x1A0 is not enough;
   proper fix is recalibration against the CL path with the repo's `--dbg`
   flow.

`nginx -> PHP-FPM` with the mod_php offsets also fails at the same leak step
(different binary, different SAPI). Public reporting has separate FPM chains;
none are vendored here.

Net: nginx is a real speed bump, not a wall. Untuned it blocks the stock chain
via the `post_max_size` cap (same class as the advisory mitigation); tuned
(`freq=0`, big `post_max_size`) the corruption is back and only the leak
geometry needs re-fitting.

### Way out: the app-LFI chain runs fine behind nginx

The zero-dependency chain above needs the memory-corruption leak, and the leak's
heap geometry breaks under *any* extra hop — including a pure L4 TCP proxy, so it
is not nginx's HTTP framing but the read pacing. Page-offset sweeps did not
recover it; it needs calibration against the proxied path.

The second public chain (ikow chain A, vendored in `exploit/lfi/`) does not touch
memory corruption: the upload-progress serialiser stores the raw multipart
**filename** in the session file, so a filename carrying `<?php system(...) ?>` is
written verbatim, and any LFI sink that includes the session file runs it.

Result through `nginx -> mod_php`, stock ini, default `cleanup=On`:

```
[+] RCE CONFIRMED: uid=33(www-data) gid=33(www-data) groups=33(www-data)
```

First attempt, and equally on `cleanup=Off` and without nginx. Wrapper:
`exploit/rce-lfi.sh` (`--no-proxy` for the delta). The app used here is three
lines and includes `$_GET['page']`; the only real precondition is "an LFI sink
exists", which is a normal WordPress/plugin-class assumption.

So: behind nginx, pre-auth RCE is routine **with an app LFI**, and the
zero-dependency chain is one calibration session away. nginx does not stop
either.

## Can a 1 MiB cap + high memory_limit be beaten?

Measured on the target's SAPI (`php -S`, 8.4.26), nested-array parse bombs:

| vars × depth | body | peak | notes |
| --- | --- | --- | --- |
| 1000 × 63 | 195 KB | 52.4 MB | saturates |
| 2500 × 63 | 488 KB | 52.4 MB | same |
| 5000 × 63 | 975 KB | 52.4 MB | same |

`max_input_vars = 1000` is the ceiling: past 1000 leaves nothing more is kept,
so the practical maximum parse-time memory from any body is ~52 MB. Body bytes
beyond ~195 KB are wasted unless `max_input_vars` is raised.

Consequences:

* 128M (`memory_limit`) is **not** reachable at default settings with a 1 MiB
  cap. If the operator raised `max_input_vars` to ~2500 (common on shared
  hosts), the OOM fires at ~490 KB and fits the cap.
* `memory_limit = -1` removes the controllable failure entirely; only an
  allocator failure (cgroup/RLIMIT) can still reach the path, and the OOM
  killer may take the process instead.
* Independent second blocker: the leak body is 33 MB. Behind a 1 MiB cap the
  chain fails at the leak step (`no Set-Cookie ... 0 bytes`); 1.1 MB gets a
  413. So even with the OOM reachable, the leak must be re-tuned to ~1 MB or the
  cap lifted.

Two cheap probes to classify a target before investing: post the ~195 KB bomb
(`/tmp/nv_1000.bin`) and read the body for `Allowed memory size` (OOM reachable
⇒ memory_limit is low), and post 1.1 MB to see 413 vs parsed (cap and whether
`post_max_size` matches it).
