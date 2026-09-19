# Dots

A native macOS accessory overlay: four 16pt black dots hang from the top of the screen.

- **First dot** — circular live selfie camera
- **Second dot** — task list (add, complete, delete; persists locally)
- **Third and fourth** — decorative

The panel is borderless, always on top, and click-through around the dots. Widgets hang below the row so the dots never grow.

## Requirements

- macOS 14+
- Xcode 16+

## Run

Open `Dots.xcodeproj` in Xcode and run the **Dots** scheme.

There is no Dock icon. Look at the **top center** of the display.

## Use

- Click the first or second dot to open/close its widget
- Type a task and press Return or **+**
- Right-click a dot → **Quit Dots**, or Cmd+Q after the panel is key

## Tests

```sh
xcodebuild test -project Dots.xcodeproj -scheme Dots -destination 'platform=macOS'
```
