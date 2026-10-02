// The night sky behind the clouds in dark mode: a few hundred stars, thicker toward the top, a
// handful brighter and faintly blue, each twinkling on its own beat. Drawn at the screen's full
// resolution (the clouds are drawn smaller and stretched), under the clouds, so they pass in front.
(() => {
  const hero = document.querySelector(".hero");
  const canvas = hero && hero.querySelector(".stars");
  const ctx = canvas && canvas.getContext("2d");
  if (!ctx) return;

  const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const darkScheme = matchMedia("(prefers-color-scheme: dark)");
  const isNight = () => {
    const theme = document.documentElement.dataset.theme;
    return theme ? theme === "dark" : darkScheme.matches;
  };

  let stars = [];
  let width = 0;
  let height = 0;
  const place = () => {
    const ratio = window.devicePixelRatio || 1;
    width = canvas.clientWidth;
    height = canvas.clientHeight;
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    const count = Math.round((width * height) / 2400);
    stars = Array.from({ length: count }, () => {
      const bright = Math.random() < 0.08;
      return {
        x: Math.random() * width,
        // Thicker toward the top; the sky fades into the page below.
        y: Math.pow(Math.random(), 1.7) * height * 0.8,
        r: bright ? 1 + Math.random() * 0.6 : 0.35 + Math.random() * 0.6,
        alpha: bright ? 0.9 : 0.25 + Math.random() * 0.55,
        hue: bright && Math.random() < 0.5 ? "200, 220, 255" : "255, 255, 255",
        speed: 0.6 + Math.random() * 1.8,
        phase: Math.random() * Math.PI * 2,
      };
    });
  };

  const draw = (now) => {
    ctx.clearRect(0, 0, width, height);
    const time = now / 1000;
    for (const star of stars) {
      const twinkle = calm ? 1 : 0.65 + 0.35 * Math.sin(time * star.speed + star.phase);
      ctx.fillStyle = `rgba(${star.hue}, ${star.alpha * twinkle})`;
      ctx.beginPath();
      ctx.arc(star.x, star.y, star.r, 0, Math.PI * 2);
      ctx.fill();
    }
  };

  // A dozen frames a second is plenty for a twinkle, and only at night with the sky on screen.
  let visible = true;
  let timer = 0;
  const run = () => {
    clearInterval(timer);
    timer = 0;
    if (!isNight()) { ctx.clearRect(0, 0, width, height); return; }
    draw(performance.now());
    if (visible && !calm) timer = setInterval(() => draw(performance.now()), 1000 / 12);
  };

  place();
  run();
  new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; run(); }).observe(hero);
  darkScheme.addEventListener("change", run);
  let resizing = 0;
  addEventListener("resize", () => {
    cancelAnimationFrame(resizing);
    resizing = requestAnimationFrame(() => { place(); run(); });
  });
})();
