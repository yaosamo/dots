# Dots

A native macOS accessory overlay: four 16pt dots hang from the top of the screen, and the two interactive dots morph into their widgets.

- **First dot** — morphs into a circular live selfie camera
- **Second dot** — morphs into a task list (add, complete, delete; persists locally)
- **Third and fourth** — decorative

The panel is borderless, always on top, and click-through around the visible controls. On macOS 26 and newer, SwiftUI's native Liquid Glass container and matched glass identities animate each dot into its expanded shape. macOS 14 and 15 use a material-backed matched-geometry fallback, and Reduce Motion switches both paths to an immediate state change.

## Requirements

- macOS 14+
- Xcode 26+

## Run

Open `Dots.xcodeproj` in Xcode and run the **Dots** scheme.

There is no Dock icon. Look at the **top center** of the display.

## Use

- Click the first or second dot to open its widget
- Click the expanded camera or the task list's **×** button to close it
- Type a task and press Return or **+**
- Right-click a dot → **Quit Dots**, or Cmd+Q after the panel is key

## Tests

```sh
xcodebuild test -project Dots.xcodeproj -scheme Dots -destination 'platform=macOS'
```
