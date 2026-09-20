# Dots

A native macOS accessory overlay: a registry-backed row of 16pt Dots hangs from the top of the screen, with compact feature UI below it.

- **Mirror** — draggable circular live selfie camera
- **Tasks** — task list (add, complete, delete; persists locally)
- **Red Pen** — draw over the screen; Escape exits, ⌘Z undoes
- **Screen to Text** — drag a rectangle, OCR, copy
- **Clipboard** — last few copied snippets; click to copy again

Only implemented Dots are shown; there are no decorative placeholders. Feature surfaces hang below the 16pt orbs instead of growing them.

The panel is borderless, always on top, and click-through around visible controls. On macOS 26 and newer, feature surfaces use SwiftUI's native Liquid Glass. macOS 14 and 15 use a material-backed fallback.

## Requirements

- macOS 14+
- Xcode 26+

## Run

Open `Dots.xcodeproj` in Xcode and run the **Dots** scheme.

There is no Dock icon. Look at the **top center** of the display for the orbs, and **Dots** in the menu bar (top-right) for About and Quit.

## Use

- Click a Dot to open it; click again or press Escape to close
- Drag the Mirror camera to place it
- Red Pen: draw, ⌘Z undo, Escape to exit
- Screen to Text: drag a region to copy recognized text
- Clipboard: click a snippet to copy it again
- Menu bar **Dots** (top-right) → About Dots or Quit Dots

## Tests

```sh
xcodebuild test -project Dots.xcodeproj -scheme Dots -destination 'platform=macOS'
```
