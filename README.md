# deskFetch

**[fastfetch](https://github.com/fastfetch-cli/fastfetch) as native macOS desktop widgets.**

Your system info and ASCII logo, on your desktop, with real colors — not a
terminal window parked in the corner, but actual WidgetKit widgets you place,
resize, and arrange like any other macOS widget.

It reads your own `~/.config/fastfetch/config.jsonc`, so the modules and logo
colors match exactly what you see in your terminal.

## Widgets

| Widget | Shows | Sizes |
| --- | --- | --- |
| **deskFetch** | System info | Small, Medium, Large, Extra Large |
| **deskFetch Logo** | ASCII logo only | Small, Medium, Large, Extra Large |
| **deskFetch Combo** | Logo + info, side by side | Medium, Large, Extra Large |

Small and Medium show a compact set (OS, host, uptime, memory, battery). Large
and Extra Large show your full module list.

## Requirements

- macOS 14 or later
- [fastfetch](https://github.com/fastfetch-cli/fastfetch) — `brew install fastfetch`
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- Xcode, plus an Apple Developer Team ID (a **free** personal team works)

## Install

```bash
git clone https://github.com/frotzilla/deskFetch.git
cd deskFetch
DEVELOPMENT_TEAM=XXXXXXXXXX ./build.sh --install
```

Find your team ID with `security find-identity -v -p codesigning` — it's the
value in parentheses.

Then right-click the desktop → **Edit Widgets** → search **deskFetch**, and drag
the ones you want.

macOS caches the widget gallery aggressively. If a widget or a size doesn't
appear, remove and re-add it; if that fails, log out and back in.

### If fastfetch isn't found

deskFetch looks in the usual places (Homebrew on both architectures, MacPorts,
Nix, `/usr/bin`) — an app launched from Finder gets a minimal `PATH`, so it
can't just rely on that. If yours lives somewhere unusual, point at it directly:

```bash
defaults write com.redwanh.deskfetch fastfetchPath /path/to/fastfetch
```

## How it works

A WidgetKit extension is sandboxed and can't execute binaries, so a widget
can't run `fastfetch` itself. deskFetch is therefore two pieces:

- **deskFetch.app** — a menu bar app (no Dock icon). Runs `fastfetch` every 10
  seconds and serves the output over loopback on `127.0.0.1:51423`
  (`/compact`, `/full`, `/logo`), then tells WidgetKit to reload.
- **deskFetchWidget.appex** — the widgets. They fetch from that local endpoint
  and render it, parsing ANSI escape codes into colored SwiftUI text.

The menu bar app has to be running for the widgets to update. It does **not**
add itself to your login items — turn that on yourself with **Launch at Login**
in the menu bar icon, which is also where you quit it.

### Fitting text to a widget

Widgets can't scroll, so text is sized to fit exactly. Two things that turned
out to matter:

- SwiftUI rounds line height up to whole points, so font size is chosen by
  searching over **integer line heights** rather than continuously. A
  continuous search converges exactly onto a rounding boundary, where being off
  by a hair costs a full point on *every* line — enough to clip a 17-row logo.
- The ASCII logo is laid out at a fixed reference size and scaled
  geometrically, which keeps the art intact at any widget size.

## Refresh rate

The menu bar app polls every 10 seconds, but macOS throttles how often it
actually redraws a desktop widget — expect updates every few minutes, not
seconds. That's a WidgetKit limitation and no app can override it.

## Building for other people

Builds are signed with your own development certificate, which is tied to your
machine, so the resulting `.app` won't launch on anyone else's Mac. Shipping it
would require a paid Apple Developer Program membership for a Developer ID
certificate plus notarization. Clone and build is the intended path.

## License

MIT — see [LICENSE](LICENSE).
