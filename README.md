# CursorLevel

macOS utility that keeps the mouse pointer at the same **physical** height when it crosses between two external displays that share a logical resolution but not a physical size.

macOS treats those screens as equally tall. If they are aligned at the bottom of the desk, the pointer arrives too high or too low. CursorLevel remaps Y at the shared edge.

## Default layout

| Role | Size | Logical resolution | Position |
| --- | --- | --- | --- |
| Left | read from the panel | any | Top row, left |
| Right | read from the panel | any | Top row, right |
| MacBook | any | any | Below the externals, left unchanged |

Physical size comes from the display over EDID (`CGDisplayScreenSize`), so any pair
of external monitors works without editing anything. Names come from
`NSScreen.localizedName`. The diagonals in `CursorLevel/Config.swift` are only a
fallback for panels that report nothing usable; the menu shows which sizes are in
use.

## Mapping

Y is measured from the shared edge, the **bottom** one on a normal desk. Which edge
that is comes from the display arrangement: displays of differing pixel height reveal
whether you lined up their tops or their bottoms. Equal pixel heights line up on both
edges at once, so those fall back to `alignmentBottom`.

- Distance from the bottom × `source inches / target inches` × `target pixel height / source pixel height`
- The second factor is 1 when both displays share a pixel height, which reduces the mapping to the diagonal ratio alone
- Where the taller display rises above the shorter one, that band has no physical neighbour. Crossing out of it is blocked; moving down on the taller display still works.
- Transitions to and from the MacBook display are not modified.

If either external is disconnected, correction pauses and the pointer behaves as macOS would without the app.

## Requirements

- macOS 13 or later
- Apple Silicon (`scripts/build.sh` builds `arm64`)
- Xcode Command Line Tools (`xcode-select --install`)
- A real code-signing identity (Apple Development). Ad-hoc signing usually makes Accessibility fail.

The bundle identifier is `com.cursorlevel.CursorLevel`. Override signing with:

```sh
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build.sh
```

## Build, install, and disk image

```sh
chmod +x scripts/build.sh
./scripts/build.sh
open /Applications/CursorLevel.app
```

The script:

1. Builds `dist/CursorLevel.app`
2. Copies it to `/Applications/CursorLevel.app`
3. Writes **`dist/CursorLevel.dmg`** for GitHub Releases (app + Applications shortcut)

A DMG is the usual way to ship a macOS app. Users open it and drag CursorLevel into Applications. A zip of the `.app` also works; Gatekeeper still warns until the build is notarized with an Apple Developer account.

Run the installed copy **from `/Applications`**. A binary launched from `dist/` is a different file to macOS, so Accessibility granted for one will not apply to the other.

## Accessibility

CursorLevel cannot correct the pointer without Accessibility access.

1. Launch `/Applications/CursorLevel.app`.
2. Open **System Settings → Privacy & Security → Accessibility**.
3. Add `/Applications/CursorLevel.app` with **+** and turn it on.
4. Quit and reopen the app.

Repeat after a new signature or a different install path.

## Controls

The status item is only a control surface:

| Control | Purpose |
| --- | --- |
| Status | Active, off, setup, or missing displays |
| Correction | Enable or disable remapping |
| Rediscover displays | After plugging or rearranging screens |
| Accessibility settings… | Opens System Settings |
| Open at login | Login item (use the `/Applications` copy) |
| Diagnostics | Event-tap counters, hidden by default |
| Quit | Stop the utility |

## Changing the layout

Most setups need no changes: sizes are measured and left/right comes from the actual
screen positions. Edit `CursorLevel/Config.swift` only for the rest:

```swift
var left = DisplaySpec(name: "", diagonalInches: 27, width: 2560, height: 1440)
var right = DisplaySpec(name: "", diagonalInches: 31.5, width: 2560, height: 1440)
var alignmentBottom = true
```

| Field | When to touch it |
| --- | --- |
| `diagonalInches` | Only if a panel reports no usable physical size |
| `width` / `height` | To force which pair is picked when more than two externals are in the top row |
| `name` | To pin a display by name; empty matches by resolution and position |
| `alignmentBottom` | Only when both displays share a pixel height; otherwise the arrangement decides |

Names such as “Built-in” or “Liquid Retina” are always ignored. Rebuild after changing the file.

## Known limitation

When the pointer moves **slowly** across the shared edge, macOS draws it on both screens at the same logical Y for a moment. A sliver appears on the destination at the wrong physical height until the pointer is fully on that display and the correction applies. That is window-server behaviour, not the mapping formula.

## License

MIT. See `LICENSE`.

[roesner.tech](https://roesner.tech)
