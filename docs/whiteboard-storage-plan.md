# Whiteboard storage, export and sharing — plan

Status: steps 1–2 built (one board on one screen, saved as JSON and restored). Export and sharing still planned.

## 1. Decide what belongs to the board

Right now each screen has its own drawing (`InkModel`), which holds everything drawn in pen mode, and it's thrown away when you leave pen mode. Before anything can be saved, the app needs to know which items are part of the whiteboard and which are quick notes on the screen:

- **Mark each item as board or screen when it's drawn.** Anything drawn while the whiteboard is up counts as board. Spotlights never do.
- **Only board items are saved.** Screen notes keep behaving as they do today.
- **One board, on one screen.** The whiteboard appears only on the screen under the pointer when pen mode opens, and that screen's board is the one saved. Other screens keep plain screen notes.

## 2. Store positions relative to the board

Positions are currently screen points. Saved positions should be measured from the board's top-left corner in grid units, or in points plus the board's size. Then a board made on a 5K display opens correctly on a MacBook. It can be scaled to fit, or centred, with the grid kept.

## 3. File format: versioned JSON

```jsonc
{
  "version": 1,
  "id": "B2F1…",
  "createdAt": "2026-09-24T10:12:00Z",
  "updatedAt": "…",
  "board": { "width": 1210, "height": 786, "grid": 20 },
  "items": [
    { "id": "…", "type": "rectangle", "from": [40, 60], "to": [240, 160], "color": "blue" },
    { "id": "…", "type": "arrow",     "from": [240, 110], "to": [400, 110], "color": "black" },
    { "id": "…", "type": "text",      "at": [60, 200], "text": "Ship it", "color": "red" },
    { "id": "…", "type": "stroke",    "brush": "ink", "color": "#1e1e1e",
      "points": "base64(Float16 x,y pairs)" }
  ]
}
```

- **Items in one ordered list,** so their stacking order is kept.
- **Colours saved by name** (`"blue"`, a `BoardColor`) for the five board colours, and as hex for brush ink. This is needed because SwiftUI's `Color` type can't be saved to a file directly.
- **Freehand lines are compacted before saving:** extra points are dropped (Ramer–Douglas–Peucker), positions are rounded to 0.5pt, and the numbers are stored as packed binary. A scribble goes from about 10 KB to about 1 KB.
- **Undo history isn't saved.**

## 4. Where boards live and how they save

- **Location:** `Application Support/Dots/Boards/<id>.json`, inside the app's sandbox, so no extra permissions are needed.
- **Autosave:** about 1 s after the last change, written safely so a crash can't leave a half-written file.
- **Reopening:** the whiteboard keeps its content between pen sessions (decided) and comes back as you left it, instead of being cleared when you leave pen mode. **C** would start a new board, and the old one stays in history.
- **Later:** a simple list of recent boards in the menu bar menu (open, duplicate, delete).
- **Code:** a new `BoardStore`, next to the task list's existing `TaskStore`, which saves the same way.

## 5. Export (all local, no server)

| Format | How | Notes |
|---|---|---|
| **PNG** (and copy to clipboard) | Render the board with SwiftUI's `ImageRenderer` at 2× | Simplest; good for Slack. Animated brushes appear frozen at one frame. |
| **PDF** | `ImageRenderer` drawing into a PDF | Stays sharp at any size. |
| **SVG** | Write it by hand from the items | Shapes and text convert directly, and lines become paths. Electric, fire and rainbow become plain colour. |
| **.excalidraw** | Convert each item to the matching Excalidraw element | Opens in Excalidraw to keep editing. Also a route to sharing, below. |

This means the shape-drawing code (`ShapeGeometry`, `ShapeLayer`, `StrokeLayer`) has to work without the live canvas, so the same code draws the screen and the export.

## 6. Shareable links: three options

**A. Board inside the link, read by a static viewer page.**
The board is compressed and put after the `#` in a link to a small web page that draws it as SVG.

- Pros: no server storage, private (the part after `#` never reaches the server), free.
- Cons: links get long, so it only works for boards with few freehand lines, and the board can't be edited after sharing.

**B. Upload to our own storage, with a viewer page.**
A small web function saves the JSON to cloud storage and returns a link such as `dots.link/b/abc123`. The viewer page is the same as in A.

- Pros: short links, boards of any size, links can be removed or expire, view counts, and possibly live updates later.
- Cons: needs hosting, some basic identity or rate limiting to stop abuse, and a privacy policy.

**C. Share through Excalidraw.**
Upload the `.excalidraw` file to Excalidraw's share service and get their encrypted link.

- Pros: nothing to host, and the person receiving it can edit.
- Cons: relies on an API Excalidraw doesn't officially offer to others, and the board leaves our control.

**Recommendation:** do A first, and fall back to B once boards get too big for a link. Both share one viewer, and A needs no server. Offer C as an "Open in Excalidraw" export rather than as the sharing path.

## 7. Build order

1. Mark items as board or screen, and make every item type saveable.
2. `BoardStore`: autosave and reopen.
3. PNG export and copy to clipboard, with an export button on the board toolbar.
4. SVG, PDF and `.excalidraw` export.
5. The viewer page, then links (A, then B).

## Decisions

- **The whiteboard keeps its content between pen sessions.** Screen notes still clear on exit.
- **One board, on one screen for now:** the screen under the pointer when pen mode opens.

## Open decisions

- **Shared links: view-only, or editable by others?** Editable pushes toward option B, or toward C through Excalidraw.
