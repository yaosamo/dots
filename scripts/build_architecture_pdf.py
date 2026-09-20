#!/usr/bin/env python3
"""Generate The Dots macOS architecture brief."""

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (
    Paragraph,
    Preformatted,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

INK = colors.HexColor("#111111")
MUTED = colors.HexColor("#5c5c5c")
RULE = colors.HexColor("#d8d8d8")
HEAD_BG = colors.HexColor("#f3f3f3")
CODE_BG = colors.HexColor("#f6f6f6")
DONE = colors.HexColor("#1a7f37")
WIP = colors.HexColor("#9a6700")
TODO = colors.HexColor("#888888")

PAGE_W, PAGE_H = letter
LEFT = 0.7 * inch
RIGHT = 0.7 * inch
TOP = 0.85 * inch
BOTTOM = 0.7 * inch
CONTENT_W = PAGE_W - LEFT - RIGHT


def styles():
    base = getSampleStyleSheet()
    s = {
        "kicker": ParagraphStyle(
            "kicker",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=8,
            leading=11,
            textColor=MUTED,
            alignment=TA_CENTER,
            tracking=1,
        ),
        "title": ParagraphStyle(
            "title",
            parent=base["Title"],
            fontName="Helvetica-Bold",
            fontSize=28,
            leading=32,
            textColor=INK,
            alignment=TA_CENTER,
            spaceAfter=4,
        ),
        "subtitle": ParagraphStyle(
            "subtitle",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=13,
            leading=18,
            textColor=INK,
            alignment=TA_CENTER,
            spaceAfter=2,
        ),
        "meta": ParagraphStyle(
            "meta",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=9,
            leading=12,
            textColor=MUTED,
            alignment=TA_CENTER,
            spaceAfter=16,
        ),
        "h1": ParagraphStyle(
            "h1",
            parent=base["Heading1"],
            fontName="Helvetica-Bold",
            fontSize=14,
            leading=18,
            textColor=INK,
            spaceBefore=14,
            spaceAfter=8,
        ),
        "h2": ParagraphStyle(
            "h2",
            parent=base["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=11,
            leading=14,
            textColor=INK,
            spaceBefore=10,
            spaceAfter=6,
        ),
        "body": ParagraphStyle(
            "body",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=9,
            leading=12.5,
            textColor=INK,
            spaceAfter=7,
        ),
        "th": ParagraphStyle(
            "th",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=8,
            leading=11,
            textColor=INK,
        ),
        "td": ParagraphStyle(
            "td",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=8,
            leading=11,
            textColor=INK,
        ),
        "code": ParagraphStyle(
            "code",
            parent=base["Code"],
            fontName="Courier",
            fontSize=7.5,
            leading=10,
            textColor=INK,
            leftIndent=0,
        ),
        "status": ParagraphStyle(
            "status",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=8.5,
            leading=12,
            textColor=INK,
        ),
        "footer": ParagraphStyle(
            "footer",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=7.5,
            textColor=MUTED,
        ),
        "dots": ParagraphStyle(
            "dots",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=16,
            leading=22,
            alignment=TA_CENTER,
            textColor=INK,
            spaceBefore=10,
            spaceAfter=16,
        ),
    }
    return s


S = styles()


def P(text, style="body"):
    return Paragraph(text, S[style])


def bullets(items):
    style = ParagraphStyle(
        "bulletItem",
        parent=S["body"],
        leftIndent=14,
        firstLineIndent=-10,
        spaceAfter=3.5,
        leading=12.5,
    )
    last = ParagraphStyle(
        "bulletItemLast",
        parent=style,
        spaceAfter=8,
    )
    flows = []
    for i, item in enumerate(items):
        flows.append(Paragraph(f"•  {item}", last if i == len(items) - 1 else style))
    return flows


def table(headers, rows, col_widths):
    def cell(text, header=False):
        return Paragraph(text, S["th"] if header else S["td"])

    data = [[cell(h, True) for h in headers]]
    for row in rows:
        data.append([cell(c) for c in row])
    t = Table(data, colWidths=col_widths, repeatRows=1)
    t.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), HEAD_BG),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ("GRID", (0, 0), (-1, -1), 0.4, RULE),
                ("ALIGN", (0, 0), (-1, 0), "LEFT"),
            ]
        )
    )
    t.spaceAfter = 10
    return t


def code_block(text):
    pre = Preformatted(text.rstrip() + "\n", S["code"])
    box = Table([[pre]], colWidths=[CONTENT_W])
    box.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), CODE_BG),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
                ("BOX", (0, 0), (-1, -1), 0.3, RULE),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ]
        )
    )
    box.spaceAfter = 10
    return box


def header_footer(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 7.5)
    canvas.drawString(LEFT, PAGE_H - 0.48 * inch, "THE DOTS  |  macOS product + technical architecture")
    canvas.drawRightString(PAGE_W - RIGHT, PAGE_H - 0.48 * inch, "Updated September 2026")
    canvas.setStrokeColor(RULE)
    canvas.setLineWidth(0.4)
    canvas.line(LEFT, PAGE_H - 0.58 * inch, PAGE_W - RIGHT, PAGE_H - 0.58 * inch)
    canvas.line(LEFT, 0.48 * inch, PAGE_W - RIGHT, 0.48 * inch)
    canvas.drawString(LEFT, 0.32 * inch, "Implementation brief for Codex / Grok")
    canvas.drawRightString(PAGE_W - RIGHT, 0.32 * inch, str(doc.page))
    canvas.restoreState()


def story():
    w = CONTENT_W
    out = []

    out += [
        Spacer(1, 36),
        P("THE DOTS", "title"),
        P("macOS Product + Technical Architecture", "subtitle"),
        P("MVP implementation brief for Codex and Grok  ·  revised after the first shell prototype", "meta"),
        P("●&nbsp;&nbsp;&nbsp;●&nbsp;&nbsp;&nbsp;●&nbsp;&nbsp;&nbsp;●&nbsp;&nbsp;&nbsp;●", "dots"),
        P("<b>Purpose.</b> This document is the source of truth for The Dots. Coding agents should implement the smallest native macOS system that satisfies the behavior below. Do not expand the product into a general launcher, note app, calendar, full clipboard manager, or automation platform unless explicitly requested."),
        table(
            ["Product principle", "Meaning"],
            [
                ["One click away", "A Dot is always accessible at the top edge of the screen."],
                ["Do the thing", "Each feature performs one small job with minimal UI."],
                ["Disappear", "Panels and overlays dismiss immediately when the job is done."],
                ["User chooses the set", "The app may offer many features, but only 1–5 active Dots are visible."],
                ["Native first", "Prefer Apple frameworks, local processing, and no backend for MVP."],
                ["Orbs never grow", "The 16 pt Dots stay 16 pt. Feature UI hangs below or detaches; it does not morph the orb."],
            ],
            [1.7 * inch, w - 1.7 * inch],
        ),
        P("<b>Prototype status (September 2026).</b> The tree at <font face='Courier'>yaosamo/dots</font> is a working top-edge shell: registry-backed Mirror + text Tasks, stable-anchor nearest-Dot magnetism, nonactivating panel, click-through around orbs, and a draggable 120 pt Mirror preview. It is <b>not</b> the full MVP. Escape/presenter completion, multi-display behavior, Pomodoro, Red Pen, Screen → Text, Clipboard, voice tasks, and onboarding are still required. Unimplemented catalog Dots are not shown as decoration."),
        P("Target platform: macOS. Minimum: macOS 14. Enhanced local AI (Foundation Models, modern Speech APIs) is availability-gated on newer systems."),
    ]

    out += [
        P("1. Product model", "h1"),
        P("The Dots is a compact top-edge utility layer. The visible objects are black circular endpoints attached to short sprouts hanging from the top edge of the current display. The user configures which utilities are present. The shell is persistent; each utility is deliberately tiny."),
        P("1.1 Launcher behavior", "h2"),
        bullets(
            [
                "Show 1–5 active Dots. Five is the MVP maximum; keep the limit a named constant in code.",
                "Default visual orb diameter: 16 × 16 pt. The interactive hit area must be larger than the visible orb (stem hit slop plus a padded circle), not equal to the 16 pt fill.",
                "On pointer movement near the launcher, calculate distance from the pointer to each <b>stable logical orb center</b>. Only the nearest eligible orb reacts.",
                "The nearest sprout/orb stretches toward the pointer with a short ease-out (start ~60–100 ms). Selection uses the unstretched anchor so the animation cannot jitter hit-testing.",
                "Clicking an orb opens that feature. Clicking it again or pressing Escape dismisses it and returns control to the prior app.",
                "Feature UI appears adjacent to its Dot. It is not a traditional app window. Become key only when keyboard input is required (Tasks composer).",
                "One transient feature at a time. Opening Tasks closes Mirror, and the other way around.",
                "Anchor to the active display under the pointer. Place the cluster flush with <font face='Courier'>visibleFrame.maxY</font> (just below the menu bar / notch) and horizontally centered. Keep per-display geometry isolated; do not assume one global coordinate space.",
                "The cluster itself is not user-draggable in MVP. The Mirror <b>preview</b> is independently draggable (see 5.1).",
            ]
        ),
        P("1.2 Onboarding", "h2"),
        P("The first launch should double as configuration. Present the Dots themselves as an interactive selector: hovering or focusing a Dot reveals a compact preview/name, and selecting it adds the utility to the user's top-edge set. Avoid a long settings wizard."),
        P("<b>Recommended first-run defaults:</b> Mirror, Tasks, Pomodoro."),
        P("After onboarding, configuration remains available through a small settings view: add/remove/reorder Dots, timer defaults, clipboard history length, and permissions status."),
        P("The current prototype launches with the implemented Mirror and Tasks descriptors. Add catalog Dots to the visible set only when their behavior is implemented; do not ship unused decorative Dots."),
        P("1.3 UX invariants", "h2"),
        table(
            ["Invariant", "Acceptance rule"],
            [
                ["No app chrome", "No title bar, sidebar, document navigation, or persistent large window in normal use. No Dock icon (<font face='Courier'>LSUIElement</font>)."],
                ["Fast open", "A click should produce visible response immediately; expensive work starts after the panel/overlay is visible."],
                ["Keyboard-safe", "Non-text features must not steal focus from the currently active app. Use a borderless nonactivating <font face='Courier'>NSPanel</font>. <font face='Courier'>canBecomeMain</font> is false. Become key only for the Tasks composer."],
                ["Escape means exit", "Escape closes any Dot panel or transient overlay and returns control to the prior app."],
                ["Orbs stay 16 pt", "Camera, lists, and other widgets hang below the row or float free. They never enlarge the orb."],
                ["State survives appropriately", "Tasks and configuration persist. Timer survives app UI dismissal. Mirror frames, Red Pen drawings, OCR selections, and clipboard history do not require durable storage in MVP."],
            ],
            [1.55 * inch, w - 1.55 * inch],
        ),
    ]

    out += [
        P("2. MVP feature set", "h1"),
        table(
            ["Dot", "Job", "MVP behavior", "Now"],
            [
                ["Mirror", "Quickly check camera view", "Open a mirrored live camera preview in a 120 pt circle hanging from the orb. Drag it anywhere on the display. When it leaves the docked hang point, that orb's sprout disappears. Close re-docks. No recording or photo capture.", "Built"],
                ["Tasks", "Capture things to do", "Small checklist. Add text with one field + Return or +. Persist locally. Voice: dictate one utterance that can become multiple tasks (not in the tree yet).", "Text only"],
                ["Pomodoro", "Start a focus timer", "Quick presets (5 / 15 / 25) plus start/pause/cancel. Persist deadline rather than ticking state.", "Not built"],
                ["Red Pen", "Point/draw over the screen", "Temporary transparent overlay for pen / highlighter / arrow. Escape clears and exits.", "Not built"],
                ["Screen → Text", "Copy visible text from anywhere", "Select a rectangle, OCR the captured pixels, copy recognized text, show a brief confirmation.", "Not built"],
                ["Clipboard", "Recover recent copied text", "Keep the most recent 5–10 text/URL clipboard entries. Click an item to copy it again.", "Not built"],
            ],
            [1.15 * inch, 1.35 * inch, w - 3.15 * inch, 0.65 * inch],
        ),
        P("<b>Not in MVP.</b> Calendar integration, recent-files browser, password vault, full note system, cloud sync, accounts, team features, plugin marketplace, cross-device sync, clipboard search, annotation saving, screen recording, or analytics-heavy dashboards. No feature should create its own Dock-level application experience. Everything is subordinate to the top-edge shell."),
    ]

    out += [
        P("3. System architecture", "h1"),
        P("Use a SwiftUI + AppKit hybrid. SwiftUI owns feature views and lightweight state. AppKit owns window/panel behavior, top-edge positioning, nonactivating interaction, transparent overlays, and screen geometry. Keep feature implementations isolated behind a common registry so additional Dots can be added without modifying the launcher core."),
        P("The current tree is a flat prototype (<font face='Courier'>AppDelegate</font>, <font face='Courier'>DotsView</font>, <font face='Courier'>CameraSession</font>, <font face='Courier'>TaskStore</font>). That is acceptable through checkpoint 3. Starting at checkpoint 2 (launcher system), introduce the registry and presenter so Pomodoro and later Dots do not keep growing <font face='Courier'>DotsView</font>."),
        code_block(
            """TheDotsApp
  AppCoordinator
  |-- DotRegistry ------------ metadata + factories
  |-- LauncherController ----- top-edge NSPanel / geometry / hover
  |-- FeaturePresenter ------- opens transient feature panels
  |-- PermissionCenter ------- camera / mic / speech / screen capture
  |
  +-- Features
      |-- Mirror
      |-- Tasks
      |-- Pomodoro
      |-- RedPen
      |-- ScreenToText
      +-- Clipboard

Shared services
  CameraService | SpeechService | TaskExtractionService
  ScreenCaptureService | OCRService | ClipboardService
  TimerService | SettingsStore | TaskStore"""
        ),
        P("3.1 Core boundaries", "h2"),
        table(
            ["Component", "Responsibility"],
            [
                ["AppCoordinator", "Bootstraps services, restores configuration, owns lifecycle, routes Dot actions."],
                ["DotRegistry", "Static catalog of available Dots: id, display name, permissions, preferred presentation mode, factory/action."],
                ["LauncherController", "Owns the always-on-top top-edge NSPanel, pointer-distance logic, animations, ordering, display changes."],
                ["FeaturePresenter", "Creates/dismisses transient NSPanel windows and full-screen transparent overlays. Enforces one active transient feature at a time."],
                ["PermissionCenter", "Single place to query/request permissions and expose permission state to onboarding/settings."],
                ["Feature modules", "Contain feature-specific view/state and use shared services through protocols."],
            ],
            [1.6 * inch, w - 1.6 * inch],
        ),
        P("3.2 Suggested feature abstraction", "h2"),
        code_block(
            """enum DotPresentation { case popover, overlay, directAction }

struct DotDescriptor: Identifiable {
    let id: DotID
    let title: String
    let presentation: DotPresentation
    let requiredPermissions: Set<AppPermission>
}

protocol DotFeature {
    var descriptor: DotDescriptor { get }
    @MainActor func activate(context: DotContext) async
    @MainActor func deactivate()
}

struct DotContext {
    let anchorRect: CGRect
    let screen: NSScreen
    let services: AppServices
}"""
        ),
        P("Do not force every feature into the same UI container. Mirror, Tasks, Pomodoro, and Clipboard are panel-like. Red Pen is an overlay. Screen → Text is a direct action that temporarily creates a selection overlay and then exits."),
    ]

    out += [
        P("4. Windowing and interaction architecture", "h1"),
        P("The launcher is an AppKit NSPanel at the top of the active screen. Style mask: borderless + <font face='Courier'>nonactivatingPanel</font>. Hovering and clicking Dots must not pull the user out of the current app. A feature panel may become key only when it actually needs keyboard entry."),
        P("4.1 Launcher panel", "h2"),
        bullets(
            [
                "Clear background, no shadow unless the final design needs one.",
                "Window level high enough to remain visible over normal windows; test around full-screen apps, Mission Control, menu bar, and system alerts. Current prototype uses <font face='Courier'>.statusBar</font> with <font face='Courier'>.canJoinAllSpaces</font>, <font face='Courier'>.fullScreenAuxiliary</font>, <font face='Courier'>.stationary</font>, <font face='Courier'>.ignoresCycle</font>.",
                "<font face='Courier'>becomesKeyOnlyIfNeeded = true</font>. <font face='Courier'>canBecomeKey = true</font>. <font face='Courier'>canBecomeMain = false</font>.",
                "Hit-test must return nil for transparent padding so clicks pass through to apps underneath. Resize the panel to the union of the orb row and any hanging/detached widget; do not cover the whole screen.",
                "SwiftUI launcher content is embedded with NSHostingView.",
                "Right-click a Dot for Quit Dots. Cmd+Q works after the panel is key.",
            ]
        ),
        P("4.2 Magnetic sprout interaction", "h2"),
        P("Required. The prototype only scales the hovered orb by 4%; that is not magnetism."),
        code_block(
            """onPointerMove(point):
    candidates = visibleDots.map { (dot, distance(point, dot.orbCenter)) }
    nearest = candidates.min(by: distance)

    for dot in visibleDots:
        if dot == nearest && distance < activationRadius:
            dot.targetOffset = clampedVectorTowardPointer(point)
        else:
            dot.targetOffset = .zero

    animate(targetOffset, duration: 0.06...0.10, easing: easeOut)"""
        ),
        P("The orb may visually stretch toward the pointer, but selection remains based on stable logical anchor centers."),
        P("4.3 Presentation rules", "h2"),
        table(
            ["Feature type", "Window behavior"],
            [
                ["Panel", "Anchor below the selected Dot. Dismiss on outside click where practical, Escape, or second click. Mirror's preview may then be dragged off the hang point."],
                ["Overlay", "Transparent borderless window spanning the relevant display(s). Escape always exits. Keep an explicit event mode so the overlay only intercepts input while active."],
                ["Direct action", "Show selection/capture UI only for the duration of the action, then a short toast and disappear."],
            ],
            [1.4 * inch, w - 1.4 * inch],
        ),
    ]

    out += [
        P("5. Feature technical specifications", "h1"),
        P("5.1 Mirror", "h2"),
        P("Goal: one-click live mirror, not a camera app."),
        bullets(
            [
                "AVFoundation capture session with a preferred built-in front camera, then Continuity Camera, then external. Mirrored preview via <font face='Courier'>AVCaptureVideoPreviewLayer</font>.",
                "Render in a 120 pt circle that hangs below the Mirror orb with an 8 pt gap. Orbs stay 16 pt.",
                "The preview is draggable. The user may place it anywhere on the current display. Store the offset from the docked hang point; the launcher panel grows to the union of the row and the preview and stays click-through around both.",
                "When the preview moves farther than 8 pt from the docked hang point, the Mirror orb's sprout disappears. The 16 pt orb remains so the user can close Mirror. Closing re-docks the preview (offset resets to zero) and restores the sprout.",
                "Start the session after the panel opens; stop immediately on dismiss. Serialize start/stop with a generation token so a queued idle cannot overwrite a newer open. Recheck the token after <font face='Courier'>startRunning()</font>.",
                "Prefer a 640×480 session preset (then medium / low). Do not use <font face='Courier'>.high</font> for a 120 pt circle.",
                "On media-services reset while the preview is open, retry once. Other runtime errors fail until the user toggles the orb. Connecting a camera later is click-to-retry, not hot-plug auto-start.",
                "No photo/video saving. No microphone. Request camera permission only when the user first activates Mirror or enables it in onboarding.",
            ]
        ),
        P("5.2 Tasks", "h2"),
        P("Goal: a tiny checklist with fast text and voice capture. A task is an action item, not a general note."),
        bullets(
            [
                "MVP persistence: local <font face='Courier'>UserDefaults</font> JSON is acceptable. Model: id, title, isDone. Add <font face='Courier'>createdAt</font> / <font face='Courier'>completedAt</font> / <font face='Courier'>sortOrder</font> when the UI needs them. SwiftData is optional later if the model grows.",
                "No due dates, projects, tags, reminders, collaboration, or recurring tasks.",
                "Text entry: one AppKit text field (the panel is a nonactivating overlay; SwiftUI <font face='Courier'>TextField</font> does not reliably take keys) + Return or + to create. Opening Tasks makes the panel key and focuses the composer. After insert, clear the field even if it is still editing.",
                "Completed items can collapse into a small completed section (not in the prototype yet).",
                "Voice entry (required for MVP, not built): press/hold or tap a mic affordance, dictate naturally, transcribe, convert the transcript into one or more tasks.",
            ]
        ),
        code_block(
            """struct DotTask: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var isDone: Bool
}

struct TaskDraft: Codable, Sendable {
    let text: String
}"""
        ),
        P("<b>Voice pipeline</b> (still to build)"),
        bullets(
            [
                "Capture microphone audio.",
                "Transcribe with Apple Speech APIs. On newer systems prefer SpeechAnalyzer / SpeechTranscriber; keep a compatibility adapter for older supported macOS if needed.",
                "Send the transcript to TaskExtractionService.",
                "If Apple Foundation Models is available, use structured/guided generation to return [TaskDraft].",
                "If the local model is unavailable or unsupported for the current language, use a deterministic fallback splitter. A cloud model adapter can be added later, but must not be required for MVP.",
                "Show the parsed tasks for immediate confirmation/editing, then persist.",
            ]
        ),
        P("<b>Task extraction contract</b>"),
        code_block(
            """Input:  "Finish the website, send the mockups to Alex, and buy cat food."
Output: [
  { "text": "Finish the website" },
  { "text": "Send the mockups to Alex" },
  { "text": "Buy cat food" }
]

Rules:
- extract actions only; do not invent tasks
- preserve names and concrete details
- split clearly separate actions
- do not add dates or priorities unless explicitly spoken"""
        ),
        P("5.3 Pomodoro / Timer", "h2"),
        bullets(
            [
                "Preset buttons: 5, 15, and 25 minutes; make presets user-configurable later.",
                "Store startedAt and targetEndDate. UI derives remaining time from wall clock instead of decrementing a counter every second.",
                "Closing the panel must not stop the timer.",
                "When targetEndDate is reached, send a local notification if permission is granted and show the Dot in a completed/attention state.",
                "MVP does not need productivity statistics, sessions history, projects, or cloud sync.",
            ]
        ),
        P("5.4 Red Pen", "h2"),
        P("Goal: temporary visual annotation over whatever is already on screen."),
        bullets(
            [
                "Activate a transparent overlay window over the current display; optionally support all displays after single-display behavior is solid.",
                "MVP tools: red pen, translucent highlighter, arrow. Keep the tool strip minimal or reveal it near the active Dot.",
                "Pointer events are intercepted only while Red Pen is active. Underlying apps must receive input again immediately after exit.",
                "Escape clears all strokes and closes the overlay. Cmd+Z may undo the last stroke.",
                "Do not save annotations. Do not require Screen Recording permission merely to draw an overlay.",
                "Represent strokes as lightweight vector paths in memory, not screenshots.",
            ]
        ),
        P("5.5 Screen → Text", "h2"),
        P("Goal: two interactions — click the Dot, drag a rectangle, then the recognized text is already in the clipboard."),
        bullets(
            [
                "Activate a selection overlay and let the user drag a rectangle.",
                "Translate selection coordinates into the correct display coordinate space.",
                "Capture only the selected region with ScreenCaptureKit (<font face='Courier'>sourceRect</font> where appropriate).",
                "Pass the resulting image to Vision RecognizeTextRequest. Prefer accurate recognition; allow language hints from system locale.",
                "Join recognized lines in visual order, trim empty lines, write the final string to NSPasteboard.general.",
                "Show a small “Copied” confirmation for about 1 second, then exit.",
                "Screen capture requires Screen Recording permission. Denial should show a compact explanation with a button to open System Settings, not a broken selection flow.",
            ]
        ),
        P("5.6 Clipboard", "h2"),
        P("Goal: recover the last few copied text snippets without becoming a full clipboard product."),
        bullets(
            [
                "Poll NSPasteboard.general.changeCount on a modest interval while the app is running. When it changes, read supported content types.",
                "MVP stores only plain text and URLs. Default history size: 10; make 5–10 configurable.",
                "Deduplicate consecutive identical values. Clicking a history item writes it back to the pasteboard and closes the panel.",
                "Keep clipboard history in memory only. Do not persist it across launches.",
                "Avoid capturing data marked transient/concealed by source apps when detectable. Add an explicit “Pause clipboard history” switch.",
                "Never market this as password storage. A future secure-snippets feature would be a separate design using Keychain.",
            ]
        ),
    ]

    out += [
        P("6. State, persistence, and services", "h1"),
        table(
            ["Data", "Storage", "Notes"],
            [
                ["Active Dot configuration", "UserDefaults / @AppStorage", "Ordered list of DotIDs, max count, launcher preferences."],
                ["Tasks", "UserDefaults JSON for MVP", "Durable user content. SwiftData later only if the model grows."],
                ["Timer", "UserDefaults", "Persist targetEndDate/status so UI can reconstruct after dismissal/relaunch."],
                ["Clipboard history", "Memory only", "Privacy-first MVP; cleared on quit."],
                ["Red Pen strokes", "Memory only", "Destroyed on exit."],
                ["OCR image", "Memory only", "Release immediately after recognition."],
                ["Mirror frames", "Not stored", "Live preview only. Preview offset is session-only; close re-docks."],
            ],
            [1.7 * inch, 1.7 * inch, w - 3.4 * inch],
        ),
        P("6.1 Service protocols", "h2"),
        code_block(
            """protocol SpeechTranscribing {
    func transcribeLive() -> AsyncThrowingStream<String, Error>
    func stop() async
}

protocol TaskExtracting {
    func extractTasks(from transcript: String) async throws -> [TaskDraft]
}

protocol OCRRecognizing {
    func recognizeText(in image: CGImage) async throws -> String
}

protocol ScreenRegionCapturing {
    func capture(rect: CGRect, on screen: NSScreen) async throws -> CGImage
}

protocol ClipboardMonitoring {
    var items: AsyncStream<[ClipboardItem]> { get }
    func copy(_ item: ClipboardItem)
}"""
        ),
        P("Keep Apple-framework types inside service implementations where practical. Feature views should depend on app protocols."),
    ]

    out += [
        P("7. Permissions, sandboxing, and privacy", "h1"),
        table(
            ["Capability", "Used by", "Behavior"],
            [
                ["Camera", "Mirror", "Request on first use; camera usage description + sandbox camera entitlement. Present in the prototype."],
                ["Microphone", "Voice tasks", "Request on first use; microphone usage description + Audio Input entitlement."],
                ["Speech recognition", "Voice tasks", "Provide required usage description/authorization path for the Speech framework APIs used."],
                ["Screen Recording", "Screen → Text", "ScreenCaptureKit requires user authorization. Detect denial and provide recovery UI."],
                ["Notifications", "Pomodoro", "Optional. Timer still functions if notification permission is denied."],
                ["Accessibility / Input Monitoring", "None in base MVP", "Do not add unless later functionality truly requires synthetic input/global event taps."],
            ],
            [1.55 * inch, 1.15 * inch, w - 2.7 * inch],
        ),
        P("<b>Privacy defaults.</b> No backend for the base MVP. Prefer on-device OCR, speech, and task extraction when available. Do not retain camera frames, microphone recordings, OCR screenshots, or Red Pen pixels. If a future cloud LLM fallback is added, it must be an explicit provider layer with disclosure and opt-in. Clipboard history is in-memory and easy to pause/clear."),
    ]

    out += [
        P("8. Suggested Xcode project structure", "h1"),
        P("Target layout as the registry lands. The prototype may stay flatter until checkpoint 2."),
        code_block(
            """TheDots/
  App/          TheDotsApp, AppCoordinator, AppServices
  Core/         DotID, DotDescriptor, DotRegistry, DotContext,
                PermissionCenter, SettingsStore
  Launcher/     LauncherController, LauncherPanel, LauncherView,
                DotOrbView, DotMagnetism, ScreenGeometry
  Presentation/ FeaturePresenter, TransientPanel, OverlayWindow,
                ToastPresenter
  Features/     Mirror, Tasks, Pomodoro, RedPen, ScreenToText, Clipboard
  Services/     Camera, Speech, TaskExtraction, FoundationModel extractor,
                Fallback extractor, ScreenCapture, OCR, Clipboard, Timer
  Data/         TaskItem, TimerState
  Settings/  Onboarding/  Resources/

TheDotsTests/
  DotMagnetismTests, TaskExtractionTests, TimerStateTests,
  ClipboardDedupTests, OCRTextOrderingTests,
  DotsLayoutTests (orb geometry, hanging widgets, Mirror detach)"""
        ),
    ]

    out += [
        P("9. Implementation sequence", "h1"),
        P("Build vertically in small checkpoints. Do not implement all services before the shell is usable. Keep the project buildable at every checkpoint. No third-party dependencies unless a native implementation is materially worse and the dependency is explicitly approved."),
        table(
            ["#", "Checkpoint", "Status"],
            [
                ["1", "Shell prototype: top-edge nonactivating NSPanel, orbs, correct positioning on one display, hover/click, click-through.", "Done"],
                ["2", "Launcher system: 1–5 Dots, ordering, nearest-dot magnetism, feature presenter, Escape dismissal, multi-display positioning.", "In progress (registry + magnetism)"],
                ["3", "Mirror: permission + mirrored preview + stop on close. Draggable 120 pt circle; sprout hides when detached; generation-token lifecycle; 640×480 preset.", "Done (drag included)"],
                ["4", "Pomodoro: timer state outside the panel, notification optional. Validates persistent background-ish state.", "Not started"],
                ["5", "Tasks text-only (local persist, AppKit composer). Then voice transcription and task extraction as separate adapters.", "Text done; voice not started"],
                ["6", "Screen → Text: selection overlay → region capture → Vision OCR → clipboard → toast.", "Not started"],
                ["7", "Clipboard: changeCount monitor, memory history, dedupe, re-copy.", "Not started"],
                ["8", "Red Pen: transparent overlay, vector strokes, Escape/undo, pointer-mode restoration.", "Not started"],
                ["9", "Onboarding/settings: choose/reorder Dots, permissions status, defaults.", "Not started"],
                ["10", "Polish: magnetism animation, reduced-motion, VoiceOver, launch-at-login if desired, App Store sandbox testing.", "Partial (reduce-motion on open, VO labels on existing orbs)"],
            ],
            [0.4 * inch, w - 1.35 * inch, 0.95 * inch],
        ),
    ]

    out += [
        P("10. Acceptance checklist", "h1"),
        table(
            ["Area", "Pass condition", "Now"],
            [
                ["Launcher", "1–5 Dots at top edge, nearest Dot reacts magnetically, no visual jitter, clicks target reliably despite 16 pt orb.", "Partial — registry, stable magnetism, padded hits; settings/order pending"],
                ["Focus", "Hovering/clicking non-text Dots does not activate The Dots or steal keyboard focus.", "Pass for non-text (prototype)"],
                ["Escape", "Escape closes the open feature and returns to the prior app.", "Fail"],
                ["Mirror", "Preview appears after permission, mirrored, camera stops when closed.", "Pass"],
                ["Mirror drag", "Preview can be placed anywhere on the display; Mirror sprout disappears once detached; close re-docks.", "Pass"],
                ["Tasks text", "Text task survives relaunch. Composer accepts typing in the overlay and clears after Return/+.", "Pass"],
                ["Tasks voice", "One dictated sentence with three clear actions can become three editable tasks.", "Fail"],
                ["Pomodoro", "Timer continues while panel is closed and recovers remaining time after UI changes/relaunch.", "Fail"],
                ["Red Pen", "Can draw/highlight/arrow over another app; Escape removes everything and returns normal clicking immediately.", "Fail"],
                ["Screen → Text", "Drag area → OCR → clipboard with no save dialog or intermediate window.", "Fail"],
                ["Clipboard", "Recent 5–10 text items appear, duplicates do not pile up, selecting one copies it again.", "Fail"],
                ["Permissions", "Every denied permission fails gracefully and explains the missing capability.", "Mirror only"],
                ["Privacy", "No images/audio/clipboard history accidentally written to durable storage.", "Pass so far"],
            ],
            [1.15 * inch, w - 1.9 * inch, 0.75 * inch],
        ),
        P("<b>Performance targets.</b> Launcher idle CPU should be effectively negligible. Pointer tracking should not trigger expensive SwiftUI rebuilds. Feature panel animation should begin immediately after click; do not block UI on permission or model initialization. Prewarm local task extraction only when useful. Clipboard polling around 0.5–1.0 seconds, then measure."),
    ]

    out += [
        P("11. Explicit decisions and open questions", "h1"),
        table(
            ["Decision", "Current choice"],
            [
                ["Maximum visible Dots", "5 for MVP; configurable constant."],
                ["Visible orb size", "16 × 16 pt; hit area larger than the fill."],
                ["Orbs vs widgets", "Orbs never grow. Widgets hang below or detach."],
                ["Minimum macOS", "14.0. Foundation Models and modern Speech APIs are availability-gated."],
                ["Backend", "None required for MVP."],
                ["Task persistence", "UserDefaults JSON for MVP. SwiftData later only if needed."],
                ["Task AI", "Apple Foundation Models when available; deterministic fallback; cloud later if needed."],
                ["Clipboard persistence", "Memory only."],
                ["Red Pen persistence", "None."],
                ["Mirror persistence", "None. Drag offset is session-only; close re-docks."],
                ["Cluster drag", "No. Only the Mirror preview is draggable."],
                ["Launcher placement", "Flush with visibleFrame.maxY, horizontally centered, display under the pointer."],
                ["Notes feature", "Not included."],
            ],
            [1.7 * inch, w - 1.7 * inch],
        ),
        P("<b>Still open after the prototype</b>", "h2"),
        bullets(
            [
                "Exact magnetic activation radius and easing curve.",
                "Whether the launcher relocates live as the pointer moves to another display, or only at launch / screen-parameter changes.",
                "Whether voice task capture is tap-to-toggle or press-and-hold.",
                "Whether Screen → Text supports multi-line formatting or always returns plain text.",
                "Whether Red Pen starts directly in pen mode or remembers the last tool.",
            ]
        ),
        P("12. Apple framework references", "h1"),
        P("Implementation references, not product dependencies. Re-check API availability against the deployment target while coding."),
        table(
            ["Framework / API", "Why"],
            [
                ["Foundation Models", "Native language models, structured output, tool calling for task extraction."],
                ["SpeechAnalyzer", "Modern asynchronous speech analysis/transcription."],
                ["Vision RecognizeTextRequest", "On-device OCR."],
                ["ScreenCaptureKit + sourceRect", "Region capture for Screen → Text."],
                ["AVCaptureVideoPreviewLayer", "Live mirrored camera preview."],
                ["NSPanel + nonactivatingPanel", "Top-edge auxiliary panel that does not steal the active app."],
                ["NSPasteboard.changeCount", "Detect general pasteboard content changes."],
            ],
            [2.3 * inch, w - 2.3 * inch],
        ),
        P("<b>End state.</b> The first release should feel like six tiny capabilities attached to the top of macOS, not six mini-apps living inside a launcher. The architecture exists to preserve that constraint while allowing the catalog of Dots to grow later."),
    ]

    flat = []
    for item in out:
        if isinstance(item, list):
            flat.extend(item)
        else:
            flat.append(item)
    return flat


def main():
    dests = [
        Path("/Users/personal/Downloads/The_Dots_macOS_Architecture.pdf"),
        Path("/Users/personal/Documents/Dots/The_Dots_macOS_Architecture.pdf"),
    ]
    for dest in dests:
        dest.parent.mkdir(parents=True, exist_ok=True)
        doc = SimpleDocTemplate(
            str(dest),
            pagesize=letter,
            leftMargin=LEFT,
            rightMargin=RIGHT,
            topMargin=TOP,
            bottomMargin=BOTTOM,
            title="The Dots — macOS Product + Technical Architecture",
            author="yaosamo",
            subject="MVP implementation brief for Codex and Grok",
        )
        doc.build(story(), onFirstPage=header_footer, onLaterPages=header_footer)
        print(dest)


if __name__ == "__main__":
    main()
