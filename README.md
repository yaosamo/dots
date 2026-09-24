# Dots

A macOS menu-bar-style utility: dots float at the top of the screen, each one a tool.

**First launch:** the screen frosts over, the dots appear, and a card for each tool explains it; turn on the ones you want and they fly up into the bar. While some tools are off, the bar ends in a **+** dot that opens the same picker (**Esc** cancels). **Choose Dots…** in the menu bar menu does too, and **Show Welcome** replays the intro.

| Dot | Shortcut | Colour when on | What it does |
|-----|----------|----------------|--------------|
| 1 · Camera | ⌃⌥1 | green | Floating selfie camera. Circle by default. Hover it for controls: **size: small → medium → large**, **circle / portrait rectangle**, close. Drag it to move. |
| 2 · Tasks | ⌃⌥2 | orange | Full-screen dimmed overlay with a stack of tasks. The "Add a task…" field sits on top and new tasks go on top of the stack. Checked-off tasks stay where they are and shrink to a compact row. On opening, the background frosts over for 300 ms and then the tasks cascade in. The list runs to the bottom of the screen and fades out at both edges. Tasks are saved between launches. **Return** adds a task. **↑/↓** select a task, **Return** or a click edits it, **Return** saves the edit and **Esc** cancels it. **Esc** closes the overlay; clicking outside the tasks does nothing. The overlay follows the system's light or dark appearance, or stays dark if **Always Dark Tasks** is on in the menu bar menu. |
| 3 · Pen | ⌃⌥3 | red | The cursor becomes a pen for drawing on any screen. Pick a brush from the toolbar on the left or with keys **1–5**: red pen, electric, fire, rainbow, spotlight. Electric, fire and rainbow are live Metal shaders (`Pen/PenShaders.metal`). **Spotlight** draws a dashed lasso; when you let go, everything outside it dims. Overlapping spotlights merge. **W** (or the button under the brushes) toggles the **whiteboard**, a white board with a dot grid filling the middle 80% of the screen, remembered between uses. Shapes, text and moved objects snap to the grid; hold **⌘** to place freely. Its contents pan with a two-finger scroll, **Space**-drag or **H** hand, and stay inside the board; notes drawn off the board stay on the screen. On it, a tiny Excalidraw toolbar picks **V** select (click to select, drag to move, Delete removes), **H** hand, **P** marker, **R** rectangle, **O** ellipse, **A** arrow, **L** line (hold Shift for squares, circles and 15° angles), **T** text (Return or Esc finishes) and **E** eraser, plus five colors. Shapes are drawn clean and exact. Picking a brush goes back to drawing with it. **Esc** deselects or exits, **⌘Z** undoes anything, **C** clears, **Delete** removes the selection or clears. Ink stays until you undo, clear or exit; the brush you picked is remembered. |

The shortcuts work from any app. The menu bar icon has **About**, the enabled tools with their shortcuts, **Choose Dots…**, and **Quit**. Shortcuts stay fixed per tool whichever dots are on. You can also right-click the dot bar to quit.

## Debug logs

In the Xcode console, filter by `app.dots` or by a category such as `camera` or `hotkeys`. The camera logs the click-to-handler latency, the morph start and finish, the camera configure time, the `startRunning`/`stopRunning` durations and how long each waited in the session queue.

## Build

Open `Dots.xcodeproj` in Xcode and run, or:

```sh
xcodebuild -project Dots.xcodeproj -target Dots -configuration Debug build
```

Requires macOS 14+. The pen shaders need Xcode's Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`, or Xcode → Settings → Components). The app is sandboxed with the camera entitlement, and macOS asks for camera permission the first time you open dot 1.

## Structure

```
Dots/
  App/     DotsApp, DotsCoordinator (dot state + toggling), FloatingPanel (window levels, panel base), HotKeys, Log
  Bar/     Top dot bar, menu bar icon
  Camera/  AVCaptureSession wrapper, floating panel, Core Animation bubble + SwiftUI controls
  Tasks/   TaskStore (JSON persistence), full-screen overlay
  Onboarding/ Welcome and dot setup overlay, DotSettings (enabled dots)
  Pen/     Per-screen drawing canvas, brushes, whiteboard tools (Board), pen cursors
```

The window stack, from top to bottom: dot bar → camera → pen canvas → task overlay → normal apps. The bar is always clickable, and the camera stays visible while you draw.
The project uses Xcode's synchronized folders, so any new file in `Dots/` joins the target automatically.

## Plans

- [Whiteboard storage, export and sharing](docs/whiteboard-storage-plan.md)
