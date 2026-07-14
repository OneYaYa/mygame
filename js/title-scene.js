const PALETTE = {
  sky: "#04090d",
  skyBand: "#04090d",
  far: "#0b2029",
  middle: "#0a1921",
  near: "#061016",
  stone: "#26363a",
  stoneLight: "#3b4b4c",
  ember: "#b94d2b",
  flame: "#e4a35d",
  star: "#8fa2a2",
  lamp: "#c7824d",
};

const STARS = [
  [0.08, 0.12], [0.17, 0.26], [0.29, 0.09], [0.41, 0.20],
  [0.55, 0.11], [0.66, 0.27], [0.78, 0.15], [0.91, 0.24],
  [0.48, 0.36], [0.73, 0.39], [0.86, 0.07],
];

function block(ctx, color, x, y, width, height) {
  ctx.fillStyle = color;
  ctx.fillRect(Math.round(x), Math.round(y), Math.round(width), Math.round(height));
}

function polygon(ctx, color, points) {
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.moveTo(Math.round(points[0][0]), Math.round(points[0][1]));
  points.slice(1).forEach(([x, y]) => ctx.lineTo(Math.round(x), Math.round(y)));
  ctx.closePath();
  ctx.fill();
}

function drawPine(ctx, x, ground, scale = 1) {
  block(ctx, PALETTE.near, x - scale, ground - 9 * scale, 2 * scale, 9 * scale);
  polygon(ctx, PALETTE.middle, [
    [x, ground - 25 * scale], [x - 7 * scale, ground - 8 * scale],
    [x - 3 * scale, ground - 8 * scale], [x - 9 * scale, ground - 2 * scale],
    [x + 9 * scale, ground - 2 * scale], [x + 3 * scale, ground - 8 * scale],
    [x + 7 * scale, ground - 8 * scale],
  ]);
}

function drawFiveLands(ctx, width, horizon) {
  const start = width * 0.50;
  const step = Math.max(18, width * 0.085);
  const base = horizon + 2;
  const ink = PALETTE.middle;

  // 王城塔影
  block(ctx, ink, start, base - 15, 3, 15);
  block(ctx, ink, start + 5, base - 21, 4, 21);
  block(ctx, ink, start + 11, base - 12, 3, 12);
  block(ctx, PALETTE.lamp, start + 6, base - 15, 1, 1);

  // 农田风车
  const farmX = start + step;
  block(ctx, ink, farmX, base - 12, 3, 12);
  block(ctx, ink, farmX - 5, base - 10, 13, 1);
  block(ctx, ink, farmX + 1, base - 16, 1, 13);
  block(ctx, PALETTE.lamp, farmX + 1, base - 5, 1, 1);

  // 白棘庄园屋顶
  const houseX = start + step * 2;
  polygon(ctx, ink, [[houseX - 7, base - 9], [houseX, base - 16], [houseX + 8, base - 9]]);
  block(ctx, ink, houseX - 6, base - 9, 13, 9);
  block(ctx, PALETTE.lamp, houseX + 2, base - 6, 1, 1);

  // 雪山
  const snowX = start + step * 3;
  polygon(ctx, ink, [[snowX - 9, base], [snowX, base - 21], [snowX + 10, base]]);
  block(ctx, PALETTE.lamp, snowX, base - 6, 1, 1);

  // 沙丘与路标
  const desertX = start + step * 4;
  polygon(ctx, ink, [[desertX - 10, base], [desertX - 1, base - 7], [desertX + 12, base]]);
  block(ctx, ink, desertX + 5, base - 11, 2, 11);
  block(ctx, ink, desertX + 2, base - 8, 5, 2);
  block(ctx, PALETTE.lamp, desertX - 1, base - 3, 1, 1);
}

function drawTraveler(ctx, x, ground, visible) {
  if (!visible) return;
  block(ctx, "#101a1d", x, ground - 14, 4, 4);
  block(ctx, "#172328", x - 1, ground - 10, 6, 7);
  block(ctx, "#273137", x + 4, ground - 8, 4, 3);
  block(ctx, "#10181c", x + 1, ground - 3, 9, 3);
  block(ctx, PALETTE.ember, x + 3, ground - 9, 1, 2);
}

function drawWell(ctx, x, ground, frame) {
  block(ctx, "rgba(185, 77, 43, .035)", x - 30, ground - 21, 60, 23);
  block(ctx, "rgba(185, 77, 43, .055)", x - 20, ground - 15, 40, 15);
  block(ctx, "#111a1d", x - 15, ground - 5, 30, 5);
  block(ctx, PALETTE.stone, x - 13, ground - 7, 26, 3);
  block(ctx, PALETTE.stoneLight, x - 9, ground - 8, 18, 2);
  block(ctx, "#150d0b", x - 9, ground - 6, 18, 3);
  block(ctx, PALETTE.ember, x - 7, ground - 6, 14, 2);
  const sway = frame % 2;
  block(ctx, PALETTE.ember, x - 2 + sway, ground - 13, 5, 7);
  block(ctx, PALETTE.flame, x - 1, ground - 11 - sway, 3, 5);
  block(ctx, "#f0c379", x, ground - 9 - sway, 1, 3);
}

function drawMeteor(ctx, width, height, elapsed, reducedMotion) {
  if (reducedMotion) return;
  const cycle = elapsed % 22000;
  if (cycle > 850) return;
  const travel = cycle / 850;
  const x = width * 0.58 + travel * width * 0.18;
  const y = height * 0.10 + travel * height * 0.08;
  block(ctx, "#d7b284", x, y, 2, 1);
  block(ctx, "#9d6f4e", x - 3, y - 1, 3, 1);
  block(ctx, "#51443d", x - 6, y - 2, 3, 1);
}

export function initTitleScene() {
  const canvas = document.getElementById("title-canvas");
  const title = document.getElementById("title-screen");
  if (!canvas || !title) return;

  const ctx = canvas.getContext("2d", { alpha: false });
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  let observerPreview = false;
  let lastFrame = -1;

  const resize = () => {
    const pixelSize = window.innerWidth < 700 ? 3 : 4;
    const nextWidth = Math.max(200, Math.ceil(canvas.clientWidth / pixelSize));
    const nextHeight = Math.max(180, Math.ceil(canvas.clientHeight / pixelSize));
    if (canvas.width === nextWidth && canvas.height === nextHeight) return;
    canvas.width = nextWidth;
    canvas.height = nextHeight;
    ctx.imageSmoothingEnabled = false;
    lastFrame = -1;
  };

  const menuButtons = () => [...title.querySelectorAll(".title-actions button:not(.hidden)")];
  title.querySelectorAll(".title-actions button").forEach((button) => {
    const updatePreview = () => { observerPreview = button.id === "observe-game-button"; };
    button.addEventListener("focus", updatePreview);
    button.addEventListener("mouseenter", updatePreview);
    button.addEventListener("mouseleave", () => {
      observerPreview = document.activeElement?.id === "observe-game-button";
    });
  });

  window.addEventListener("keydown", (event) => {
    if (title.classList.contains("hidden")) return;
    if (document.querySelector(".modal-layer:not(.hidden)")) return;
    const buttons = menuButtons();
    if (!buttons.length) return;
    const current = buttons.indexOf(document.activeElement);
    const down = event.key === "ArrowDown" || event.key.toLowerCase() === "s";
    const up = event.key === "ArrowUp" || event.key.toLowerCase() === "w";
    if (event.key === "Enter" && current < 0) {
      event.preventDefault();
      buttons[0].click();
      return;
    }
    if (!down && !up) return;
    event.preventDefault();
    const next = current < 0
      ? (down ? 0 : buttons.length - 1)
      : (current + (down ? 1 : -1) + buttons.length) % buttons.length;
    buttons[next].focus();
  });

  const render = (time) => {
    requestAnimationFrame(render);
    if (title.classList.contains("hidden")) return;
    const frame = reducedMotion ? 0 : Math.floor(time / 420) % 2;
    if (frame === lastFrame && time % 22000 > 900) return;
    lastFrame = frame;

    const width = canvas.width;
    const height = canvas.height;
    const portrait = height > width * 1.05;
    const ground = Math.round(height * (portrait ? 0.82 : 0.76));
    const horizon = Math.round(height * (portrait ? 0.67 : 0.59));
    const focusX = Math.round(width * (portrait ? 0.72 : 0.73));

    block(ctx, PALETTE.sky, 0, 0, width, height);
    block(ctx, PALETTE.skyBand, 0, Math.round(height * 0.46), width, height * 0.54);

    STARS.forEach(([x, y], index) => {
      const lit = reducedMotion || (index + frame) % 4 !== 0;
      block(ctx, lit ? PALETTE.star : "#3d5054", width * x, height * y, 1, 1);
    });
    drawMeteor(ctx, width, height, time, reducedMotion);

    polygon(ctx, PALETTE.far, [
      [0, horizon + 12], [width * .12, horizon - 11], [width * .23, horizon + 2],
      [width * .36, horizon - 24], [width * .49, horizon + 5], [width * .63, horizon - 17],
      [width * .78, horizon + 3], [width * .90, horizon - 12], [width, horizon], [width, height], [0, height],
    ]);
    drawFiveLands(ctx, width, horizon);
    polygon(ctx, PALETTE.middle, [
      [0, ground - 6], [width * .12, ground - 18], [width * .25, ground - 5],
      [width * .40, ground - 14], [width * .55, ground - 3], [width * .68, ground - 11],
      [width * .83, ground - 4], [width, ground - 16], [width, height], [0, height],
    ]);

    drawPine(ctx, width * (portrait ? .16 : .43), ground + 1, portrait ? .7 : .9);
    drawPine(ctx, width * .93, ground + 2, .72);
    drawTraveler(ctx, focusX - 24, ground, !observerPreview);
    drawWell(ctx, focusX, ground, frame);

    polygon(ctx, PALETTE.near, [
      [0, ground + 10], [width * .17, ground + 5], [width * .34, ground + 13],
      [width * .52, ground + 7], [width * .69, ground + 12], [width * .84, ground + 6],
      [width, ground + 11], [width, height], [0, height],
    ]);
    block(ctx, PALETTE.stone, focusX + 28, ground + 4, 9, 3);
    block(ctx, PALETTE.middle, focusX + 31, ground + 1, 4, 3);
  };

  resize();
  if ("ResizeObserver" in window) new ResizeObserver(resize).observe(canvas);
  window.addEventListener("resize", resize, { passive: true });
  requestAnimationFrame(render);
}
