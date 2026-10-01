// The arrow under the dots, drawn like the pen's electric brush (Dots/Shaders/PenShaders.metal):
// the line jumps to a new jitter in ticks, with a flickering blue corona around a pale core.
// ShaderTuning: rate 10.42 ticks a second, glow radius 9.7; the brush's line is 3 points.
(() => {
  const canvas = document.querySelector(".electric");
  const ctx = canvas && canvas.getContext("2d");
  if (!ctx) return;
  const css = { width: 48, height: 104 };
  const ratio = window.devicePixelRatio || 1;
  canvas.width = css.width * ratio;
  canvas.height = css.height * ratio;
  ctx.scale(ratio, ratio);

  const RATE = 10.42;
  const GLOW = 9.7;
  const JITTER = 2.6; // scaled down from the brush's 21.8 for a small arrow

  // Value noise, as in Noise.h.
  const hash = (x, y) => {
    let px = (x * 123.34) % 1, py = (y * 456.21) % 1;
    const d = px * (px + 45.32) + py * (py + 45.32);
    px += d; py += d;
    return ((px * py) % 1 + 1) % 1;
  };
  const noise = (x, y) => {
    const ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
    const ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
    const a = hash(ix, iy), b = hash(ix + 1, iy), c = hash(ix, iy + 1), d = hash(ix + 1, iy + 1);
    return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy;
  };

  // The arrow: a line down, then a chevron, as the stroke a pen would draw.
  const cx = css.width / 2;
  const strokes = [
    [[cx, 12], [cx, css.height - 16]],
    [[cx - 15, css.height - 32], [cx, css.height - 14], [cx + 15, css.height - 32]],
  ];
  // Points every 3 px along each stroke, so the jitter can bend it.
  const dense = strokes.map((points) => {
    const out = [];
    for (let i = 0; i < points.length - 1; i++) {
      const [x0, y0] = points[i], [x1, y1] = points[i + 1];
      const steps = Math.max(1, Math.round(Math.hypot(x1 - x0, y1 - y0) / 3));
      for (let s = 0; s < steps; s++) out.push([x0 + ((x1 - x0) * s) / steps, y0 + ((y1 - y0) * s) / steps]);
    }
    out.push(points[points.length - 1]);
    return out;
  });

  const draw = (time) => {
    const tick = Math.floor(time * RATE);
    const flicker = 0.7 + 0.3 * hash(tick, 1);
    ctx.clearRect(0, 0, css.width, css.height);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    const paths = dense.map((points) => {
      const path = new Path2D();
      points.forEach(([x, y], i) => {
        const jx = (noise(x * 0.25 + tick * 3.1, y * 0.25) - 0.5) * 2 * JITTER;
        const jy = (noise(x * 0.25 + 17 + tick * 2.3, y * 0.25) - 0.5) * 2 * JITTER;
        i ? path.lineTo(x + jx, y + jy) : path.moveTo(x + jx, y + jy);
      });
      return path;
    });
    // Corona, then the core: blue (0.25, 0.6, 1) around pale (0.85, 0.95, 1).
    ctx.shadowColor = `rgba(64, 153, 255, ${0.9 * flicker})`;
    ctx.shadowBlur = GLOW * 1.6;
    ctx.strokeStyle = `rgba(64, 153, 255, ${0.85 * flicker})`;
    ctx.lineWidth = 4;
    paths.forEach((path) => ctx.stroke(path));
    ctx.shadowBlur = GLOW * 0.44;
    ctx.strokeStyle = "rgb(217, 242, 255)";
    ctx.lineWidth = 2;
    paths.forEach((path) => ctx.stroke(path));
  };

  const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (calm) { draw(0); return; }
  let visible = true;
  let frame = 0;
  const loop = (now) => {
    draw(now / 1000);
    frame = visible ? requestAnimationFrame(loop) : 0;
  };
  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    if (visible && !frame) frame = requestAnimationFrame(loop);
  }).observe(canvas);
  frame = requestAnimationFrame(loop);
})();
