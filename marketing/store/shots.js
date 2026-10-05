// Each Mac App Store screenshot: its words, its capture (in captures/) and where the pills sit.
// The card is centered, its top at 260px; positions are CSS px on the 1440×900 page.
// Render with ./render.sh <name> (or no name for all). See docs/marketing-assets.md.
const SHOTS = {
  // Calibration only: the live 1.0 clipboard screenshot, rebuilt from a crop of its own card.
  "calibrate-clipboard": {
    label: "Clipboard", tint: "clipboard",
    title: "Your last five copies.",
    sub: "Text and images, one click away from being copied again.",
    capture: "captures/calibrate-clipboard.png",
    card: { width: 1120, height: 395 },
    pills: [
      { text: "Press 1–5 to copy again", at: { left: "130px", top: "300px" } },
      { text: "Passwords are never recorded", at: { left: "1016px", top: "665px" } },
    ],
  },

  "06-screenshot": {
    label: "Screenshot", tint: "screenshot",
    title: "Screenshots, framed.",
    sub: "Snap an area or a window, set it in a frame, point at what matters.",
    capture: "captures/06-screenshot.png",
    card: { width: 1074, height: 605 },
    pills: [
      { text: "Safari or macOS title bar", at: { left: "118px", top: "430px" } },
      { text: "Arrows, boxes and a pen", at: { left: "1050px", top: "300px" } },
      { text: "Copy, and paste anywhere", at: { left: "1030px", top: "760px" } },
    ],
  },

  "03-dots": {
    label: "Dots", tint: "pen",
    title: "Six tiny tools. One dot each.",
    sub: "They live at the top of your screen, a shortcut away from any app.",
    capture: "captures/03-dots.png",
    card: { width: 1250, height: 200 },
    columns: [
      { name: "Camera", tint: "camera", line: "Selfie bubble for calls", key: "⌃⇧1" },
      { name: "Tasks", tint: "tasks", line: "A list over everything", key: "⌃⇧2" },
      { name: "Pen", tint: "pen", line: "Draw on any screen", key: "⌃⇧3" },
      { name: "Timer", tint: "timer", line: "A die that counts down", key: "⌃⇧4" },
      { name: "Clipboard", tint: "clipboard", line: "Your last ten copies", key: "⌃⇧5" },
      { name: "Screenshot", tint: "screenshot", line: "Shots in a frame", key: "⌃⇧6" },
    ],
  },
};
