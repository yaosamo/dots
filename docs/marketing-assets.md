# Marketing assets: store screenshots, site clips and icons

How to make the Mac App Store screenshots, the website's clips and the dots' glyphs so every new one
matches the ones already out. The tools live in `marketing/`; the site's files in `site/`.

## Before capturing anything

- **Build the version you're showing** (⌘R in Xcode) and quit any other copy of Dots, including the
  App Store one. They share permissions (see the README), so the wrong one may be what's on screen.
- **A clean screen:** close or hide other apps' windows, hide desktop icons
  (`defaults write com.apple.finder CreateDesktop false; killall Finder`, and `true` to undo), and turn
  on Do Not Disturb so no notification lands in a shot.
- **A wallpaper like the others':** a bright macOS gradient wallpaper (the live shots use Sequoia's
  and Sonoma's). Keep the same one across a release's shots. 1.1's screenshot shot and clip use
  Sonoma (`/System/Library/Desktop Pictures/Sonoma.heic`), with the framed page a render of
  dots.yaosamo.com.
- **Light appearance**, unless the shot is the dark one (`10-dark`).
- **Content that reads as real use:** the demo tasks (Launch Dots 1.1, Book flights to Lisbon, Buy oat
  milk), the clipboard set in the 09 shot, and dots.yaosamo.com as the page in screenshot shots.
  Never a real person's data, passwords or private messages.

## Mac App Store screenshots

**Spec:** 2880×1800 PNG (the store also takes 1440×900), RGB, no alpha. Upload in order; the first
three show in search, so lead with the hooks.

**The look,** shared by every shot (all set by `marketing/store/template.html`; never restyle one):
the light sky with the site's clouds behind the card's top edge; a tint dot and the dot's name; a
headline (Figtree 600, a short sentence with a full stop); one line under it; the capture in a card
with 22 px corners and a soft shadow, its top 260 px down; two or three white pills with the tint dot,
each half on the card and half off it.

**Current set** (`shots.js` holds the ones made with the template):

| # | File | Dot | Headline |
|---|------|-----|----------|
| 01 | `01-blob` | Camera | Blob camera |
| 02 | `02-cloud` | Camera | (camera in a cloud) |
| 03 | `03-dots` | Dots | Five tiny tools. One dot each. (live; redo as "Six" with every dot in its color: words are in `shots.js`, the capture is still to take) |
| 04 | `04-tasks` | Tasks | |
| 05 | `05-pen` | Pen | |
| 06 | `06-screenshot` | Screenshot | Screenshots, framed. |
| 07 | `07-board` | Pen | (whiteboard) |
| 08 | `08-timer` | Timer | |
| 09 | `09-clipboard` | Clipboard | Your last five copies. (says five: redo it for ten) |
| 10 | `10-dark` | | (dark mode) |

**Make one:**

1. **Capture** the screen with the feature showing: `screencapture -x capture.png` (whole display, at
   Retina resolution), or ⌘⇧5. A window alone: `screencapture -o -l <window id> capture.png` (no shadow).
2. **Crop** it to what the card shows: a 16:10 or 16:9 area of the screen around the feature, at full
   resolution: `ffmpeg -i capture.png -vf crop=W:H:X:Y marketing/store/captures/<name>.png`.
3. **Add it to `marketing/store/shots.js`:** label, tint (`camera`, `tasks`, `pen`, `timer`,
   `clipboard`, `screenshot`), title, sub, the card's size in CSS px (1074×605 for a 16:9 screen,
   1120 wide for a wide strip) and the pills' positions.
4. **Render:** `marketing/store/render.sh <name>` writes `marketing/store/out/<name>.png` at 2880×1800.
   Look at it next to a live one; `calibrate-clipboard` rebuilds the live 09 shot from its own card,
   so the template can be checked against the store any time.
5. **Upload** in App Store Connect › the version › Mac screenshots, in the order above.

Words: plain and short, like the app (see the README and site). Pills name what you can do, three to
five words each, no full stop.

## Site clips (the "See them in action" cards and the changelog)

**Spec** (what `marketing/clips/make-clip.sh` makes): `<name>.mp4`, 16:10 at 1680×1050, H.264 High,
30 fps, yuv420p, no audio, faststart, CRF 20 (`-tune animation`), 5–13 s, about 0.5–1.5 MB; and
`<name>.jpg`, its poster, 1600×1000, taken from the recording itself. The cards show clips about
700 px wide, so 1680 keeps them sharp on Retina. The clip loops, so end where it starts (or on a
calm frame). Clips before 1.1 are 800×500 or 1120×700 at CRF 28 and look soft; remake them this way
when they're next touched.

**Crop to the feature, not the whole screen:** a 5K screen scaled into 1680 px turns UI text to mush.
Keep the downscale at 1.5× or less (on a 5K display that's a crop about 2400–2500 px wide around the
window), and record with `screencapture -v`, whose files keep full detail.

**Make one:**

1. **Record** the screen while you show the feature once, slowly, with the pointer visible:
   ⌘⇧5 › Record Entire Screen (or `screencapture -v -C -V 15 recording.mov` for 15 s). Do it on the
   clean screen above.
2. **Cut and encode:** `marketing/clips/make-clip.sh recording.mov <name> <start> <duration> [crop] [poster]`.
   The crop defaults to the biggest centered 16:10 area; pass `w:h:x:y` (in the recording's pixels)
   to frame the feature, and pick a poster time that shows it at its best.
3. **Add the card** to `site/index.html` in `.features`, copying an existing `<article>`: set
   `--tint: var(--<dot>)`, the `src`/`poster`, the `aria-label`s, an `<h3>` with the feature's name and
   one line (`<p>`) in the voice of the others. A new dot also needs its hero `<li>` (tint, `--i` its
   index, icon, tooltip with its shortcut) and a `--<dot>` color in `site/styles.css`.
4. **Changelog:** each release in `site/changelog.html` leads with one headline and one clip (the same
   files work), then its improvements as bullets.

## Dot glyphs (site/icons)

Each dot's glyph is the app's own SF Symbol (`Dot.symbol` in `Dots/App/DotsCoordinator.swift`) in its
tint (`Dot.tint`), 144×144, its longer side 110 px:

```sh
swift marketing/icons/render-icon.swift camera.viewfinder FF2D55 site/icons/screenshot.png
```

Tints: camera `34C759`, tasks `FF9500`, pen `FF3B30`, timer `AF52DE`, clipboard `007AFF`,
screenshot `FF2D55` (the system colors, as `--<dot>` in `site/styles.css`).

## App Store text

Kept with the release, not here: What's New, promotional text (170 characters at most; it can change
without a review) and the reviewer notes. The description lists every dot with its shortcut, so a new
dot means a new paragraph there too.
