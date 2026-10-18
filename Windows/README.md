# AllInOneIME for Windows

The Windows shell of AllInOneIME, on the core in `../Core` (the same Swift package the macOS app is built on). So far:

- The input method's text service (Text Services Framework, C++), in `tip/`, with its own README. It is the DLL side
  of wire protocol v1 (`../Core/docs/wire-protocol-v1.md`).
- `AllInOneIMEEngine`, the per-user engine that the text service talks to over a named pipe, in wire protocol v1. It
  serves the core's `AllInOneIMEWire` server: a Composer for each text field, one serial queue for each client
  connection. What the wire doesn't carry isn't done yet and is only logged: the candidate panel isn't drawn,
  nothing is opened, no model is asked.
- `allinoneime-cli`, the command line. It runs level two (translate / polish, the rewrites) with the core's code and
  settings (`config.json` where the core keeps it on Windows, under `%APPDATA%`). `wire-replay` replays the
  protocol's goldens over the real pipe.

The settings window and the installer come next.

```
swift build                                   # Swift 6.4 for Windows, with Visual Studio's MSVC and Windows SDK
swift run allinoneime-cli --help
```

The core builds and its tests build here too: `swift build --build-tests` in `../Core`, and `swift test --filter
AllInOneIMEWireTests` runs the protocol's goldens in process.

## The engine

```
.build\debug\AllInOneIMEEngine.exe [--test] [--instances N] [--quiet]
```

- **Pipe:** `\\.\pipe\AllInOneIME-<UserSID>-v1`, with the protocol's SDDL and `FILE_FLAG_FIRST_PIPE_INSTANCE` (§2.1).
  It is in message mode, refuses remote clients, uses overlapped I/O, and keeps at least 4 instances waiting.
- **Single instance:** a second engine for the same user exits (`Local\AllInOneIME-Engine-<SID>`).
- **Client check:** a client from another session or another user is refused. Low-integrity and AppContainer
  clients are `untrusted` (§8). Tested with a low-integrity copy of the CLI: it connects, comes out
  `low, untrusted`, and the goldens pass.
- **A client that stops reading:** its writes time out after 500 ms and the connection is dropped (tested: about
  0.6 s), so the engine isn't stalled for every app.
- **Watchdog:** the engine exits when a connection's queue is busy for more than 2 s.
- **bye:** Ctrl+C, logoff and shutdown send `bye` to every client first.
- **`--test`:** a manual clock, level two from a golden's scripted provider, and `x-test` directives
  (`AllInOneIMEWire`'s `TestFrame`) accepted. Clients are taken to own the foreground. `wire-replay` drives it.

## Replaying the goldens over the pipe

```
allinoneime-cli wire-replay [--launch ENGINE.exe] [--cold-starts N] [--repeat N] <file.jsonl>...
```

Against an engine in test mode, either one already running or one started with `--launch`, it does what a DLL does:

1. the server check (§2.1, with the spec notes' fix: the server process's integrity is checked, not the pipe's label);
2. each `>` frame written;
3. `x-test idle`;
4. the frames the engine sent before the idle answer compared with the `<` lines.

It prints each file and the key round trips: from writing a `keyDown` or `keyUp` to reading its `result`, timed
with `QueryPerformanceCounter`. With `--cold-starts N`, it first launches the engine N times and times each launch
until `welcome`.

```
swift build -c release
.build\release\allinoneime-cli wire-replay --launch .build\release\AllInOneIMEEngine.exe ^
    --cold-starts 20 --repeat 50 ..\Core\Tests\AllInOneIMEWireTests\WireGoldens\*.jsonl
```

## Measured (M2)

Measured on 2026-10-18 on a Ryzen 5 5600X (12 threads, 48 GB) running Windows 11 Pro 26200 with Swift 6.4.1.

- **Setup:** the engine in test mode (Latin input, the scripted provider), run over OpenSSH (session 0, high
  integrity).
- **Results:** all 10 goldens passed on every run, 500 of 500 replays in release and 200 of 200 in debug.
- **Load:** the PC was shared. Another job's builds kept the CPU at 50–90%, so the numbers are a little pessimistic
  and the cold starts vary between runs.

| | release | debug |
|---|---|---|
| cold start, launch → pipe open (p50 / p90 / max of 20) | 29.3 / 30.6 / 82.1 ms | 23.7 / 25.0 / 31.1 ms |
| cold start, launch → `welcome` (p50 / p90 / max of 20) | 30.9 / 33.2 / 83.8 ms | 25.5 / 26.8 / 33.4 ms |
| key round trip, p50 | 0.092 ms | 0.175 ms |
| key round trip, p90 | 0.189 ms | 0.398 ms |
| key round trip, p99 | 0.296 ms | 0.601 ms |
| key round trip, max | 0.70 ms | 11.0 ms |
| key round trips measured | 16,400 (50 runs) | 6,560 (20 runs) |
| the engine's first key | 0.49 ms | 0.39 ms |

Notes on the numbers:

- **Budget:** the spec allows 20 ms p99 on the engine's side (§5.4), and the DLL gives up after 150 ms.
- **What the round trip includes:** both ends' JSON, the pipe and the Composer, all of it.
- **The max cold start:** the slowest launch is always the first of a series (a cold file cache).
- **Fresh executables:** while the antivirus was still scanning freshly built executables and another build was
  running, one series measured 151 ms p50.
- **Debug vs release:** the debug engine starting faster than the release one is noise from the load, not a real
  difference.
- **Not measured yet:** the first draw (50 ms), keepalive, and anything with Rime or a model, which need the DLL, the
  panel and a language pack.
