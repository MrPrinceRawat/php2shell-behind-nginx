# php2shell behind nginx — what actually survives

Notes and measurements on running php2shell (CVE-2026-109618 / CVE-2026-109619)
against PHP that sits behind nginx, plus a reliable app-level chain for the cases
where the memory-corruption chain cannot be delivered.

Short version:

* nginx **dechunks every request**, even with `proxy_request_buffering off`. PHP
  therefore always sees a `Content-Length`, so `post_max_size` applies again and
  the chunked-bypass that public exploits rely on is gone.
* A small `post_max_size` is a real mitigation: with PHP's shipped production
  values (128M / 8M) the body is capped at 8M, the parser never exhausts memory,
  and neither CVE fires.
* Even with the cap lifted, the **leak step does not survive the hop**. It breaks
  through a bare L4 TCP proxy too, so it is not HTTP framing — the multipart read
  pacing shifts the heap geometry the page-indexed fake `zend_string` depends on.
* Parse-time memory is hard-capped by `max_input_vars`, not by body size:
  measured saturation at 52.4 MB. 128M is unreachable at default settings.
* What does survive nginx is the **app-LFI chain**: the upload-progress
  serialiser writes an attacker-controlled filename into the session file, and
  any `include` sink executes it. First attempt, default `cleanup=On`.

## 1. nginx rewrites the request

Two configurations, identical app, header-echo endpoint:

| config | PHP sees |
| --- | --- |
| `proxy_request_buffering on` | `CONTENT_LENGTH: 162`, `HTTP_TRANSFER_ENCODING: null` |
| `proxy_request_buffering off`, 162 B body | same — small bodies are still buffered |
| `proxy_request_buffering off`, 2 MB body, client sends chunked | `CONTENT_LENGTH: null`, `HTTP_TRANSFER_ENCODING: chunked` |

So chunked framing only reaches PHP when the body exceeds `client_body_buffer_size`
*and* buffering is off. nginx also enforces `client_max_body_size` either way —
it counts bytes, so chunking does not buy budget.

The published exploits send bodies with `Transfer-Encoding: chunked` and no
`Content-Length`; that sets `content_length = 0` in PHP, which skips the
`post_max_size` pre-check in `rfc1867_post_handler()` and makes
`session.upload_progress.freq` compute an update step of 0 (an update on every
part). Behind nginx both of those disappear.

## 2. The cap is the mitigation

PHP production defaults are `memory_limit=128M`, `post_max_size=8M`. Behind nginx
every request is capped at 8 MB, so parsing cannot exhaust memory. Same requests,
same build, direct against Apache: OOM, corrupted state, chain works. Through
nginx: `HTTP 500` never happens, both buffering modes fail at the leak step.

Raising the cap (256M) is not enough on its own — the leak still fails (§3).

## 3. The leak does not survive a hop

With `post_max_size` raised and `session.upload_progress.freq=0` (restoring the
per-part updates that `content_length=0` gave for free), A1 reaches the
`send_cookie` OOM again: `HTTP 500`, bodyless, as intended. B1 then fails with
`no heap pointers in leak window`.

Isolating the cause: a **plain L4 `stream` proxy** (no HTTP parsing at all, nginx
never touches headers) fails identically. So it is not dechunking, not
`Content-Length`, not header rewriting. It is read pacing: the multipart buffer
refills differ, the 2 MB chunk that holds the stale session id is populated in a
different order, and the fake `zend_string` header no longer lands on the page
`PS(id)` points into. Sweeping the page index (0x100–0x1A0) does not recover it.

The leak is an OOB read in a URL-encoded `Set-Cookie`: A1 leaves `PS(id)`
dangling with `send_cookie=1`, B1 places a fake `zend_string` header at a fixed
page inside a fill value, and `php_session_send_cookie()` hands back
`fake_len` bytes of heap. Every byte of that geometry has to line up, which is
why a hop is enough to break it.

## 4. Parse-time memory is capped by `max_input_vars`

Nested-array bombs against the CLI SAPI (same parser as any web SAPI):

| vars × depth | body | peak |
| --- | --- | --- |
| 1000 × 63 | 195 KB | 52.4 MB |
| 2500 × 63 | 488 KB | 52.4 MB |
| 5000 × 63 | 975 KB | 52.4 MB |

Identical peak regardless of body size: leaves beyond `max_input_vars = 1000` are
not retained. So the maximum parse-time memory any request can cause is ~52 MB,
and 128M is unreachable without raising `max_input_vars`. Everything past ~195 KB
of body is wasted. Optimising the key shape makes it worse — long key names cost
more per level and reduce the number of vars that fit (27-char segments: 35.6 MB;
120-char: 10.5 MB).

Consequence: a 1 MiB `client_max_body_size` plus a high `memory_limit` removes
the OOM entirely. A 1 MiB body only reaches 24M–35M of parse memory, so it OOMs at
`memory_limit ≤ 24M` and is clean at 32M and above.

## 5. What does work through nginx

The app-LFI chain (chain A) is not a memory-corruption bug, so nothing above
applies to it. The upload-progress serialiser stores the raw multipart
**filename** in the session record; a filename containing PHP code is written
verbatim, and any LFI sink that includes the session file executes it.

```
[attempt 1] SID=exploit1cd3... file=/var/lib/php/sessions/sess_exploit1cd3...
    plant=HTTP/1.1 200 OK
[+] RCE CONFIRMED: uid=33(www-data) gid=33(www-data) groups=33(www-data)
```

Conditions: `session.upload_progress.enabled` (default on), a known session save
path, and an `include` sink. Works with default `cleanup=On` (stall the writer
after `FILE_START`) and with `cleanup=Off`. Reproduce with `exploit/rce-lfi.sh`.

## 6. Mitigations, ranked

| setting | effect |
| --- | --- |
| `post_max_size` at default 8M, `memory_limit` 128M | both CVEs unreachable through a proxy (§2) |
| `memory_limit = -1` | removes the controllable failure; only allocator failure remains, and RLIMIT_AS/DATA can cause exactly that |
| `session.upload_progress.enabled = 0` | kills the carrier, so kills both chains including the LFI one |
| `max_input_vars` low | caps parse memory (§4); does not help once the OOM path is chosen |
| bigger `client_max_body_size` | *weakens* the config: restores the OOM window |

## 7. Detection

`rules/php2shell.rules` (Suricata) and `rules/modsecurity.conf`: multipart POST
carrying `PHP_SESSION_UPLOAD_PROGRESS` with a large body, and the forced
`PHPSESSID` variant. Log-side the discriminator is the startup fatal:

```
PHP Fatal error:  Allowed memory size of <N> bytes exhausted ... in Unknown on line 0
```

`Unknown on line 0` means the OOM happened during request parsing, not in
application code.

## 8. Open problem: the 1 MiB case

The leak body is 33 MB in the published form; the fake header sits at page
`0x137`, i.e. 1.24 MB of body before it, which already exceeds a common 1 MiB
`client_max_body_size`. A1 itself can be shrunk a long way (160 nested parts,
152 KB, still OOMs at `memory_limit=24M`) but the page index is allocation-driven
— it is wherever the allocator put the session id — so the body cannot simply be
trimmed. Moving the id low in its chunk, or shrinking `fake_len` and re-fitting
the page, is the remaining work.
