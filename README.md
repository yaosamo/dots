# Dots

A macOS menu-bar-style utility: dots float at the top of the screen, each one a tool.

**First launch:** clouds come down over the screen, then the dots appear one by one; click a dot to preview its tool and switch it on or off, and **Done** flies the chosen dots into the bar as the clouds lift. While some tools are off, the bar ends in a **+** dot that opens the same choice over the clouds (**Esc** cancels). **Choose Dots…** in the menu bar menu does too, and **Show Welcome** replays the intro. Every shader and welcome value lives in `ShaderTuning` and `WelcomeTuning`; the live-tuning labs (Shader Lab, Welcome Lab) are on the `dev` branch.

| Dot | Shortcut | Colour when on | What it does |
|-----|----------|----------------|--------------|
| 1 · Camera | ⌃⇧1 | green | Floating selfie camera. Circle by default. Hover it for controls: **size: small → medium → large**, **shape: circle → portrait rectangle → blob** (a drop that slowly wobbles), **effect** (the pen's electric, fire or rainbow around its edge, a cloud it sits in, or none; remembered), close. Drag it to move. |
| 2 · Tasks | ⌃⇧2 | orange | Full-screen dimmed overlay with a stack of tasks. The "Add a task…" field sits on top and new tasks go on top of the stack. Checked-off tasks stay where they are and shrink to a compact row. Drag a task to reorder the list. **Subtasks** (one level): drag a task a little to the right under another and a block appears beside its slot: it will land as a subtask. Drag a subtask left, from anywhere in its group, to make it a task; the subtasks below it become its own. A task you drag carries its subtasks, folded into a stack; dragged right under another task, it becomes a subtask and its subtasks come along. With a task selected, **Tab** makes it a subtask of the task above (its own subtasks join it) and **⇧Tab** makes a subtask a task where it is. **←** folds a task's subtasks into a stack under it, and **→** or a click on the stack unfolds them; hovering a task with subtasks also shows a button that folds or unfolds them. Checking a task checks its subtasks; unchecking a subtask unchecks its task; deleting a task deletes its subtasks. On opening, the background frosts over for 300 ms and then the tasks cascade in. The list runs to the bottom of the screen and fades out at both edges. Tasks are saved between launches. **Return** adds a task. **↑/↓** select a task, **Return** or a click edits it, **Return** saves the edit and opens an empty "Add a task…" row right after it, at the same level (after a task with its subtasks showing, as its first subtask); it goes away if you leave it empty, press Esc or click elsewhere. **Backspace** in an empty task deletes it and goes on editing the task above; a task with subtasks isn't deleted this way. The trash button shows while a task is being edited. **⌘Z** brings back deleted tasks, newest first, with their subtasks and in their places (while text is being typed, it undoes the typing instead). Deleted tasks can be restored until Dots quits. **Esc** cancels an edit. A card being edited can still be dragged by the card; a drag on its text selects text. **Esc** steps back one level at a time: it cancels an edit, then deselects the task, then closes the overlay; clicking outside the tasks does nothing. The overlay follows the system's light or dark appearance, or stays dark if **Always Dark Mode** is on in the menu bar menu (which also darkens the clipboard and the whiteboard). |
| 3 · Pen | ⌃⇧3 | red | The cursor becomes a pen for drawing on any screen. It opens with the **electric** brush, or with the whiteboard **marker** when the board is up. Click the active tool again to turn drawing off (**pointer mode**): the ink stays up, the cursor is normal and clicks reach the apps below; pick any tool to draw again. The toolbar on the right also has an **eraser** button that clears everything drawn on the screen in one click (the whiteboard is left alone; ⌘Z undoes it). Pick a brush from the toolbar on the right or with keys **1–5**: red pen, electric, fire, rainbow, spotlight. Electric, fire and rainbow are live Metal shaders (`Pen/PenShaders.metal`). **Spotlight** draws a dashed lasso; when you let go, everything outside it dims. Overlapping spotlights merge. **W** (or the button under the brushes) toggles the **whiteboard**, a white board with a dot grid filling the middle 80% of the screen under the pointer. What you draw on it is saved (`Application Support/Dots/Boards/current.json`) and comes back next time, even after quitting; notes drawn off the board still clear on exit. Shapes, text and moved objects snap to the grid; hold **⌘** to place freely. Its contents pan with a two-finger scroll, **Space**-drag or **H** hand, and stay inside the board; notes drawn off the board stay on the screen. On it, a tiny Excalidraw toolbar picks **V** select (click to select, drag to move, Delete removes), **H** hand, **P** marker, **R** rectangle, **O** ellipse, **A** arrow, **L** line (hold Shift for squares, circles and 15° angles), **T** text (Return or Esc finishes) and **E** eraser, plus five colors and a **Clear board** button that clears the whole board (screen notes stay; ⌘Z undoes it while the pen is open). Shapes are drawn clean and exact. Picking a brush goes back to drawing with it. **Esc** deselects or exits, **⌘Z** undoes anything, **C** clears, **Delete** removes the selection or clears. Screen ink stays until you undo, clear or exit; **C** also clears the board. |
| 4 · Timer | ⌃⇧4 | purple | A countdown on a 3D die that drops in, bounces off the screen's edges and rolls to a stop on the bottom edge. Drag and let go to toss it. Click it to start or pause; hover for −1 min, +1 min, reset and **✕** (put the die away), or click the time to type one: `10s`, `2m`, `1:30`, or a bare number of minutes. When time's up it chimes and hops once. The time you set is remembered. |
| 5 · Clipboard | ⌃⇧5 | blue | Your last ten copies (three without Dots Pro; text or images) as cards over a frosted screen, newest first, in rows of five; images show whole, however wide or tall. Click a card (hover shows **Copy**), or press **1–9** (**0** for the tenth), to copy it again; hover one for **✕** (or press **Delete**) to remove it; Esc or a click off the cards closes it. Tasks, pen and the clipboard cover the screen, so opening one closes the others. History is kept between launches (`Application Support/Dots/Clipboard`); copies marked concealed or transient, like passwords from a password manager, are never recorded. macOS asks before an app reads the clipboard, so history is recorded silently once Dots is set to **Always Allow** in System Settings › Privacy & Security › Paste from Other Apps; until then the card explains how. |

The shortcuts work from any app. The menu bar icon has **About**, the enabled tools with their shortcuts, **Choose Dots…**, **Hide Dots** (takes the bar off the screen; the shortcuts and the menu still open every enabled tool, and turning it off drops the dots back in), and **Quit**. Shortcuts stay fixed per tool whichever dots are on. You can also right-click the dot bar to quit.

## Dots Pro

Every dot is free to switch on. One non-consumable in-app purchase, **Dots Pro** (`app.dots.Dots.pro`), unlocks the parts inside them:

| Free | Dots Pro |
|------|----------|
| Camera: circle, portrait and blob, every size | Camera effects: electric, fire, rainbow, cloud |
| Pen: red pen, spotlight, eraser, undo | Pen: electric, fire and rainbow brushes |
| Tasks, timer | Whiteboard (**W**) |
| Clipboard: the newest three copies | Clipboard: the last ten |

A locked feature shows a lock and opens the Dots Pro card (`Pro/UnlockPanel.swift`); so does **Unlock Dots Pro…** in the menu bar menu. `Pro/ProStore.swift` checks StoreKit 2 entitlements at launch and on every transaction update (refunds turn Pro off live) and caches the result so Dots opens unlocked. Clipboard history always keeps ten; without Pro only three show. A chosen camera effect is kept without Pro and comes back with a restore.

To test purchases locally, pick `Dots.storekit` in the scheme's Run › Options › StoreKit Configuration, then use Xcode's Debug › StoreKit › Manage Transactions to refund or delete. Debug builds also have **Pretend Pro (Debug)** in the menu bar menu.

## Debug logs

In the Xcode console, filter by `app.dots.Dots` or by a category such as `camera` or `hotkeys`. The camera logs the click-to-handler latency, the morph start and finish, the camera configure time, the `startRunning`/`stopRunning` durations and how long each waited in the session queue.

## Build

Open `Dots.xcodeproj` in Xcode and run, or:

```sh
xcodebuild -project Dots.xcodeproj -target "Dots & Clouds" -configuration Debug build
```

Requires macOS 14+. The pen shaders need Xcode's Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`, or Xcode → Settings → Components). The app is sandboxed with the camera entitlement, and macOS asks for camera permission the first time you open dot 1.

## Structure

```
Dots/
  App/     DotsApp, DotsCoordinator (dot state + toggling), FloatingPanel (window levels, panel base), HotKeys, Log
  Bar/     Top dot bar, menu bar icon
  Camera/  AVCaptureSession wrapper, floating panel, Core Animation bubble + SwiftUI controls
  Tasks/   TaskStore (JSON persistence), full-screen overlay
  Onboarding/ Welcome and dot setup over the clouds (CloudsView), DotSettings (enabled dots), WelcomeTuning
  Timer/   Dice timer
  Clipboard/ Clipboard history
  Pen/     Per-screen drawing canvas, brushes, whiteboard tools (Board), pen cursors
```

The window stack, from top to bottom: dot bar → camera → pen canvas → task overlay → normal apps. The bar is always clickable, and the camera stays visible while you draw.
The project uses Xcode's synchronized folders, so any new file in `Dots/` joins the target automatically.

## Plans

- [Whiteboard storage, export and sharing](docs/whiteboard-storage-plan.md)
