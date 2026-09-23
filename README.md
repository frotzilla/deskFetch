# Fastfetch Widgets

macOS desktop widgets that display [fastfetch](https://github.com/fastfetch-cli/fastfetch)
output — your system info and ASCII logo, rendered with real colors, on your desktop.

Uses whatever is in your own `~/.config/fastfetch/config.jsonc`, so the modules
and logo colors match what you see in your terminal.

## Widgets

| Widget | Shows | Sizes |
| --- | --- | --- |
| **Fastfetch** | System info text | Small, Medium, Large, Extra Large |
| **Fastfetch Logo** | ASCII logo only | Small, Medium, Large, Extra Large |
| **Fastfetch Combo** | Logo + info, side by side | Medium, Large, Extra Large |

Small and Medium show a compact set (OS, host, uptime, memory, battery); Large
and Extra Large show your full module list.

## Requirements

- macOS 14 or later
- [fastfetch](https://github.com/fastfetch-cli/fastfetch) — `brew install fastfetch`
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- Xcode, and an Apple Developer Team ID (a **free** personal team is enough)

## Build

```bash
DEVELOPMENT_TEAM=XXXXXXXXXX ./build.sh --install
```

Find your team ID with `security find-identity -v -p codesigning` — it's the
value in parentheses. Then add the widgets: right-click the desktop → **Edit
Widgets** → search "Fastfetch".

macOS caches the widget gallery aggressively. If a widget or size doesn't show
up, remove and re-add it; if that fails, log out and back in.

## How it works

WidgetKit extensions are sandboxed and can't execute binaries, so a widget
can't run `fastfetch` itself. Instead:

- **FastfetchWidgetHost** is a menu bar app (no Dock icon). It runs `fastfetch`
  every 10 seconds and serves the output over loopback on `127.0.0.1:51423`
  (`/compact`, `/full`, `/logo`), then asks WidgetKit to reload.
- **FastfetchWidgetExtension** fetches from that local endpoint and renders it,
  parsing the ANSI escape codes into colored SwiftUI text.

The host app must be running for the widgets to update; it registers itself as
a login item so it starts automatically. Quit it from the menu bar icon.

### Text fitting

Widgets can't scroll, so text is sized to fit the space exactly. Two details
that turned out to matter:

- SwiftUI rounds line height up to whole points, so the font size is chosen by
  searching over *integer line heights* rather than continuously — otherwise the
  search lands exactly on a rounding boundary and a 1pt error becomes a full
  point of overflow on every line.
- The ASCII logo is laid out at a fixed reference size and scaled
  geometrically, which keeps the art intact at any widget size.

## Refresh rate

The host app polls every 10 seconds, but macOS throttles how often it actually
redraws a desktop widget — expect updates every few minutes, not seconds. This
is a WidgetKit limitation, not something the app can override.

## Note on distribution

Builds are signed with your own development certificate, which is tied to your
machine. That's fine for personal use, but the resulting `.app` won't launch on
anyone else's Mac. Distributing it would need a paid Apple Developer Program
membership for a Developer ID certificate plus notarization.

## License

MIT — see [LICENSE](LICENSE).
