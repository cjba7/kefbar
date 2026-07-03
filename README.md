<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# kefbar

**Control your KEF speakers' volume from the macOS menu bar.**

A tiny, calm menu-bar app (with an optional command-line tool) for [KEF][kef]
wireless speakers: LSX II, LS50 Wireless II, LS60 Wireless, and other W2-platform
models. It talks straight to the speaker on your own network. No cloud, no account,
no KEF Connect app.

<p align="center">
  <img src="docs/screenshots/panel.png" alt="kefbar menu-bar panel" width="340">
</p>

## Why

You just want to nudge the volume, and reaching for a phone app or the remote is
friction. kefbar puts a fader and mute one click away in the menu bar, keeps in sync
when the volume changes elsewhere, and can bind to a hardware knob or key.

## Features

- **Volume and mute** per speaker, with a live fader and the level shown large.
- **Power at a glance.** A Uni-Q status ring shows on, standby, or unreachable.
- **Several speakers.** Each on its own row; standby ones dim.
- **Stays in sync.** Change the volume from the remote or KEF Connect and the fader follows.
- **Make it yours.** Four calm palettes, plus Light, Dark, or Match-macOS appearance.
- **Command line.** A `kefbar` tool for scripts and hardware keys.

## Install

1. Download **`kefbar-<version>.dmg`** from [Releases][releases].
2. Open it and drag **kefbar** to **Applications**.
3. First launch: right-click the app and choose **Open** (it isn't notarized yet, so
   Gatekeeper asks once).
4. Click **Allow** when macOS asks for **Local Network** access, which kefbar needs to
   reach your speaker.

kefbar lives in the menu bar, not the Dock. Turn on **Launch at login** in Settings to
keep it there.

## Using it

Click the speaker icon in the menu bar:

- Drag the fader to set the volume; click the speaker glyph to mute or unmute.
- The Uni-Q ring shows power: lit when on, faint on standby, amber if unreachable.
- Open **Settings** to add speakers and change the look.

### Settings

<p align="center">
  <img src="docs/screenshots/settings.png" alt="kefbar Settings" width="520">
</p>

Four tabs:

- **Speakers.** Click **Rescan** to find speakers on your network, then **Add**, rename,
  set a default, or remove.
- **General.** Launch at login.
- **CLI.** Install the command-line tool and set its default step.
- **UI.** Pick a palette (Lavender, Dark Olive, Sea Grey, Brown Olive) and appearance.

## Command line (optional)

Handy for wiring volume to a hardware knob, Stream Deck, or keyboard shortcut. Install it
from **Settings, CLI, Install CLI**, then:

```sh
kefbar get                # current volume (0 to 100)
kefbar set 30             # set an absolute volume
kefbar up 3               # raise by 3
kefbar down 3             # lower by 3
kefbar mute               # mute (remembers the level)
kefbar unmute             # restore it
kefbar status             # model, power, volume, firmware
kefbar list               # your configured speakers
kefbar discover           # find speakers on the network
```

Flags: `--speaker <name>`, `--host <ip>`, `--json`.

**Bind to hardware keys.** Point Logi Options+, BetterTouchTool, Keyboard Maestro, or a
Stream Deck at `/usr/local/bin/kefbar up 3` (or `down 3`). Rapid taps are safe: they
serialise, so five quick presses sum correctly instead of racing. The first time a
launcher app runs `kefbar`, grant **that app** Local Network access too.

## Requirements

- macOS 13 (Ventura) or later
- A KEF **W2-platform** speaker on your network: LSX II, LSX II LT, LS50 Wireless II,
  or LS60 Wireless.

## Build from source

```sh
make app        # build kefbar.app into ./build
make dmg        # package a drag-to-Applications DMG
make test       # run the unit tests
make release    # just the CLI, into .build/release/kefbar
```

See [`SPEC.md`](SPEC.md) for the full design, and [`TODO.md`](TODO.md) for what's next.

## License

[GPL-3.0-or-later](LICENSE).

[kef]: https://www.kef.com/
[releases]: https://github.com/cjba7/kefbar/releases
