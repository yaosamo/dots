// The welcome's clouds, as the app draws them: a WebGL port of Dots/Shaders/CloudShader.metal
// (and Noise.h), with the app's WelcomeTuning values. Falls back to clouds.png without WebGL.
(() => {
  const hero = document.querySelector(".hero");
  const canvas = hero && hero.querySelector(".clouds-canvas");
  const gl = canvas && canvas.getContext("webgl", { premultipliedAlpha: true, alpha: true, antialias: false });
  if (!gl) return;

  const vertex = `
    attribute vec2 corner;
    void main() { gl_Position = vec4(corner, 0.0, 1.0); }
  `;

  // WelcomeTuning, tuned for a page: cloudSize 2.762, softness 0.337, depth 0 as in the app; more gaps,
  // a shorter bank and less fog than the app (holes 0.2, reach 0.741, edgeFog 0.832 there), so the sky shows;
  // drift 0.025; the veil softer here (0.878 in the app), the sky behind being so pale; three layers, shape 4, warp 1, puff 2, shade 2, wisps 2, edge 2.
  const fragment = `
    precision highp float;
    uniform vec2 size;
    uniform float time, descend, leave, fade, seed;

    const float SCALE = 2.762;
    const float HOLES = 0.3;
    const float SOFTNESS = 0.337;
    const float TRAVEL = 0.0;
    const float REACH = 0.62;
    const float EDGE_FOG = 0.5;
    const float DRIFT = 0.025;
    const float VEIL = 0.6;

    float hash(vec2 p) {
      p = fract(p * vec2(123.34, 456.21));
      p += dot(p, p + 45.32);
      return fract(p.x * p.y);
    }

    float noise(vec2 p) {
      vec2 i = floor(p);
      vec2 f = fract(p);
      vec2 u = f * f * (3.0 - 2.0 * f);
      return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
                 mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
    }

    // Octave counts only known at run time: loop to the most and stop early (GLSL ES 1.0).
    float fbm(vec2 p, int octaves) {
      if (octaves <= 0) return 0.5;
      float value = 0.0;
      float amplitude = 0.5;
      for (int i = 0; i < 6; i++) {
        if (i >= octaves) break;
        value += amplitude * noise(p);
        p *= 2.03;
        amplitude *= 0.5;
      }
      return value;
    }

    float billow(vec2 p, int octaves) {
      if (octaves <= 0) return 0.5;
      float value = 0.0;
      float amplitude = 0.5;
      for (int i = 0; i < 6; i++) {
        if (i >= octaves) break;
        value += amplitude * (1.0 - abs(noise(p) * 2.0 - 1.0));
        p *= 2.03;
        amplitude *= 0.5;
      }
      return value;
    }

    vec4 cloudLayer(vec2 uv, float aspect, float depth) {
      float layerSeed = seed + depth * 17.3;
      float layerScale = SCALE * mix(2.2, 0.75, depth);
      int less = depth < 0.25 ? 1 : 0;
      float fall = (1.0 - descend) * TRAVEL * mix(0.5, 1.4, depth) + leave * TRAVEL * mix(0.6, 1.6, depth);
      vec2 q = uv + vec2(-time * DRIFT * mix(0.4, 1.0, depth), fall);
      vec2 p = q * layerScale + layerSeed;

      vec2 warp = vec2(noise(p * 0.5 + vec2(0.0, time * 0.01)), noise(p * 0.5 + vec2(5.2, 1.3))) - 0.5;
      vec2 w = p + warp * 0.9;
      float n = fbm(w, 4 - less) + (billow(w * 2.3, 2 - less) - 0.5) * 0.22;
      float above = fbm(w - vec2(0.0, 0.12), 2 - less);

      float front = descend * (1.0 - leave) * REACH * mix(0.85, 1.05, depth);
      float ragged = (fbm(vec2(uv.x * 2.2, time * 0.05) + layerSeed, 2) - 0.5) * 0.35;
      float inBank = 1.0 - smoothstep(front - 0.12, front + 0.14, uv.y + ragged);

      vec2 centered = vec2((uv.x - aspect * 0.5) / aspect, uv.y - 0.5) * 2.0;
      float edge = smoothstep(0.35, 1.05, length(centered * vec2(1.0, 0.8)));

      float body = n + edge * EDGE_FOG * 0.25 - (1.0 - inBank) * 0.7 - leave * 0.35;
      float cover = HOLES + (1.0 - depth) * 0.06;
      float density = smoothstep(cover, cover + SOFTNESS, body);
      density *= mix(smoothstep(0.2, 0.6, fbm(w * 3.1, 2 - less)), 1.0, smoothstep(0.3, 0.7, density));
      float fog = inBank * mix(0.05, 0.35, edge) * EDGE_FOG;
      float alpha = clamp(max(density, fog * (1.0 - depth * 0.5)), 0.0, 1.0) * mix(0.55, 1.0, depth);

      float lit = clamp(0.7 + (n - above) * 2.5 + density * 0.3, 0.0, 1.0);
      vec3 shadow = mix(vec3(0.80, 0.83, 0.89), vec3(0.86, 0.88, 0.92), depth);
      vec3 colour = mix(shadow, vec3(1.0), lit);
      colour = mix(vec3(0.90, 0.92, 0.96), colour, mix(0.6, 1.0, depth));
      return vec4(colour * alpha, alpha);
    }

    void main() {
      float aspect = size.x / size.y;
      // 0…1 down the view, height = 1, like the app.
      vec2 view = vec2(gl_FragCoord.x / size.x, 1.0 - gl_FragCoord.y / size.y);
      vec2 uv = vec2(view.x * aspect, view.y);

      vec4 result = vec4(0.0);
      for (int i = 0; i < 3; i++) {
        vec4 layer = cloudLayer(uv, aspect, float(i) / 2.0);
        result = layer + result * (1.0 - layer.a);
      }

      vec2 d = vec2(uv.x - aspect * 0.5, uv.y - 0.5);
      float v = VEIL * exp(-dot(d, d) * 5.0) * descend * (1.0 - leave);
      result = vec4(v) + result * (1.0 - v);
      gl_FragColor = result * fade;
    }
  `;

  const compile = (type, source) => {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    return gl.getShaderParameter(shader, gl.COMPILE_STATUS) ? shader : null;
  };
  const vs = compile(gl.VERTEX_SHADER, vertex);
  const fs = compile(gl.FRAGMENT_SHADER, fragment);
  if (!vs || !fs) return;
  const program = gl.createProgram();
  gl.attachShader(program, vs);
  gl.attachShader(program, fs);
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) return;
  gl.useProgram(program);

  // One triangle that covers the whole view.
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const corner = gl.getAttribLocation(program, "corner");
  gl.enableVertexAttribArray(corner);
  gl.vertexAttribPointer(corner, 2, gl.FLOAT, false, 0, 0);

  const at = (name) => gl.getUniformLocation(program, name);
  const u = { size: at("size"), time: at("time"), descend: at("descend"), leave: at("leave"), fade: at("fade"), seed: at("seed") };
  gl.uniform1f(u.seed, Math.random() * 50); // different clouds each time, as in the app
  gl.uniform1f(u.leave, 0);

  // Drawn smaller than the view and stretched up, like the app (cloudResolution 0.33, a bit more here).
  const resolution = 0.45;
  const resize = () => {
    const ratio = (window.devicePixelRatio || 1) * resolution;
    const width = Math.max(1, Math.round(canvas.clientWidth * ratio));
    const height = Math.max(1, Math.round(canvas.clientHeight * ratio));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
      gl.viewport(0, 0, width, height);
    }
    gl.uniform2f(u.size, width, height);
  };

  const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const start = performance.now();
  const easeOut = (x) => 1 - Math.pow(1 - Math.min(Math.max(x, 0), 1), 3);
  const draw = (now) => {
    // Reduced motion: the bank already down, holding still.
    const time = calm ? 12 : (now - start) / 1000;
    resize();
    gl.uniform1f(u.time, time);
    gl.uniform1f(u.descend, calm ? 1 : easeOut(time / 1.636));
    gl.uniform1f(u.fade, calm ? 1 : Math.min(time / 0.4, 1));
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  };

  hero.classList.add("has-clouds");
  let visible = true;
  let frame = 0;
  const loop = (now) => {
    draw(now);
    frame = visible && !calm ? requestAnimationFrame(loop) : 0;
  };
  // Only while the top of the page is on screen.
  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    if (visible && !frame) frame = requestAnimationFrame(loop);
  }).observe(hero);
  addEventListener("resize", () => { if (calm) draw(performance.now()); });
  frame = requestAnimationFrame(loop);
})();
