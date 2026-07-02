# kefbar — build spec

A tiny, open-source macOS app + CLI to control the volume of KEF W2-platform
wireless speakers (LSX II, LSX II LT, LS50 Wireless II, LS60 Wireless) from the
menu bar and the command line. No cloud, no KEF Connect app, no remote — just the
speaker's own local HTTP API on the LAN.

This document is the authoritative brief. Build in the milestone order in §14.
Everything the speaker API does is pinned in §5 — do not re-guess it.

---

## 1. Purpose

- Replace the KEF remote / KEF Connect app for the one thing done constantly:
  **setting volume**, per speaker.
- Native menu-bar slider (feels like Apple's volume slider) with **one slider per
  configured speaker** (e.g. "Living Room", "Study Desk").
- A **fast CLI** so a physical controller (Logitech Options+ button, Stream Deck,
  BetterTouchTool, Keyboard Maestro) can bind hardware buttons to volume changes.

## 2. Goals / non-goals

**Goals**
- Menu-bar-only agent (no Dock clutter by default), optional Dock presence.
- Launch at login (toggle).
- Discover any KEF W2 speaker on the LAN by probing the API contract.
- Persist multiple speakers (name + IP, keyed by MAC so IP changes self-heal).
- Per-speaker volume slider + mute in a menu-bar popover.
- Live-reflect changes made on the physical remote (event poll).
- CLI: set / up / down / mute / unmute / get, fast enough for rapid button taps.
- Ship as a drag-to-Applications DMG. Built locally for now.

**Non-goals (v1)**
- No streaming / source selection / transport control in the UI (API supports it;
  leave hooks but build no UI). Volume + mute + power status only.
- No multi-user, no menubar EQ, no per-app volume.
- No notarised public release yet (local builds; GitHub CI comes later).
- No Windows/Linux. macOS only.

## 3. Platform & tooling

- **Language:** Swift, for *all three* parts (app, CLI, shared lib). One language;
  the CLI compiles to a fast native binary — no interpreter start-up cost, which
  matters for rapid taps (see §11).
- **macOS floor: 13.0 (Ventura).** Chosen to minimise code: use the native
  high-level APIs directly, skip all back-compat workarounds.
  - Menu bar: SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)` (13+).
  - Launch at login: `SMAppService.mainApp.register()/unregister()` (13+) — no helper
    bundle, no plist.
  - Networking: native `URLSession.data(for:)` (12+). No shim.
  - Ventura still installs on 2017-and-later Macs (~8-year-old hardware), so a higher
    floor costs almost no real-world reach.
- **UI:** pure SwiftUI App lifecycle — a `MenuBarExtra` scene for the bar and a
  `Settings` scene for the settings window. No AppKit status-item/popover plumbing.
- **Build:** SwiftPM package for `KEFKit` (library) + `kefbar` (CLI executable); an
  Xcode project (or SwiftPM app-bundle build) for the menu-bar app, referencing
  `KEFKit`. `Makefile` drives build + DMG.
- **No third-party runtime deps.** Foundation + Network + AppKit/SwiftUI only.
  (Bonjour via `NWBrowser`; HTTP via `URLSession`; IPC via POSIX `AF_UNIX` sockets.)

## 4. Architecture

```
                         ~/Library/Application Support/kefbar/config.json
                         (speakers: name, IP, MAC, maxVolume) — single source of truth
                                   ^                     ^
                                   | read/write          | read (+ resolve default)
                                   |                     |
   +-------------------------------+          +--------------------------+
   |  kefbar.app  (menu-bar agent)  |          |   kefbar  (CLI binary)   |
   |  - MenuBarExtra (SwiftUI)      |          |   set/up/down/mute/get   |
   |     per-speaker Slider + mute  |          +-----------+--------------+
   |  - Settings window             |                      | 1) fast path: connect to
   |     discovery / add / rename   |                      |    app's local IPC socket
   |  - Event-poll loop (live UI)   |<-----IPC socket------+ 2) fallback: talk to
   |  - Local control daemon        |  (Unix domain socket |    speaker directly
   |     (Unix domain socket)       |   ~/.../kefbar/ctl.sock)
   +---------------+----------------+                      |
                   | HTTP (LAN)                            | HTTP (LAN, fallback only)
                   v                                       v
            +--------------------------------------------------+
            |      KEF speaker(s)  --  http://<ip>/api/...      |
            +--------------------------------------------------+

        Shared Swift library:  KEFKit
        - KEF HTTP client (get/set volume, status, firmware, poll, discover)
        - Config model + atomic load/save
        - IPC message types (shared by app server + CLI client)
```

**Key point on "the server":** the only server is a **Unix domain socket** for
local app<->CLI IPC. It is *not* a TCP/web server — nothing binds a network port,
nothing is exposed to the LAN, no firewall prompt, **no sudo**. sudo is only ever
requested for the optional CLI symlink into `/usr/local/bin` (§12).

## 5. KEF W2 HTTP control API (authoritative — verified against pykefcontrol v0.9.3)

Base URL per speaker: `http://<speaker-ip>` (plain HTTP, port 80).

- **Read:** `GET /api/getData?path=<PATH>&roles=value`
  -> JSON array; the value is in element `[0]` under a type key (e.g. `i32_`, `string_`).
- **Write:** `POST /api/setData` with JSON body:
  ```json
  { "path": "player:volume", "roles": "value", "value": { "type": "i32_", "i32_": 30 } }
  ```
  On the W2 platform, **writes are POST** (old firmware was GET-only; if a write
  fails as unsupported, treat the speaker as old firmware — see firmware rule below).

### Paths used

| Purpose            | Path                                        | Type / values                          | Notes |
|--------------------|---------------------------------------------|----------------------------------------|-------|
| Volume (get/set)   | `player:volume`                             | `i32_`, 0-100 (0 = muted)              | primary control |
| Max volume         | `settings:/kef/host/maximumVolume`          | `i32_`                                 | clamp slider/CLI to this |
| Volume limit       | `settings:/kef/host/volumeLimit`            | `i32_`/bool                            | optional |
| Volume step        | `settings:/kef/host/volumeStep`             | `i32_`                                 | default CLI step |
| Power status       | `settings:/kef/host/speakerStatus`          | `string_`: `powerOn` \| `standby`      | show in UI |
| Source             | `settings:/kef/play/physicalSource`         | `string_`: `wifi`/`bluetooth`/`tv`/`optical`/`coaxial`/`analog` | display only in v1 |
| Model name         | `settings:/kef/host/modelName`              | `string_` (e.g. `LSXII`, `LS50WII`)    | confirm exact path via pykefcontrol `speaker_model` |
| Speaker name       | `settings:/deviceName`                      | `string_` (friendly name)              | confirm exact path via pykefcontrol `speaker_name` |
| **Firmware ver.**  | firmware-version path                       | `string_` (e.g. `V27100`)              | confirm exact path via pykefcontrol `firmware_version`; used by firmware rule |
| MAC address        | `settings:/system/primaryMacAddress`        | `string_`                              | **stable identity key** |
| Transport (later)  | `player:player/control`                     | play/pause/next/previous               | not in v1 UI |
| Now playing (later)| `player:player/data`                        | object                                 | not in v1 UI |

> When implementing, confirm `modelName` / `deviceName` / firmware-version exact
> paths against the pykefcontrol source (`KefConnector.speaker_model`,
> `.speaker_name`, `.firmware_version`). Volume, status, MAC and event paths are
> confirmed.

### Firmware rule (per Carlos)

- Opportunistically read the firmware version via `getData` when a speaker is added
  or refreshed, and store/display it.
- If the version reads as old (below a known-good constant we set), **or** a write
  has to fall back to / fails on the GET-only path, show a **non-blocking "update
  firmware via KEF Connect" warning**: an inline note in the app row + a one-line
  note on CLI stderr (still perform the action if it succeeded). Never block volume
  control on it.

### Event poll (live updates from the physical remote)

Long-poll so the UI reflects volume changes made on the remote without busy polling:

1. **Subscribe:** `POST /api/event/modifyQueue` with a body listing paths to watch,
   e.g. `player:volume`, `settings:/kef/host/speakerStatus`
   (each as `{ "path": "...", "type": "itemWithValue" }`). Returns a queue id.
2. **Poll:** `GET /api/event/pollQueue?queueId=<id>&timeout=<seconds>` — blocks up to
   `timeout`, returns changed items immediately when something changes; volume comes
   back under `player:volume` -> `i32_`. Re-issue the poll in a loop.

One poll loop **per speaker** (only for speakers currently shown / powered on).
Handle timeouts, speaker sleep (network iface drops in `standby`), and reconnect.

## 6. Discovery ("scan for any KEF")

Goal: find every KEF W2 speaker on the LAN by the API contract, regardless of model
or firmware. Two-tier:

**A. Fast-path hint — Bonjour (`NWBrowser`).** KEF speakers advertise AirPlay/Cast
(`_airplay._tcp`, `_raop._tcp`, `_googlecast._tcp`) and may expose a KEF-specific
type. Browse those, collect candidate IPs. Do **not** trust these as "a controllable
KEF" — they only give candidate hosts quickly. (Action for the coding session: next
to a live speaker, run `dns-sd -B _services._dns-sd._udp local.` and
`dns-sd -B <type> local.` to see if a `_kef._tcp`-style type exists; if so, add it.)

**B. Source of truth — contract probe.** For each candidate IP (Bonjour hits first,
then, if none/insufficient, sweep the local IPv4 /24 of each active interface):
- `GET http://<ip>/api/getData?path=settings:/system/primaryMacAddress&roles=value`
  with a short timeout (~400 ms).
- If it returns the expected JSON shape -> it's a KEF W2 speaker. Then fetch
  `modelName`, `deviceName`, `maximumVolume`, firmware version to populate the result.
- Concurrency: probe with a bounded task group (e.g. 64 in flight) so a full /24
  finishes in ~1-2 s. Enumerate interfaces/subnets via `getifaddrs`.

**Identity & self-heal:** key a speaker by **MAC**. On every discovery, if a known
MAC appears at a new IP, silently update the stored IP. DHCP changes don't break the
app or CLI. (Still recommend the user set a DHCP reservation.)

## 7. Configuration

Location: `~/Library/Application Support/kefbar/config.json` — **shared by app and
CLI**. Atomic writes (write temp + rename) so the CLI never reads a half-written
file. The app owns writes; the CLI is read-only to config (never mutates it).

```jsonc
{
  "version": 1,
  "defaultSpeakerId": "ab:cd:ef:12:34:56",   // optional; used by CLI/UI default
  "cliStep": 5,                               // default up/down step
  "speakers": [
    {
      "id": "ab:cd:ef:12:34:56",              // MAC — stable key
      "name": "Living Room",                  // user-editable label
      "host": "192.168.1.42",                 // last-known IP
      "model": "LSXII",
      "maxVolume": 100,                        // clamp target
      "firmware": "V27100",                    // last-read firmware version
      "lastSeen": "2026-07-02T10:00:00Z"
    }
  ]
}
```

## 8. KEFKit (shared library)

- `KEFClient(host:)` — async: `volume` get/set, `status`, `source`, `model`, `name`,
  `mac`, `maxVolume`, `firmwareVersion`; `mute`/`unmute` (store & restore prior
  level); `subscribe()/poll()` -> `AsyncStream<SpeakerEvent>`.
- `Discovery` — Bonjour browse + contract-probe sweep -> `[DiscoveredSpeaker]`.
- `Config` — load/save (atomic), resolve default, resolve a selector (name **or** IP).
- `IPCMessage` / `IPCResponse` — Codable types shared by the app's socket server and
  the CLI client (so the wire format can't drift).
- `HTTP` — thin `URLSession` wrapper over native `data(for:)` async.
- Volume clamping helper (0...maxVolume).

Dependency-free and unit-testable against the mock server (§15).

## 9. Menu-bar app (kefbar.app)

- **Agent by default:** `Info.plist` `LSUIElement = true` (no Dock icon). A
  "Show in Dock" toggle flips `NSApp.setActivationPolicy(.regular/.accessory)` at
  runtime. The status-bar item is always present.
- **Menu bar:** SwiftUI `MenuBarExtra(...) { ... }.menuBarExtraStyle(.window)`. The
  window content is the SwiftUI panel directly (no NSPopover/NSHostingController):
  - one row per configured speaker: name + power-status dot (`powerOn`/`standby`);
    horizontal `Slider` 0...maxVolume bound to live volume; mute toggle (mute stores
    prior level; unmute restores).
  - `standby` speakers shown but dimmed; moving the slider may wake the speaker
    (volume write) — verify behaviour.
  - inline firmware-update note on a row when the firmware rule (§5) fires.
  - footer: "Settings...", "Rescan", "Quit".
- **Slider -> speaker throttling:** dragging emits many values. Throttle writes to
  ~8-10/sec and **always send the final value on release**; never queue a backlog.
  Reuse a warm `URLSession` per speaker.
- **Live updates:** the per-speaker event-poll loop updates the slider when volume
  changes on the physical remote. Debounce so remote-echo doesn't fight a live drag.
- **Settings window** — SwiftUI `Settings` scene (standard, near-zero boilerplate;
  app becomes `.regular` while open if agent):
  - Discovered speakers list (from §6) with "Add".
  - Configured speakers: rename, edit IP manually, remove, set default; show model +
    firmware.
  - Toggles: **Launch at login** (§ below), **Show in Dock**, **CLI default step**.
  - Button: **Install command-line tool** (§12).
- **Launch at login:** `SMAppService.mainApp.register()` / `.unregister()`. No sudo,
  no helper bundle, no plist.

## 10. Local control daemon (app-hosted IPC)

- Transport: **Unix domain socket** at `~/Library/Application Support/kefbar/ctl.sock`
  (POSIX `AF_UNIX`). Created on app launch, removed on quit; recreate a stale socket
  file on start.
- Protocol: newline-delimited JSON. One request per line, one response line.
  ```jsonc
  // request
  { "cmd": "set", "speaker": "Living Room", "value": 35 }   // speaker optional (see resolution)
  { "cmd": "up",  "step": 5 }
  { "cmd": "mute" }
  { "cmd": "get" }
  { "cmd": "list" }
  // response
  { "ok": true,  "volume": 40 }
  { "ok": false, "error": "ambiguous speaker; specify --speaker or --host", "speakers": ["Living Room","Study Desk"] }
  ```
- Why route the CLI through the app when it's running: the daemon holds a **warm
  connection** and the **cached current volume** per speaker, so `up/down` needs no
  extra GET round-trip, and it can **coalesce** rapid taps.
- **Coalescing/debounce:** collapse bursts to the LAN — apply the latest target per
  speaker within a small window (e.g. 30-40 ms), last-write-wins. Prevents flooding
  the speaker when the user taps a hardware button several times fast.

## 11. CLI (`kefbar`)

Commands:
```
kefbar get                     # print current volume (0-100) of the resolved speaker
kefbar set <0-100>             # absolute
kefbar up   [step]             # relative (default step = config cliStep)
kefbar down [step]             # relative
kefbar mute
kefbar unmute
kefbar status                  # model, name, power, volume, firmware
kefbar list                    # configured speakers (name -> IP, default marked)
kefbar discover                # run a scan, print found speakers (does NOT write config)
```
Flags: `--speaker <name>` | `--host <ip>` | `--step <n>` | `--json`.

**Speaker resolution (exactly as required):**
1. `--host` given -> use it directly.
2. `--speaker <name>` given -> resolve via config.
3. else if `defaultSpeakerId` set -> use it.
4. else if **exactly one** speaker in config -> use it.
5. else -> **exit non-zero**, print to stderr: `multiple speakers configured; pass
   --speaker <name> or --host <ip>` followed by the list of names/IPs.

**Latency (hard requirement — physical buttons fire in quick succession):**
- Prefer the **daemon fast path**: connect to `ctl.sock`, send one line, read one
  line, exit. Sub-ms IPC; the daemon coalesces bursts and already knows current
  volume (so `up/down` is instant, no GET).
- **Fallback** (app not running / socket absent): read config, talk to the speaker
  directly over HTTP. `set` = one POST. `up/down` = one GET + one POST (still fast on
  LAN). Keep the process lean: no Bonjour, connect straight to the known IP.
- Native binary -> negligible cold-start. Target end-to-end well under ~50 ms on the
  fast path, under ~150 ms on the fallback.

**I/O contract (for scripting / Logi Options+ debugging):**
- Success: resulting volume to stdout (or JSON with `--json`), exit 0.
- Old-firmware warning (§5) goes to **stderr**; exit still 0 if the action worked.
- Failure: clear message to stderr, non-zero exit. Distinct codes: `2` usage/
  resolution, `3` speaker unreachable, `4` speaker firmware too old (write unsupported).

**Logitech / hardware binding (doc note, not code):** the CLI is the integration
surface. Logi Options+ can bind a button to launch a small `.command`/app that runs
`kefbar up 3`; for arbitrary shell actions, BetterTouchTool, Keyboard Maestro, or a
Stream Deck "System: Open" action calling the CLI are more reliable than Options+'s
native scripting. Put a couple of copy-paste examples in the README.

## 12. Privileged operations

- **Normal operation needs no elevated privileges.** Menu-bar app, IPC socket, login
  item (`SMAppService`), discovery, and all speaker control run entirely as the user.
- The **only** sudo/admin moment: the optional "Install command-line tool" button
  symlinks the bundled CLI into `/usr/local/bin/kefbar` so it's on `PATH`:
  ```
  osascript -e 'do shell script "ln -sf \"/Applications/kefbar.app/Contents/Helpers/kefbar\" /usr/local/bin/kefbar" with administrator privileges'
  ```
  This triggers the native macOS admin-password prompt. Provide an "Uninstall CLI"
  that removes the symlink. If declined, the CLI still works when invoked by full
  path from the app bundle.

## 13. Build & packaging

**Repo layout**
```
kefbar/
|- README.md
|- SPEC.md                     # this file
|- Makefile                    # build, app, dmg, clean
|- Package.swift               # KEFKit (lib) + kefbar (CLI executable)
|- Sources/
|  |- KEFKit/                  # shared library
|  |- kefbar/                  # CLI (thin client over KEFKit)
|- App/                        # menu-bar app (Xcode project or SwiftPM app target)
|  |- kefbar.xcodeproj (or Package)  # references ../Sources/KEFKit
|  |- Sources/... (AppKit + SwiftUI)
|  |- Resources/ (icon, Info.plist with LSUIElement=true)
|- Tests/
|  |- KEFKitTests/             # unit tests against the mock server (§15)
|- scripts/
   |- make_dmg.sh              # create-dmg or hdiutil
   |- mock_kef.py              # mock speaker for dev/CI (§15)
```

**Build**
- Library + CLI: `swift build -c release` -> `kefbar` binary.
- App: `xcodebuild -project App/kefbar.xcodeproj -scheme kefbar -configuration Release`
  (or a SwiftPM app-bundle build). App bundles the release `kefbar` binary in
  `Contents/Helpers/`.
- Set the deployment target to **macOS 13.0** on all targets.
- `make` should: build CLI -> build app -> embed CLI -> produce DMG.

**DMG**
- `scripts/make_dmg.sh` uses `create-dmg` (Homebrew) — or plain `hdiutil` — to make a
  drag-to-Applications DMG (app icon + Applications symlink + background).

**Signing / notarisation (deferred):**
- Local builds: **ad-hoc sign** (`codesign -s -`) is fine; on first launch the user
  right-clicks -> Open, or runs `xattr -dr com.apple.quarantine /Applications/kefbar.app`.
- Public releases later: Developer ID sign + notarise + staple in GitHub CI. Out of
  scope now (CI wired later, a la the portkey repo).

## 14. Build order (milestones)

- **M0 — KEFKit client.** `KEFClient` get/set volume, status, model/name/mac/firmware,
  maxVolume, mute/unmute over native async `URLSession`. Prove against the real
  speaker via a throwaway `main`.
- **M1 — CLI (direct/fallback path only).** Full command set + resolution rules +
  exit codes + firmware-warning on stderr, talking straight to the speaker. Carlos
  can bind hardware buttons and it already works, before any GUI exists.
- **M2 — Discovery.** Contract-probe sweep + Bonjour hints; `kefbar discover`.
- **M3 — Menu-bar app.** `MenuBarExtra` + SwiftUI sliders, mute, `Settings`-scene
  window (add/rename/IP), event-poll live updates, launch-at-login (`SMAppService`),
  show-in-Dock. Config shared with CLI.
- **M4 — IPC daemon + CLI fast path.** Unix-socket server in the app; CLI prefers it,
  falls back to M1 path. Add coalescing/debounce.
- **M5 — Packaging.** Embed CLI in app bundle, "Install CLI" button, `make dmg`.

Each milestone must build and be testable on its own. Do M0/M1 first so control
works from day one; the GUI is a layer on a proven core.

## 15. Testing

- **Mock KEF server** (`scripts/mock_kef.py`, or a small Swift stub) implementing
  `getData`/`setData`/`pollQueue` for `player:volume`, status, mac, firmware, etc.
  Lets KEFKit and the CLI be developed and unit-tested without hardware and in CI.
- **Unit tests:** value parsing (`i32_`), setData envelope, volume clamping, speaker
  resolution matrix, config atomic round-trip, firmware-old detection.
- **Integration checklist (real LAN, manual):** discover finds the speaker; slider
  changes volume; physical-remote change moves the slider (poll); rapid `kefbar up`
  taps don't lag or overshoot (coalescing); CLI works with app **on** (fast path) and
  **off** (fallback); DHCP IP change is self-healed via MAC; old-firmware warning
  path fires correctly.

## 16. Decisions (all confirmed with Carlos)

1. **Name: kefbar.** CLI command `kefbar`. Bundle `kefbar.app`. Repo `cjba7/kefbar`.
2. **Swift** for app + CLI + shared lib. macOS only; no Windows/Linux.
3. **macOS floor 13.0 Ventura** — chosen to minimise code: native `MenuBarExtra` +
   `SMAppService` + native async `URLSession`, zero back-compat workarounds. Still
   installs on 2017-and-later Macs. Least code is an explicit priority (a human is
   unlikely to read or edit this).
4. **v1 scope:** volume + mute + power-status only. No source/transport UI.
5. **Firmware:** minimum-firmware acceptable; read version via `getData` and warn to
   update when old / when a write hits the GET-only path (non-blocking).
6. **CLI = thin client to an app-hosted Unix-socket daemon, with direct-to-speaker
   fallback.** Local socket, not a web server; **no sudo**. Works with the app off.
7. **Speaker identity keyed by MAC** so DHCP IP changes self-heal.
8. **sudo only** for the optional `/usr/local/bin/kefbar` symlink.

## 17. References

- pykefcontrol (API behaviour we mirror): https://github.com/N0ciple/pykefcontrol
- kef-mcp (confirms POST /api/setData, GET /api/getData on W2): https://glama.ai/mcp/servers/nqrwhal/kef-mcp
- kefctl (older LSX/LS50W reverse-engineering notes): https://github.com/kraih/kefctl
- Apple: `MenuBarExtra`, `SMAppService`, SwiftUI `Settings` scene, `NWBrowser`,
  `Network` (`AF_UNIX`).
