# kefbar — build spec

A tiny, open-source macOS app + CLI to control the volume of KEF W2-platform
wireless speakers (LSX II, LSX II LT, LS50 Wireless II, LS60 Wireless) from the
menu bar and the command line. No cloud, no KEF Connect app, no remote — just the
speaker's own local HTTP API on the LAN.

This document is the authoritative brief. Build in the milestone order in §14.
Everything the speaker API does is pinned in §5 — do not re-guess it. All design
decisions are settled (§16); do not reopen them.

**License:** GPL-3.0-or-later. `LICENSE` file with full text;
`SPDX-License-Identifier: GPL-3.0-or-later` header in every source file.

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
- Discover any KEF W2 speaker on the LAN.
- Persist multiple speakers (name + IP, keyed by MAC so IP changes self-heal).
- Per-speaker volume slider + mute in a menu-bar popover.
- Live-reflect changes made on the physical remote OR the CLI (event poll).
- CLI: set / up / down / mute / unmute / get, fast and correct under rapid taps.
- Ship as a drag-to-Applications DMG. Built locally for now.

**Non-goals (v1)**
- No streaming / source selection / transport control in the UI (API supports it;
  leave hooks, build no UI). Volume + mute + power status only.
- No IPC daemon (cut — see §16). No multi-user, no EQ, no per-app volume.
- No notarised public release yet (local builds; GitHub CI later).
- No Windows/Linux. macOS only.

## 3. Platform & tooling

- **Language:** Swift, for all three parts (app, CLI, shared lib). One language; the
  CLI compiles to a fast native binary — no interpreter start-up cost.
- **macOS floor: 13.0 (Ventura).** Chosen to minimise code: use native high-level
  APIs directly, zero back-compat workarounds.
  - Menu bar: SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)` (13+).
  - Launch at login: `SMAppService.mainApp.register()/unregister()` (13+).
  - Networking: native `URLSession.data(for:)` (12+).
  - Ventura installs on 2017-and-later Macs, so the floor costs little real reach.
- **UI:** pure SwiftUI App lifecycle — a `MenuBarExtra` scene + a `Settings` scene.
- **Bundle id:** `com.cjba7.kefbar`.
- **Build:** SwiftPM package for `KEFKit` (library) + `kefbar` (CLI executable); an
  Xcode project (or SwiftPM app-bundle build) for the app, referencing `KEFKit`.
  `Makefile` drives build + DMG. Deployment target macOS 13.0 on all targets.
- **No third-party runtime deps.** Foundation + SwiftUI + Network (`NWBrowser`) only.

## 4. Architecture

There is **no server and no IPC**. The app and the CLI are independent processes
that share a config file and each talk directly to the speaker over HTTP. The app's
event-poll loop keeps its sliders in sync with whatever changes volume (remote or
CLI). The CLI serialises its own rapid invocations with an `flock` lockfile (§10).

```
              ~/Library/Application Support/kefbar/config.json
              (speakers: name, IP, MAC, maxVolume, firmware) — single source of truth
                        ^                              ^
                        | read/write                   | read-only
                        |                              |
   +--------------------+------------+   +-------------+------------------+
   |  kefbar.app (menu-bar agent)    |   |  kefbar (CLI binary)           |
   |  - MenuBarExtra: per-speaker    |   |  set/up/down/mute/unmute/get   |
   |    Slider + mute                |   |  - always talks direct to      |
   |  - Settings scene: discover/    |   |    speaker (no daemon)         |
   |    add/rename/IP                |   |  - flock lockfile serialises   |
   |  - Event-poll loop -> live UI   |   |    rapid up/down (§10)         |
   +----------------+----------------+   +-------------+------------------+
                    | HTTP (LAN)                       | HTTP (LAN)
                    v                                  v
             +-----------------------------------------------+
             |     KEF speaker(s)  --  http://<ip>/api/...    |
             +-----------------------------------------------+

        Shared Swift library: KEFKit
        - KEF HTTP client (get/set volume, status, firmware, poll, discover)
        - Config model + atomic load/save
```

**No sudo** for any of this. sudo is only ever requested for the optional CLI symlink
into `/usr/local/bin` (§12).

## 5. KEF W2 HTTP control API (authoritative — verified against pykefcontrol v0.9.3)

Base URL per speaker: `http://<speaker-ip>` (plain HTTP, port 80).

- **Read:** `GET /api/getData?path=<PATH>&roles=value`
  -> JSON array; value in element `[0]` under a type key (e.g. `i32_`, `string_`).
- **Write:** `POST /api/setData` with JSON body:
  ```json
  { "path": "player:volume", "roles": "value", "value": { "type": "i32_", "i32_": 30 } }
  ```
  On W2, **writes are POST** (old firmware was GET-only — see firmware rule).

### Paths used

| Purpose            | Path                                        | Type / values                          | Notes |
|--------------------|---------------------------------------------|----------------------------------------|-------|
| Volume (get/set)   | `player:volume`                             | `i32_`, 0-100 (0 = muted)              | primary control |
| Max volume         | `settings:/kef/host/maximumVolume`          | `i32_`                                 | clamp slider/CLI to this |
| Power status       | `settings:/kef/host/speakerStatus`          | `string_`: `powerOn` \| `standby`      | show in UI |
| Source             | `settings:/kef/play/physicalSource`         | `string_`: `wifi`/`bluetooth`/`tv`/`optical`/`coaxial`/`analog` | display only in v1 |
| Model name         | `settings:/kef/host/modelName`              | `string_` (e.g. `LSXII`, `LS50WII`)    | confirm exact path via pykefcontrol `speaker_model` |
| Speaker name       | `settings:/deviceName`                      | `string_`                              | confirm exact path via pykefcontrol `speaker_name` |
| Firmware version   | firmware-version path                       | `string_` (e.g. `V27100`)              | confirm exact path via pykefcontrol `firmware_version`; store for display |
| MAC address        | `settings:/system/primaryMacAddress`        | `string_`                              | **stable identity key** |

> Confirm `modelName`/`deviceName`/firmware paths against the live speaker + the
> pykefcontrol source before coding (see the M0/discovery verification step).
> Volume, status and MAC paths are confirmed.

### Firmware rule (behavioural only — settled)

Do **not** parse or threshold the firmware version. Warn **only** when a write has to
fall back to / fails on the GET-only path (i.e. genuinely old firmware). The warning
is **non-blocking**: an inline note on the app row + a one-line note on CLI stderr;
if the action itself succeeded, CLI exit stays 0. Firmware version is still read and
displayed (in `status` / Settings), but never gates behaviour.

### Event poll (live updates)

Long-poll so the UI reflects volume changes from the remote **or** the CLI:

1. **Subscribe:** `POST /api/event/modifyQueue` listing paths to watch
   (`player:volume`, `settings:/kef/host/speakerStatus`), each
   `{ "path": "...", "type": "itemWithValue" }`. Returns a queue id.
2. **Poll:** `GET /api/event/pollQueue?queueId=<id>&timeout=<seconds>` — blocks up to
   `timeout`, returns changes immediately; volume comes back as `player:volume` ->
   `i32_`. Re-issue in a loop. One loop per shown/powered speaker; handle timeout,
   standby (iface drops), reconnect.

## 6. Discovery ("scan for any KEF") — Bonjour-first, subnet fallback

**Primary — Bonjour (`NWBrowser`), fastest.** KEF speakers advertise on the LAN. The
**exact mDNS service type must be confirmed against the live LSX II** during M0/M2
(browse `_services._dns-sd._udp local.` and known types `_kef._tcp`, `_airplay._tcp`,
`_raop._tcp`, `_googlecast._tcp`; resolve the LSX II instance for host + TXT). Pin the
confirmed type in code. Browse it, resolve instances to IPs.

**Confirm each hit + fallback — contract probe.** For each Bonjour IP (and, if Bonjour
yields nothing, sweep the local IPv4 /24 of each active interface via `getifaddrs`):
- `GET http://<ip>/api/getData?path=settings:/system/primaryMacAddress&roles=value`,
  ~400 ms timeout. Expected JSON shape -> it's a KEF W2 speaker.
- Then fetch `modelName`, `deviceName`, `maximumVolume`, firmware to populate the row.
- Bounded task group (~64 in flight); a full /24 finishes in ~1-2 s.

**Identity & self-heal:** key by **MAC**. If a known MAC appears at a new IP, silently
update the stored IP. (Still recommend a DHCP reservation.)

## 7. Configuration

`~/Library/Application Support/kefbar/config.json` — **shared by app and CLI**. Atomic
writes (temp + rename). App owns writes; CLI is read-only to config.

```jsonc
{
  "version": 1,
  "defaultSpeakerId": "ab:cd:ef:12:34:56",   // optional; CLI/UI default
  "cliStep": 5,                               // default up/down step; bounded 1-10
  "speakers": [
    {
      "id": "ab:cd:ef:12:34:56",              // MAC — stable key
      "name": "Living Room",
      "host": "192.168.1.42",
      "model": "LSXII",
      "maxVolume": 100,
      "firmware": "V27100",
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
- `Config` — load/save (atomic), resolve default, resolve a selector (name or IP),
  clamp helpers (volume 0...maxVolume; step 1...10).
- `HTTP` — thin `URLSession` wrapper over native `data(for:)` async.

Dependency-free and unit-testable against the mock server (§15).

## 9. Menu-bar app (kefbar.app)

- **Agent by default:** `Info.plist` `LSUIElement = true` (no Dock icon). "Show in
  Dock" toggle flips `NSApp.setActivationPolicy(.regular/.accessory)`. Menu-bar item
  always present; icon = SF Symbol `speaker.wave.2`.
- **Menu bar:** SwiftUI `MenuBarExtra(...) { ... }.menuBarExtraStyle(.window)`; content
  is the SwiftUI panel directly. One row per configured speaker: name + power-status
  dot; horizontal `Slider` 0...maxVolume bound to live volume; mute toggle (stores/
  restores prior level). `standby` speakers dimmed; moving the slider may wake the
  speaker — verify. Inline firmware note when the rule (§5) fires. Footer:
  "Settings...", "Rescan", "Quit".
- **Slider -> speaker throttling:** dragging emits many values. Throttle writes to
  ~8-10/sec and always send the final value on release; no backlog. Warm `URLSession`
  per speaker.
- **Live updates:** per-speaker event-poll loop updates the slider on volume changes
  from the remote or the CLI. Debounce so remote-echo doesn't fight a live drag.
- **Settings scene** (SwiftUI `Settings`, near-zero boilerplate; app -> `.regular`
  while open if agent): discovered list with "Add"; configured speakers rename / edit
  IP / remove / set default, showing model + firmware; toggles for **Launch at
  login**, **Show in Dock**, **CLI default step** (1-10). Button: **Install CLI** (§12).
- **Launch at login:** `SMAppService.mainApp.register()` / `.unregister()`. No sudo.

## 10. CLI concurrency & serialisation (flock)

No daemon. To keep rapid physical-button taps **correct** (five `kefbar up` processes
must not each read the same base and all write base+step), relative `up`/`down` wrap
their read-modify-write in an exclusive `flock` on
`~/Library/Application Support/kefbar/cli.lock`:

1. open + `flock(LOCK_EX)` (blocks briefly if another invocation holds it),
2. GET current volume, compute clamped target (0...maxVolume, step 1...10),
3. POST new volume, release the lock.

Serialised, so N taps sum correctly. Absolute `set` is idempotent (last-write-wins)
and does **not** take the lock. This replaces the former IPC daemon at ~10 lines.

## 11. CLI (`kefbar`)

```
kefbar get                     # current volume (0-100) of the resolved speaker
kefbar set <0-100>             # absolute (clamped to maxVolume)
kefbar up   [step]             # relative; step default = cliStep (5), max 10
kefbar down [step]             # relative; step default = cliStep (5), max 10
kefbar mute
kefbar unmute
kefbar status                  # model, name, power, volume, firmware
kefbar list                    # configured speakers (name -> IP, default marked)
kefbar discover                # scan + print found speakers (does NOT write config)
```
Flags: `--speaker <name>` | `--host <ip>` | `--step <n>` | `--json`.

**Step bound (settled):** any step — CLI arg or configured default — must be an
integer **1-10**. `up`/`down` with step > 10 (or < 1) -> exit non-zero, stderr
`step must be 1-10`. Guards against a typo like `up 100` deafening the user.

**Speaker resolution:**
1. `--host` -> use directly.
2. `--speaker <name>` -> resolve via config.
3. else `defaultSpeakerId` if set.
4. else if **exactly one** speaker in config -> use it.
5. else -> exit non-zero, stderr `multiple speakers configured; pass --speaker <name>
   or --host <ip>` + the list.

**Latency:** always direct to the speaker. `set` = one POST. `up`/`down` = one GET +
one POST under the flock. Native binary -> negligible cold-start; keep the process
lean (no Bonjour, connect straight to the known IP). Target well under ~150 ms.

**I/O contract:** success -> resulting volume to stdout (or `--json`), exit 0.
Old-firmware warning -> stderr, exit still 0 if the action worked. Failure -> stderr +
non-zero. Codes: `2` usage/resolution, `3` unreachable, `4` firmware too old
(write unsupported).

**Logitech / hardware binding (README note):** the CLI is the integration surface.
Logi Options+ can launch a small `.command` running `kefbar up 3`; for arbitrary
shell actions, BetterTouchTool / Keyboard Maestro / Stream Deck calling the CLI are
more reliable. Include copy-paste examples in the README.

## 12. Privileged operations

- **Normal operation needs no elevated privileges** — app, login item, discovery,
  CLI, all run as the user.
- Only sudo moment: optional "Install command-line tool" symlinks the bundled CLI to
  `/usr/local/bin/kefbar`:
  ```
  osascript -e 'do shell script "ln -sf \"/Applications/kefbar.app/Contents/Helpers/kefbar\" /usr/local/bin/kefbar" with administrator privileges'
  ```
  Native admin-password prompt. Provide "Uninstall CLI". If declined, the CLI still
  works via its full bundle path.

## 13. Build & packaging

**Repo layout**
```
kefbar/
|- README.md
|- LICENSE                     # GPL-3.0
|- SPEC.md                     # this file
|- Makefile                    # build, app, dmg, clean
|- Package.swift               # KEFKit (lib) + kefbar (CLI executable)
|- Sources/
|  |- KEFKit/
|  |- kefbar/                  # CLI
|- App/                        # menu-bar app (Xcode project or SwiftPM app target)
|  |- kefbar.xcodeproj (or Package)   # references ../Sources/KEFKit
|  |- Sources/... (SwiftUI)
|  |- Resources/ (icon, Info.plist with LSUIElement=true)
|- Tests/
|  |- KEFKitTests/             # unit tests vs mock server (§15)
|- scripts/
   |- make_dmg.sh
   |- mock_kef.py              # mock speaker for dev/CI (§15)
```

**Build**
- Library + CLI: `swift build -c release` -> `kefbar` binary.
- App: `xcodebuild -project App/kefbar.xcodeproj -scheme kefbar -configuration Release`
  (or SwiftPM app-bundle). App bundles the release `kefbar` in `Contents/Helpers/`.
- `make`: build CLI -> build app -> embed CLI -> produce DMG.
- Every source file carries the SPDX GPL-3.0-or-later header.

**DMG:** `scripts/make_dmg.sh` via `create-dmg` (Homebrew) or `hdiutil` — drag-to-
Applications (app icon + Applications symlink + background).

**Signing / notarisation (deferred):** local builds ad-hoc sign (`codesign -s -`);
first launch is right-click -> Open or `xattr -dr com.apple.quarantine
/Applications/kefbar.app`. Developer ID + notarise + staple comes with GitHub CI later.

## 14. Build order (milestones)

- **M0 — KEFKit.** `KEFClient` (volume get/set, status, model/name/mac/firmware,
  maxVolume, mute/unmute) over native async `URLSession`; `Config` atomic load/save;
  `scripts/mock_kef.py`. First verify §5 paths + the Bonjour type against the live
  LSX II, then implement. Prove via a throwaway `main`.
- **M1 — CLI.** Full command set, resolution rules, step bound (1-10), exit codes,
  firmware-warning on stderr, `flock` serialisation (§10) — direct to speaker. After
  this, hardware buttons work with no GUI.
- **M2 — Discovery.** Bonjour (confirmed type) + subnet fallback; `kefbar discover`.
- **M3 — Menu-bar app.** `MenuBarExtra` + SwiftUI sliders, mute, `Settings`-scene
  window (add/rename/IP), event-poll live updates, launch-at-login (`SMAppService`),
  show-in-Dock. Shares config with the CLI.
- **M4 — Packaging.** Embed CLI in the bundle, "Install CLI" button, `make dmg`.

Each milestone builds and is testable alone. M0/M1 first so control works day one.

## 15. Testing

- **Mock KEF server** (`scripts/mock_kef.py`, or a small Swift stub) implementing
  `getData`/`setData`/`pollQueue` for `player:volume`, status, mac, firmware — dev +
  CI without hardware.
- **Unit tests:** `i32_` parsing, setData envelope, volume clamp, **step 1-10 bound**,
  speaker-resolution matrix, config atomic round-trip.
- **Integration (real LAN, manual):** discover finds the LSX II; slider changes
  volume; remote change moves the slider (poll); rapid `kefbar up` taps sum correctly
  (flock) and don't overshoot; step > 10 is rejected; DHCP IP change self-heals via
  MAC; old-firmware warning path fires when applicable.

## 16. Decisions (all settled — do not reopen)

1. **Name:** kefbar. CLI `kefbar`, bundle `com.cjba7.kefbar`, repo `cjba7/kefbar`.
2. **Swift** for app + CLI + shared lib. macOS only.
3. **macOS floor 13.0 Ventura** — least code via native `MenuBarExtra` + `SMAppService`
   + native async `URLSession`. Installs on 2017+ Macs. Least code is the priority.
4. **v1 scope:** volume + mute + power-status only. No source/transport UI.
5. **Firmware: behavioural warning only** — warn (non-blocking) only when a write hits
   the GET-only path. No version parsing/threshold. Version still shown.
6. **No IPC daemon.** CLI always talks direct to the speaker; rapid `up`/`down`
   serialised with an `flock` lockfile (§10). App hosts nothing. No sudo except §12.
7. **Discovery: Bonjour-first, subnet fallback.** Exact mDNS type confirmed against
   the live LSX II, then pinned in code.
8. **Speaker identity keyed by MAC** — DHCP IP changes self-heal.
9. **Default step 5; step bounded 1-10** (CLI arg and configured default); >10 errors.
   Absolute `set` clamped 0...maxVolume.
10. **License GPL-3.0-or-later**; SPDX header in every source file.
11. **sudo only** for the optional `/usr/local/bin/kefbar` symlink.

## 17. References

- pykefcontrol (API behaviour we mirror): https://github.com/N0ciple/pykefcontrol
- kef-mcp (confirms POST /api/setData, GET /api/getData on W2): https://glama.ai/mcp/servers/nqrwhal/kef-mcp
- kefctl (older LSX/LS50W notes): https://github.com/kraih/kefctl
- Apple: `MenuBarExtra`, `SMAppService`, SwiftUI `Settings` scene, `NWBrowser`.
