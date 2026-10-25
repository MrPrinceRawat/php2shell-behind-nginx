# php2shell behind nginx

Measurements, a lab, and an app-level chain for CVE-2026-109618 / CVE-2026-109619
on PHP that is served through nginx.

Read **[WRITEUP.md](WRITEUP.md)**. It is the point of the repo.

Summary of the results:

* nginx dechunks and sets `Content-Length` (even with `proxy_request_buffering off`,
  for bodies under `client_body_buffer_size`), so `post_max_size` applies again and
  the chunked bypass public exploits rely on is gone;
* at PHP's shipped production defaults (128M / 8M) neither CVE fires through a
  proxy at all — the cap does the work;
* the heap leak does not survive any extra hop, including a bare L4 proxy — it is
  read pacing, not HTTP framing;
* parse-time memory saturates at 52.4 MB because of `max_input_vars = 1000`, so a
  high `memory_limit` plus a 1 MiB body is not exploitable;
* the app-LFI chain does survive nginx, first try, with default `cleanup=On`.

## Layout

```
WRITEUP.md          the write-up: measurements, mitigations, detection, open problem
FINDINGS.md         lab notebook: raw runs, the vuln-vs-patched table, the dead ends
lab/                mod_php target, stock and tightened profiles, patched control
lab-fpm/            same build behind nginx + PHP-FPM
lab-proxy/          nginx -> mod_php, buffering on/off
exploit/
  php2shell.py      single-target driver for the primitive-level behaviour
  compare.py        vulnerable vs patched delta table
  rce/              vendored pure-HTTP chain + aarch64 offsets (NOTICE.md)
  rce-lfi.sh        app-LFI chain through nginx: one command, RCE
  lfi/              the chain and its three-line target app
  remote/           TLS forwarder + patient runner for a remote/slow target
rules/              Suricata + ModSecurity detection
out/                captured runs
```

## Quickstart

```sh
lab/up.sh                                   # 8080 stock, 8081 tight, 8082 patched
exploit/rce.sh                              # zero-dependency chain, direct to Apache
exploit/rce.sh --patched                    # same, 8.4.27: leak fails
exploit/rce-lfi.sh                          # app-LFI chain, through nginx
exploit/compare.py --vuln 8081 --patched 8082
lab/down.sh
```

Requires macOS with Apple `container` (the labs build on `php:8.4.26-*`).

## Attribution

`exploit/rce/` and `exploit/lfi/` are vendored from public research — see
`exploit/rce/NOTICE.md`. Everything else here is ours. MIT.
