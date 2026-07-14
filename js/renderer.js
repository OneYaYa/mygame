import { clamp, distance, hashString, rectanglesOverlap, seededNoise } from "./utils.js";
import { getStoryLandmarks } from "./simulation.js";

const WIDTH = 768;
const HEIGHT = 480;
const TILE = 24;
const PIXEL = 2;
const CAMERA_EASE = 8;
const CULL_PADDING = 64;

const FALLBACK_PALETTES = {
  capital: { ground: "#87906b", groundAlt: "#929a73", path: "#c2aa7d", edge: "#455744", accent: "#d5a75d", water: "#55a2ad", wall: "#c9ad7e", roof: "#824e56" },
  farm: { ground: "#79a65a", groundAlt: "#86b362", path: "#d0ac6e", edge: "#46633c", accent: "#e1b953", water: "#55a5a3", wall: "#c39155", roof: "#9e513c" },
  mansion: { ground: "#638b61", groundAlt: "#70986a", path: "#cbbf9d", edge: "#3e5943", accent: "#d68a9b", water: "#599aa6", wall: "#d1b99c", roof: "#604768" },
  snow: { ground: "#d8e4df", groundAlt: "#e7eee8", path: "#b7c9c8", edge: "#607982", accent: "#87c2cf", water: "#609caf", wall: "#99a7a6", roof: "#526d78" },
  desert: { ground: "#d4a55f", groundAlt: "#dfb46d", path: "#c88c50", edge: "#7b593d", accent: "#65a280", water: "#43a49c", wall: "#bc7c4d", roof: "#755044" },
};

const PATH_STYLES = {
  royal: { base: "#cbb88d", edge: "#806b53", light: "#e5cf8a", pattern: "royal" },
  market: { base: "#a38f75", edge: "#66584b", light: "#c7b598", pattern: "cobble" },
  cobble: { base: "#aaa28c", edge: "#6f6b60", light: "#cbc4aa", pattern: "cobble" },
  dirt: { base: "#b98252", edge: "#795637", light: "#d5a46a", pattern: "dirt" },
  farm: { base: "#c69a5e", edge: "#7e5d38", light: "#dfb775", pattern: "farm" },
  garden: { base: "#d3c5a2", edge: "#887d67", light: "#eee2bd", pattern: "garden" },
  marble: { base: "#d5d0bf", edge: "#8f887c", light: "#f1ecdb", pattern: "marble" },
  snow: { base: "#cbdad8", edge: "#879fa2", light: "#eff6f3", pattern: "snow" },
  ice: { base: "#9ec8cc", edge: "#5d8994", light: "#d4eff0", pattern: "ice" },
  sand: { base: "#cf9858", edge: "#93663f", light: "#e7b978", pattern: "sand" },
  ruin: { base: "#94816a", edge: "#5f554c", light: "#b9a78d", pattern: "ruin" },
};

const SKIN_TONES = ["#efbd91", "#e3aa7d", "#cf8e66", "#a9684f", "#f1c9a2"];
const NPC_STYLE = {
  aveline: { hair: "bun", trim: "#e5bc68", outfit: "dress" },
  rowan: { hair: "bob", accessory: "glasses", trim: "#b9a5d1", outfit: "coat" },
  taren: { hair: "short", accessory: "guard", trim: "#9fb4b3", outfit: "uniform" },
  mira: { hair: "braid", accessory: "straw", trim: "#e7bd54", outfit: "overalls" },
  bo: { hair: "short", accessory: "beekeeper", trim: "#f3cf62", outfit: "apron" },
  nia: { hair: "bob", accessory: "kerchief", trim: "#d9b985", outfit: "apron" },
  celeste: { hair: "long", accessory: "jewel", trim: "#e4b667", outfit: "dress" },
  oswin: { hair: "side", accessory: "mustache", trim: "#d2c6a4", outfit: "vest" },
  lune: { hair: "bob", accessory: "beret", trim: "#dd9c78", outfit: "artist" },
  sora: { hair: "braid", accessory: "medic", trim: "#d8f0e4", outfit: "coat" },
  garrick: { hair: "short", accessory: "furhat", trim: "#c2d1d0", outfit: "uniform" },
  ymir: { hair: "long", accessory: "hood", trim: "#b8acd3", outfit: "robe" },
  zahra: { hair: "long", accessory: "headwrap", trim: "#e4b156", outfit: "merchant" },
  kade: { hair: "side", accessory: "glasses", trim: "#d2b682", outfit: "scholar" },
  ruu: { hair: "braid", accessory: "headband", trim: "#9bd19a", outfit: "guide" },
};

function shade(color, amount = 0) {
  const match = /^#([\da-f]{6})$/i.exec(color || "");
  if (!match) return color || "#777777";
  const value = Number.parseInt(match[1], 16);
  const channel = (shift) => clamp(((value >> shift) & 255) + amount, 0, 255);
  return `rgb(${channel(16)}, ${channel(8)}, ${channel(0)})`;
}

function pixelRect(ctx, x, y, w, h, color) {
  ctx.fillStyle = color;
  ctx.fillRect(Math.round(x), Math.round(y), Math.round(w), Math.round(h));
}

function drawPixelLine(ctx, x, y, length, color, vertical = false) {
  pixelRect(ctx, x, y, vertical ? PIXEL : length, vertical ? length : PIXEL, color);
}

function paletteFor(region) {
  return { ...(FALLBACK_PALETTES[region.id] || FALLBACK_PALETTES.capital), ...(region.palette || {}) };
}

function normalizeRect(item) {
  return {
    x: Number(item.x || 0),
    y: Number(item.y || 0),
    w: Number(item.w ?? item.width ?? 24),
    h: Number(item.h ?? item.height ?? 24),
  };
}

function sceneWidth(scene) {
  return Math.max(1, Number(scene?.width || WIDTH));
}

function sceneHeight(scene) {
  return Math.max(1, Number(scene?.height || HEIGHT));
}

function scenePlaceId(state) {
  return state?.placeId || state?.regionId || "";
}

function itemPlaceId(item, fallback = "") {
  return item?.placeId || item?.sceneId || fallback;
}

function rectIntersects(left, right, padding = 0) {
  return left.x < right.x + right.w + padding
    && left.x + left.w > right.x - padding
    && left.y < right.y + right.h + padding
    && left.y + left.h > right.y - padding;
}

function pointRect(item, defaultSize = 24) {
  const rect = normalizeRect(item || {});
  if (!Number.isFinite(rect.w) || rect.w <= 0) rect.w = defaultSize;
  if (!Number.isFinite(rect.h) || rect.h <= 0) rect.h = defaultSize;
  return rect;
}

function pointToRectDistance(point, rect) {
  const dx = Math.max(rect.x - point.x, 0, point.x - (rect.x + rect.w));
  const dy = Math.max(rect.y - point.y, 0, point.y - (rect.y + rect.h));
  return Math.hypot(dx, dy);
}

/** Resolve a macro-region outdoor scene or one of its indoor places. */
export function resolveScene(content, regionId, placeId = regionId) {
  const regions = content?.regions || [];
  const region = regions.find((item) => item.id === regionId) || regions[0] || null;
  if (!region) return null;
  const requested = placeId || regionId || region.id;
  if (requested === region.id) return region;
  const place = (content?.places || []).find((item) => item.id === requested && (!item.regionId || item.regionId === region.id));
  return place || region;
}

export function getCollisionRects(scene) {
  const obstacles = (scene?.obstacles || []).filter((item) => item.collision !== false).map(normalizeRect);
  const buildings = (scene?.buildings || []).filter((item) => item.collision !== false).flatMap((item) => {
    if (Array.isArray(item.collisionRects) && item.collisionRects.length) return item.collisionRects.map(normalizeRect);
    const rect = normalizeRect(item);
    return [{ ...rect, y: rect.y + rect.h * .36, h: rect.h * .64 }];
  });
  const furniture = (scene?.furniture || []).filter((item) => item.collision !== false).map((item) => {
    const rect = normalizeRect(item);
    const inset = Math.min(4, rect.w * .12);
    return { ...rect, x: rect.x + inset, y: rect.y + rect.h * .35, w: Math.max(2, rect.w - inset * 2), h: Math.max(2, rect.h * .65) };
  });
  const solidZones = (scene?.zones || []).filter((item) => item.collision === true).map(normalizeRect);
  return [...obstacles, ...buildings, ...furniture, ...solidZones];
}

export function movePlayer(state, scene, dx, dy) {
  const player = state.player;
  const blockers = getCollisionRects(scene);
  const worldWidth = sceneWidth(scene);
  const worldHeight = sceneHeight(scene);
  const tryAxis = (axis, amount) => {
    if (!amount) return;
    const next = { x: player.x - 8, y: player.y - 7, w: 16, h: 13 };
    if (axis === "x") next.x += amount;
    else next.y += amount;
    const outside = next.x < 8 || next.y < 8 || next.x + next.w > worldWidth - 8 || next.y + next.h > worldHeight - 8;
    if (outside || blockers.some((rect) => rectanglesOverlap(next, rect))) return;
    player[axis] += amount;
  };
  tryAxis("x", dx);
  tryAxis("y", dy);
}

export function nearestNpc(state, content, maxDistance = 58) {
  if (state?.mode === "observer" || state?.player?.present === false) return null;
  let result = null;
  let best = maxDistance;
  const currentPlace = scenePlaceId(state);
  (content.npcs || []).forEach((npc) => {
    const npcState = state.npcs[npc.id];
    const npcPlace = itemPlaceId(npcState, itemPlaceId(npc, npcState?.regionId || npc.regionId || npc.region));
    if (!npcState || npcState.regionId !== state.regionId || npcPlace !== currentPlace) return;
    const currentDistance = distance(state.player, npcState);
    if (currentDistance < best) {
      best = currentDistance;
      result = { profile: npc, state: npcState, distance: currentDistance };
    }
  });
  return result;
}

export function nearestLandmark(state, scene, maxDistance = 48, content = null) {
  if (state?.mode === "observer" || state?.player?.present === false) return null;
  if (!scene || scene.id !== scenePlaceId(state)) return null;
  let result = null;
  let best = maxDistance;
  const landmarks = [...(scene.landmarks || []), ...(content ? getStoryLandmarks(state, content, scene) : [])];
  landmarks.forEach((landmark) => {
    if (itemPlaceId(landmark, scene.id) !== scenePlaceId(state)) return;
    if (!landmark.interactive && !landmark.description) return;
    const currentDistance = pointToRectDistance(state.player, pointRect(landmark, 24));
    if (currentDistance < best) {
      best = currentDistance;
      result = { ...landmark, distance: currentDistance };
    }
  });
  return result;
}

/** Find the closest door, gate, cave mouth, or other scene transition. */
export function nearestPortal(state, sceneOrContent, maxDistance = 52) {
  if (!state?.player) return null;
  const scene = Array.isArray(sceneOrContent?.regions)
    ? resolveScene(sceneOrContent, state.regionId, scenePlaceId(state))
    : sceneOrContent;
  if (!scene || scene.id !== scenePlaceId(state)) return null;
  let result = null;
  let best = maxDistance;
  (scene.portals || []).forEach((portal) => {
    if (portal.disabled || itemPlaceId(portal, scene.id) !== scenePlaceId(state)) return;
    const rect = pointRect(portal, 24);
    const currentDistance = pointToRectDistance(state.player, rect);
    if (currentDistance < best) {
      best = currentDistance;
      result = { ...portal, distance: currentDistance };
    }
  });
  return result;
}

export function updateNpcMovement(state, content, deltaSeconds) {
  (content.npcs || []).forEach((npc) => {
    const npcState = state.npcs[npc.id];
    if (!npcState) return;
    const dx = npcState.targetX - npcState.x;
    const dy = npcState.targetY - npcState.y;
    const length = Math.hypot(dx, dy);
    if (length < 1) return;
    if (Math.abs(dx) > Math.abs(dy)) npcState.facing = dx > 0 ? "right" : "left";
    else npcState.facing = dy > 0 ? "down" : "up";
    const speed = 16 + (hashString(npc.id) % 12);
    const travel = Math.min(length, speed * deltaSeconds);
    npcState.x += dx / length * travel;
    npcState.y += dy / length * travel;
  });
}

export class WorldRenderer {
  constructor(canvas, content) {
    this.canvas = canvas;
    this.context = canvas.getContext("2d");
    this.context.imageSmoothingEnabled = false;
    this.content = content;
    this.elapsed = 0;
    this.playerMoving = false;
    this.actorMotion = new Map();
    this.motionSceneId = null;
    this.camera = { x: 0, y: 0, offsetX: 0, offsetY: 0, sceneId: null };
    this.particles = Array.from({ length: 46 }, (_, index) => ({
      x: (index * 83) % WIDTH,
      y: (index * 47) % HEIGHT,
      speed: 7 + (index % 7) * 3,
      phase: index * .73,
    }));
  }

  setMoving(value) { this.playerMoving = value; }

  sampleActorMotion(actorId, x, y, requestedFacing = "down") {
    const validFacing = ["up", "down", "left", "right"].includes(requestedFacing) ? requestedFacing : null;
    const previous = this.actorMotion.get(actorId);
    const dx = previous ? x - previous.x : 0;
    const dy = previous ? y - previous.y : 0;
    const travel = Math.hypot(dx, dy);
    const moving = Boolean(previous && travel > .01 && travel < 24);
    let facing = validFacing || previous?.facing || "down";
    if (moving) facing = Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? "right" : "left") : (dy > 0 ? "down" : "up");
    const distance = (previous?.distance || 0) + (moving ? travel : 0);
    this.actorMotion.set(actorId, { x, y, facing, distance });
    return {
      moving,
      facing,
      walkFrame: moving ? Math.floor(this.elapsed * 9 + distance * .18) % 4 : 0,
    };
  }

  updateCamera(state, scene, deltaSeconds = 0) {
    const worldWidth = sceneWidth(scene);
    const worldHeight = sceneHeight(scene);
    const maxX = Math.max(0, worldWidth - WIDTH);
    const maxY = Math.max(0, worldHeight - HEIGHT);
    const changedScene = this.camera.sceneId !== scene.id;
    let focus = null;

    if (state.mode === "observer") {
      const focusedId = state.observer?.focusedNpcId;
      const focused = focusedId ? state.npcs?.[focusedId] : null;
      const focusedPlace = itemPlaceId(focused, focused?.regionId || "");
      if (focused && focused.regionId === state.regionId && focusedPlace === scene.id) focus = focused;
      const cameraX = Number(state.observer?.cameraX ?? state.cameraX);
      const cameraY = Number(state.observer?.cameraY ?? state.cameraY);
      if (!focus && Number.isFinite(cameraX) && Number.isFinite(cameraY)) focus = { x: cameraX, y: cameraY };
      if (!focus && changedScene) focus = scene.camera || scene.spawn || { x: worldWidth / 2, y: worldHeight / 2 };
    } else {
      focus = state.player;
    }

    if (!focus) focus = { x: this.camera.x + WIDTH / 2, y: this.camera.y + HEIGHT / 2 };
    const targetX = clamp(Number(focus.x || 0) - WIDTH / 2, 0, maxX);
    const targetY = clamp(Number(focus.y || 0) - HEIGHT / 2, 0, maxY);
    const ease = changedScene ? 1 : 1 - Math.exp(-CAMERA_EASE * Math.max(0, deltaSeconds));
    this.camera.x += (targetX - this.camera.x) * ease;
    this.camera.y += (targetY - this.camera.y) * ease;
    this.camera.x = clamp(this.camera.x, 0, maxX);
    this.camera.y = clamp(this.camera.y, 0, maxY);
    this.camera.offsetX = Math.max(0, Math.floor((WIDTH - worldWidth) / 2));
    this.camera.offsetY = Math.max(0, Math.floor((HEIGHT - worldHeight) / 2));
    this.camera.sceneId = scene.id;
  }

  worldToScreen(x, y) {
    return {
      x: Number(x) - Math.round(this.camera.x) + this.camera.offsetX,
      y: Number(y) - Math.round(this.camera.y) + this.camera.offsetY,
    };
  }

  screenToWorld(clientX, clientY) {
    const bounds = this.canvas.getBoundingClientRect();
    const screenX = (Number(clientX) - bounds.left) * (this.canvas.width / Math.max(1, bounds.width));
    const screenY = (Number(clientY) - bounds.top) * (this.canvas.height / Math.max(1, bounds.height));
    return {
      x: screenX + Math.round(this.camera.x) - this.camera.offsetX,
      y: screenY + Math.round(this.camera.y) - this.camera.offsetY,
    };
  }

  visibleWorld(scene) {
    return {
      x: Math.round(this.camera.x),
      y: Math.round(this.camera.y),
      w: Math.min(WIDTH, sceneWidth(scene)),
      h: Math.min(HEIGHT, sceneHeight(scene)),
    };
  }

  isVisible(item, visible, padding = CULL_PADDING) {
    return rectIntersects(normalizeRect(item), visible, padding);
  }

  render(state, deltaSeconds = 0) {
    this.elapsed += deltaSeconds;
    const region = this.content.regions.find((item) => item.id === state.regionId) || this.content.regions[0];
    if (!region) return;
    const scene = resolveScene(this.content, state.regionId, scenePlaceId(state)) || region;
    if (this.motionSceneId !== scene.id) {
      this.actorMotion.clear();
      this.motionSceneId = scene.id;
    }
    const ctx = this.context;
    const palette = { ...paletteFor(region), ...(scene.palette || {}) };
    const interior = scene.kind === "interior";
    this.updateCamera(state, scene, deltaSeconds);
    const visible = this.visibleWorld(scene);
    const landmarks = [...(scene.landmarks || []), ...getStoryLandmarks(state, this.content, scene)];
    ctx.clearRect(0, 0, WIDTH, HEIGHT);
    ctx.fillStyle = interior ? "#241d1b" : palette.edge;
    ctx.fillRect(0, 0, WIDTH, HEIGHT);
    ctx.save();
    ctx.translate(this.camera.offsetX - Math.round(this.camera.x), this.camera.offsetY - Math.round(this.camera.y));
    if (interior) this.drawInteriorBase(ctx, scene, palette, visible, state.seed);
    else {
      this.drawGround(ctx, region, palette, state.seed, visible, scene);
      if ((scene.zones || []).length || sceneWidth(scene) > WIDTH || sceneHeight(scene) > HEIGHT) {
        this.drawOutdoorBiome(ctx, region, scene, palette, state.seed, visible);
      } else this.drawBiome(ctx, region, palette, state.seed);
    }
    (scene.zones || []).filter((item) => this.isVisible(item, visible, 24)).forEach((zone) => this.drawZone(ctx, zone, palette, region, scene));
    this.drawPaths(ctx, scene, palette, visible);
    landmarks
      .filter((item) => itemPlaceId(item, scene.id) === scene.id && (item.layer || "ground") === "ground" && this.isVisible(item, visible))
      .forEach((item) => this.drawLandmark(ctx, item, palette));
    (scene.buildings || []).filter((building) => this.isVisible(building, visible)).forEach((building) => this.drawBuilding(ctx, building, palette));
    landmarks
      .filter((item) => itemPlaceId(item, scene.id) === scene.id && (item.layer || "ground") !== "ground" && this.isVisible(item, visible))
      .forEach((item) => this.drawLandmark(ctx, item, palette));
    (scene.portals || []).filter((portal) => !portal.disabled && this.isVisible(portal, visible, 32)).forEach((portal) => this.drawPortal(ctx, portal, palette, interior));

    const actors = [];
    this.content.npcs.forEach((npc) => {
      const npcState = state.npcs[npc.id];
      const npcPlace = itemPlaceId(npcState, itemPlaceId(npc, npcState?.regionId || npc.regionId || npc.region));
      const actorRect = npcState ? { x: npcState.x - 26, y: npcState.y - 72, w: 52, h: 88 } : null;
      if (npcState?.regionId === state.regionId && npcPlace === scene.id && actorRect && rectIntersects(actorRect, visible, 20)) {
        actors.push({ kind: "npc", profile: npc, state: npcState, y: npcState.y });
      }
    });
    if (state.mode !== "observer" && state.player?.present !== false) {
      actors.push({ kind: "player", state: state.player, y: state.player.y });
    }
    (scene.furniture || []).filter((item) => this.isVisible(item, visible)).forEach((item) => {
      const rect = normalizeRect(item);
      actors.push({ kind: "furniture", state: item, y: Number(item.sortY ?? rect.y + rect.h) });
    });
    actors.sort((a, b) => a.y - b.y).forEach((actor) => {
      if (actor.kind === "player") this.drawPlayer(ctx, actor.state);
      else if (actor.kind === "furniture") this.drawFurniture(ctx, actor.state, palette);
      else this.drawNpc(ctx, actor.profile, actor.state, state);
    });
    ctx.restore();

    if (interior) this.drawInteriorLight(ctx, state, scene);
    else {
      this.drawWeather(ctx, state, region, deltaSeconds);
      this.drawDaylight(ctx, state);
    }
    this.drawBorder(ctx, palette);
  }

  drawGround(ctx, region, palette, seed, visible = { x: 0, y: 0, w: WIDTH, h: HEIGHT }, scene = region) {
    ctx.fillStyle = palette.ground;
    ctx.fillRect(0, 0, sceneWidth(scene), sceneHeight(scene));
    const regionSeed = seed ^ hashString(region.id);
    const startX = Math.max(0, Math.floor((visible.x - 12) / 12) * 12);
    const startY = Math.max(0, Math.floor((visible.y - 12) / 12) * 12);
    const endX = Math.min(sceneWidth(scene), Math.ceil((visible.x + visible.w + 12) / 12) * 12);
    const endY = Math.min(sceneHeight(scene), Math.ceil((visible.y + visible.h + 12) / 12) * 12);
    for (let y = startY; y < endY; y += 12) {
      for (let x = startX; x < endX; x += 12) {
        const noise = seededNoise(regionSeed, x / 12, y / 12);
        if (noise > .65) pixelRect(ctx, x, y, 12, 12, palette.groundAlt);

        const px = x + 2 + Math.floor(noise * 7);
        const py = y + 3 + Math.floor((noise * 17) % 6);
        if (region.id === "snow") {
          if (noise > .7) {
            pixelRect(ctx, px, py, 5, 2, "rgba(100,148,160,.18)");
            pixelRect(ctx, px + 3, py - 2, 2, 2, "rgba(255,255,255,.48)");
          }
        } else if (region.id === "desert") {
          if (noise > .55) pixelRect(ctx, px, py, noise > .82 ? 4 : 2, 2, "rgba(122,77,42,.22)");
        } else if (region.id === "capital") {
          if (noise > .7) pixelRect(ctx, px, py, 4, 3, "rgba(63,79,59,.18)");
        } else if (noise > .48) {
          const grass = noise > .78 ? shade(palette.edge, 10) : "rgba(53,91,43,.25)";
          pixelRect(ctx, px + 2, py, 2, 5, grass);
          pixelRect(ctx, px, py + 2, 2, 3, grass);
          if (noise > .86) pixelRect(ctx, px + 4, py + 1, 2, 4, grass);
        }
      }
    }
  }

  drawPaths(ctx, scene, palette, visible = { x: 0, y: 0, w: WIDTH, h: HEIGHT }) {
    const paths = scene.paths?.length ? scene.paths : (scene.kind === "interior" ? [] : this.fallbackPaths(scene.id));
    const visiblePaths = paths.filter((path) => this.isVisible(path, visible, 12));
    visiblePaths.forEach((path, pathIndex) => {
      const rect = normalizeRect(path);
      const styleName = String(path.style || "plain").toLowerCase();
      const style = PATH_STYLES[styleName] || {};
      const pathColor = path.color || style.base || palette.path;
      const edgeColor = style.edge || shade(pathColor, -34);
      const lightColor = style.light || shade(pathColor, 18);
      const pattern = style.pattern || "plain";
      pixelRect(ctx, rect.x - 4, rect.y - 4, rect.w + 8, rect.h + 8, edgeColor);
      pixelRect(ctx, rect.x - 2, rect.y - 2, rect.w + 4, rect.h + 4, shade(pathColor, -15));
      pixelRect(ctx, rect.x, rect.y, rect.w, rect.h, pathColor);

      const horizontal = rect.w > rect.h;
      const long = horizontal ? rect.w : rect.h;
      const short = horizontal ? rect.h : rect.w;

      if (pattern === "royal" || pattern === "marble") {
        const slab = pattern === "royal" ? 22 : 30;
        const band = pattern === "royal" ? 14 : 20;
        for (let across = 5; across < short - 3; across += band) {
          const offset = Math.floor(across / band) % 2 ? slab / 2 : 0;
          for (let step = 3 - offset; step < long - 2; step += slab) {
            const sx = horizontal ? rect.x + step : rect.x + across;
            const sy = horizontal ? rect.y + across : rect.y + step;
            pixelRect(ctx, sx, sy, horizontal ? Math.min(slab - 3, long - step) : 2, horizontal ? 2 : Math.min(slab - 3, long - step), shade(pathColor, -13));
          }
        }
        if (pattern === "royal") {
          for (let step = 12; step < long - 5; step += 36) {
            const sx = horizontal ? rect.x + step : rect.x + short / 2 - 1;
            const sy = horizontal ? rect.y + short / 2 - 1 : rect.y + step;
            pixelRect(ctx, sx, sy, 3, 3, lightColor);
          }
        } else {
          for (let step = 17; step < long - 5; step += 47) {
            const sx = horizontal ? rect.x + step : rect.x + short * .34;
            const sy = horizontal ? rect.y + short * .34 : rect.y + step;
            pixelRect(ctx, sx, sy, horizontal ? 13 : 2, horizontal ? 2 : 13, lightColor);
          }
        }
      } else if (pattern === "cobble" || pattern === "ruin") {
        const rowSize = pattern === "ruin" ? 18 : 12;
        for (let across = 3; across < short - 3; across += rowSize) {
          const row = Math.floor(across / rowSize);
          const stoneSize = pattern === "ruin" ? 25 : 17;
          for (let step = row % 2 ? -6 : 2; step < long - 2; step += stoneSize) {
            const noise = seededNoise(hashString(`${scene.id}-${styleName}-${pathIndex}`), step, across);
            const gap = pattern === "ruin" && noise > .62 ? 7 : 3;
            const sx = horizontal ? rect.x + step : rect.x + across;
            const sy = horizontal ? rect.y + across : rect.y + step;
            pixelRect(ctx, sx, sy, horizontal ? Math.max(3, stoneSize - gap) : 2, horizontal ? 2 : Math.max(3, stoneSize - gap), noise > .72 ? lightColor : shade(pathColor, -18));
            if (pattern === "ruin" && noise > .76) pixelRect(ctx, sx + 4, sy + 3, horizontal ? 2 : 6, horizontal ? 6 : 2, edgeColor);
          }
        }
      } else if (pattern === "snow") {
        for (let step = 12; step < long - 5; step += 24) {
          const side = Math.floor(step / 24) % 2 ? 5 : -6;
          const sx = horizontal ? rect.x + step : rect.x + short / 2 + side;
          const sy = horizontal ? rect.y + short / 2 + side : rect.y + step;
          pixelRect(ctx, sx, sy, 5, 7, shade(pathColor, -18));
          pixelRect(ctx, sx + 2, sy - 3, 3, 3, lightColor);
        }
      } else if (pattern === "ice") {
        for (let step = 13; step < long - 9; step += 34) {
          const cross = 7 + (hashString(`${scene.id}-ice-${pathIndex}-${step}`) % Math.max(5, Math.floor(short - 14)));
          const sx = horizontal ? rect.x + step : rect.x + cross;
          const sy = horizontal ? rect.y + cross : rect.y + step;
          pixelRect(ctx, sx, sy, horizontal ? 11 : 2, horizontal ? 2 : 11, shade(pathColor, -27));
          pixelRect(ctx, sx + (horizontal ? 7 : -4), sy + (horizontal ? 2 : 7), horizontal ? 2 : 6, horizontal ? 6 : 2, lightColor);
        }
      } else {
        const spacing = pattern === "garden" ? 9 : pattern === "sand" ? 18 : 13;
        for (let step = 7; step < long - 3; step += spacing) {
          const noise = seededNoise(hashString(`${scene.id}-${styleName}-${pathIndex}`), step, pathIndex);
          const cross = 5 + Math.floor(noise * Math.max(3, short - 12));
          const sx = horizontal ? rect.x + step : rect.x + cross;
          const sy = horizontal ? rect.y + cross : rect.y + step;
          if (pattern === "farm") {
            pixelRect(ctx, sx, sy, horizontal ? 8 : 2, horizontal ? 2 : 8, noise > .55 ? lightColor : shade(pathColor, -17));
            if (noise > .72) pixelRect(ctx, sx + 3, sy - 3, 2, 3, "#71864b");
          } else if (pattern === "sand") {
            pixelRect(ctx, sx, sy, horizontal ? 12 : 2, horizontal ? 2 : 12, noise > .6 ? lightColor : shade(pathColor, -10));
          } else if (pattern === "garden") {
            pixelRect(ctx, sx, sy, noise > .6 ? 4 : 2, 2, noise > .76 ? lightColor : shade(pathColor, -18));
          } else {
            pixelRect(ctx, sx, sy, noise > .5 ? 7 : 4, 2, noise > .72 ? lightColor : shade(pathColor, -18));
            if (pattern === "dirt" && noise > .74) pixelRect(ctx, sx + 2, sy + 3, 4, 2, shade(pathColor, -8));
          }
        }
      }

      const edgeStep = horizontal ? 18 : 16;
      for (let step = 5; step < long; step += edgeStep) {
        const wobble = (hashString(`${scene.id}-${pathIndex}-${step}`) % 3) * 2;
        if (horizontal) {
          pixelRect(ctx, rect.x + step, rect.y - 2, 7 + wobble, 2, pathColor);
          pixelRect(ctx, rect.x + step + 8, rect.y + rect.h, 6, 2, pathColor);
        } else {
          pixelRect(ctx, rect.x - 2, rect.y + step, 2, 7 + wobble, pathColor);
          pixelRect(ctx, rect.x + rect.w, rect.y + step + 7, 2, 6, pathColor);
        }
      }
    });
  }

  fallbackPaths(regionId) {
    if (regionId === "farm") return [{ x: 0, y: 330, w: WIDTH, h: 55 }, { x: 355, y: 0, w: 58, h: HEIGHT }];
    if (regionId === "mansion") return [{ x: 340, y: 190, w: 88, h: 290 }, { x: 120, y: 330, w: 530, h: 48 }];
    if (regionId === "snow") return [{ x: 0, y: 350, w: WIDTH, h: 54 }, { x: 350, y: 180, w: 62, h: 300 }];
    if (regionId === "desert") return [{ x: 0, y: 330, w: WIDTH, h: 52 }, { x: 370, y: 70, w: 48, h: 350 }];
    return [{ x: 0, y: 315, w: WIDTH, h: 70 }, { x: 340, y: 0, w: 88, h: HEIGHT }];
  }

  drawBiome(ctx, region, palette, seed) {
    switch (region.id) {
      case "farm": this.drawFarm(ctx, palette, seed); break;
      case "mansion": this.drawGarden(ctx, palette, seed); break;
      case "snow": this.drawSnow(ctx, palette, seed); break;
      case "desert": this.drawDesert(ctx, palette, seed); break;
      default: this.drawCapital(ctx, palette, seed); break;
    }
  }

  drawOutdoorBiome(ctx, region, scene, palette, seed, visible) {
    const biome = scene.biome || region.biome || region.id;
    const cell = biome === "desert" ? 72 : 84;
    const startX = Math.max(0, Math.floor((visible.x - cell) / cell) * cell);
    const startY = Math.max(0, Math.floor((visible.y - cell) / cell) * cell);
    const endX = Math.min(sceneWidth(scene), visible.x + visible.w + cell);
    const endY = Math.min(sceneHeight(scene), visible.y + visible.h + cell);
    for (let gridY = startY; gridY < endY; gridY += cell) {
      for (let gridX = startX; gridX < endX; gridX += cell) {
        const hash = hashString(`${seed}:${scene.id}:${gridX}:${gridY}`);
        const x = gridX + 9 + (hash % Math.max(12, cell - 24));
        const y = gridY + 9 + ((hash >>> 8) % Math.max(12, cell - 24));
        if (biome === "capital") {
          pixelRect(ctx, x, y, 7, 3, "rgba(72,82,62,.22)");
          pixelRect(ctx, x + 2, y - 2, 5, 2, "rgba(196,191,145,.18)");
        } else if (biome === "farm") {
          pixelRect(ctx, x + 3, y, 2, 8, "#4f793d");
          pixelRect(ctx, x, y + 4, 4, 2, "#6e9a48");
          pixelRect(ctx, x + 5, y + 2, 5, 2, "#87ac53");
        } else if (biome === "mansion") {
          if (hash % 3 === 0) this.drawFlower(ctx, x, y, hash % 2 ? "#e69aaa" : "#eecb72");
          else pixelRect(ctx, x, y, 5, 2, "rgba(51,91,51,.24)");
        } else if (biome === "snow") {
          pixelRect(ctx, x, y + 2, 9, 2, "rgba(99,151,164,.2)");
          pixelRect(ctx, x + 5, y, 3, 2, "rgba(255,255,255,.62)");
        } else if (biome === "desert") {
          pixelRect(ctx, x, y, 12, 2, "rgba(127,77,40,.2)");
          if (hash % 4 === 0) this.drawRock(ctx, x + 9, y + 8, "#a16d47", 1);
        }
      }
    }
  }

  drawInteriorBase(ctx, scene, palette, visible, seed) {
    const width = sceneWidth(scene);
    const height = sceneHeight(scene);
    const floor = scene.palette?.floor || palette.ground || "#b88a58";
    const floorAlt = scene.palette?.floorAlt || shade(floor, 10);
    pixelRect(ctx, 0, 0, width, height, shade(floor, -18));
    const startX = Math.max(0, Math.floor((visible.x - TILE) / TILE) * TILE);
    const startY = Math.max(0, Math.floor((visible.y - TILE) / TILE) * TILE);
    const endX = Math.min(width, visible.x + visible.w + TILE);
    const endY = Math.min(height, visible.y + visible.h + TILE);
    for (let y = startY; y < endY; y += TILE) {
      for (let x = startX; x < endX; x += TILE) {
        const alternate = ((x / TILE) + (y / TILE)) % 2 === 0;
        pixelRect(ctx, x, y, TILE, TILE, alternate ? floor : floorAlt);
        pixelRect(ctx, x, y + TILE - 2, TILE, 2, shade(floor, -17));
        if (hashString(`${seed}:${scene.id}:${x}:${y}`) % 5 === 0) pixelRect(ctx, x + 5, y + 6, 8, 2, shade(floor, 19));
      }
    }
    const wall = scene.palette?.wall || palette.wall || "#b89465";
    const trim = scene.palette?.trim || shade(wall, -35);
    const wallDepth = Math.min(54, Math.max(28, Number(scene.wallDepth || 42)));
    pixelRect(ctx, 0, 0, width, wallDepth, shade(wall, -18));
    pixelRect(ctx, 5, 5, width - 10, wallDepth - 9, wall);
    for (let x = 9; x < width - 8; x += 28) pixelRect(ctx, x, wallDepth - 13, 18, 2, shade(wall, 18));
    pixelRect(ctx, 0, wallDepth - 5, width, 7, trim);
    pixelRect(ctx, 0, 0, 7, height, trim);
    pixelRect(ctx, width - 7, 0, 7, height, shade(trim, -9));
    pixelRect(ctx, 0, height - 7, width, 7, shade(trim, -18));
  }

  drawZone(ctx, zone, palette, region, scene) {
    const rect = normalizeRect(zone);
    const type = String(zone.type || zone.kind || "ground").toLowerCase();
    const base = zone.color || palette.accent;
    if (type === "plaza" || type === "cobble") {
      pixelRect(ctx, rect.x, rect.y, rect.w, rect.h, type === "plaza" ? "#a8a184" : "#8f927c");
      for (let y = rect.y + 3; y < rect.y + rect.h; y += 12) {
        const offset = ((y - rect.y) / 12) % 2 ? 8 : 0;
        for (let x = rect.x + 3 + offset; x < rect.x + rect.w; x += 18) {
          pixelRect(ctx, x, y, Math.min(14, rect.x + rect.w - x), 2, "rgba(68,67,57,.25)");
          pixelRect(ctx, x, y + 2, 2, 7, "rgba(68,67,57,.18)");
        }
      }
      return;
    }
    if (type === "wall") {
      pixelRect(ctx, rect.x, rect.y, rect.w, rect.h, shade(base || palette.wall, -28));
      pixelRect(ctx, rect.x + 3, rect.y + 3, rect.w - 6, Math.max(3, rect.h - 7), zone.color || "#918873");
      for (let y = rect.y + 7; y < rect.y + rect.h; y += 10) {
        pixelRect(ctx, rect.x + 2, y, rect.w - 4, 2, "#655f55");
        for (let x = rect.x + 8 + ((y / 10) % 2) * 9; x < rect.x + rect.w; x += 20) pixelRect(ctx, x, y - 7, 2, 7, "#70695d");
      }
      return;
    }
    if (type === "crop") {
      const crop = String(zone.crop || zone.variant || "greens").toLowerCase();
      pixelRect(ctx, rect.x, rect.y, rect.w, rect.h, "#91613f");
      for (let y = rect.y + 10; y < rect.y + rect.h - 3; y += 20) {
        pixelRect(ctx, rect.x + 4, y + 7, rect.w - 8, 5, "#624331");
        pixelRect(ctx, rect.x + 4, y + 7, rect.w - 8, 2, "#b47a4c");
        for (let x = rect.x + 12; x < rect.x + rect.w - 5; x += 20) {
          if (crop === "wheat") {
            pixelRect(ctx, x, y - 6, 2, 14, "#6f7d35");
            pixelRect(ctx, x - 3, y - 9, 7, 6, "#c99a3f");
            pixelRect(ctx, x - 1, y - 12, 4, 10, "#e0b753");
            pixelRect(ctx, x - 4, y - 5, 4, 2, "#e7c66b");
            pixelRect(ctx, x + 2, y - 2, 5, 2, "#b88d38");
          } else if (crop === "turnip") {
            pixelRect(ctx, x - 3, y + 1, 8, 7, "#d6c4bb");
            pixelRect(ctx, x - 1, y + 6, 4, 4, "#b8849a");
            pixelRect(ctx, x, y - 6, 2, 8, "#476f3b");
            pixelRect(ctx, x - 6, y - 5, 7, 4, "#75a64c");
            pixelRect(ctx, x + 1, y - 8, 7, 4, "#8aba55");
            pixelRect(ctx, x - 4, y - 9, 5, 3, "#5e8d43");
          } else {
            pixelRect(ctx, x, y - 2, 2, 10, "#466c38");
            pixelRect(ctx, x - 4, y, 6, 3, "#79a344");
            pixelRect(ctx, x + 2, y - 3, 6, 3, "#95b64d");
          }
        }
      }
      return;
    }
    if (type === "orchard") {
      pixelRect(ctx, rect.x, rect.y, rect.w, rect.h, shade(palette.groundAlt, -4));
      for (let y = rect.y + 8; y < rect.y + rect.h - 40; y += 58) {
        for (let x = rect.x + 8; x < rect.x + rect.w - 32; x += 54) this.drawTree(ctx, x, y, palette, (x + y) % 2);
      }
      return;
    }
    if (type === "canal") {
      pixelRect(ctx, rect.x, rect.y, rect.w, rect.h, "#756a58");
      pixelRect(ctx, rect.x + 4, rect.y + 4, rect.w - 8, rect.h - 8, shade(palette.water, -14));
      const horizontal = rect.w >= rect.h;
      const length = horizontal ? rect.w : rect.h;
      for (let step = 12; step < length - 8; step += 28) {
        if (horizontal) pixelRect(ctx, rect.x + step, rect.y + rect.h / 2, 17, 2, shade(palette.water, 32));
        else pixelRect(ctx, rect.x + rect.w / 2, rect.y + step, 2, 17, shade(palette.water, 32));
      }
      return;
    }
    if (type === "paddock") {
      pixelRect(ctx, rect.x, rect.y, rect.w, rect.h, shade(palette.groundAlt, 3));
      this.drawFenceRect(ctx, rect, zone.color || "#9a683f");
      return;
    }
    if (type === "hedge") {
      pixelRect(ctx, rect.x, rect.y + 5, rect.w, Math.max(4, rect.h - 5), shade(palette.edge, -10));
      for (let x = rect.x; x < rect.x + rect.w; x += 12) {
        pixelRect(ctx, x, rect.y + ((x / 12) % 2) * 2, Math.min(14, rect.x + rect.w - x), Math.min(13, rect.h), shade(palette.edge, 12));
        pixelRect(ctx, x + 3, rect.y + 3, 5, 3, shade(palette.groundAlt, -8));
      }
      return;
    }
    if (type === "flowerbed") {
      pixelRect(ctx, rect.x, rect.y, rect.w, rect.h, "#704e3c");
      for (let y = rect.y + 5; y < rect.y + rect.h - 7; y += 14) {
        for (let x = rect.x + 6; x < rect.x + rect.w - 6; x += 14) this.drawFlower(ctx, x, y, (x + y) % 3 ? "#e995aa" : "#f0c66a");
      }
      return;
    }
    if (type === "pond" || type === "oasis") {
      this.drawLandmark(ctx, { ...zone, type }, palette);
      return;
    }
    if (type === "cliff") {
      pixelRect(ctx, rect.x, rect.y, rect.w, rect.h, "#69797b");
      pixelRect(ctx, rect.x, rect.y, rect.w, 8, "#a9bab5");
      for (let x = rect.x + 9; x < rect.x + rect.w; x += 25) {
        const drop = 8 + (hashString(`${scene.id}:${x}:${rect.y}`) % Math.max(9, rect.h - 8));
        pixelRect(ctx, x, rect.y + 9, 3, drop, "#53686d");
        pixelRect(ctx, x + 3, rect.y + 11, 5, 2, "#879597");
      }
      return;
    }
    if (type === "ice") {
      pixelRect(ctx, rect.x, rect.y, rect.w, rect.h, zone.color || "#9bcbd0");
      for (let x = rect.x + 11; x < rect.x + rect.w - 5; x += 31) {
        pixelRect(ctx, x, rect.y + 8 + (x % 13), 3, Math.min(18, rect.h - 10), "#72aeb8");
        pixelRect(ctx, x + 3, rect.y + 13 + (x % 13), 8, 2, "#d4ecdf");
      }
      return;
    }
    if (type === "dune") {
      pixelRect(ctx, rect.x, rect.y, rect.w, rect.h, zone.color || "#ddb06a");
      for (let y = rect.y + 12; y < rect.y + rect.h; y += 24) {
        for (let x = rect.x; x < rect.x + rect.w; x += 12) {
          const rise = Math.round(Math.sin((x + y) / 34) * 4);
          pixelRect(ctx, x, y + rise, Math.min(13, rect.x + rect.w - x), 2, "rgba(135,82,43,.22)");
        }
      }
      return;
    }
    if (type === "mesa") {
      pixelRect(ctx, rect.x + 5, rect.y, rect.w - 10, rect.h, "#a86645");
      pixelRect(ctx, rect.x, rect.y + 8, rect.w, rect.h - 8, "#91563f");
      pixelRect(ctx, rect.x + 4, rect.y + 8, rect.w - 8, 5, "#c68150");
      for (let y = rect.y + 22; y < rect.y + rect.h; y += 17) pixelRect(ctx, rect.x + 7, y, rect.w - 14, 3, "rgba(96,52,42,.27)");
      return;
    }
    if (type === "rug") {
      const rug = zone.color || "#9b4f4b";
      pixelRect(ctx, rect.x, rect.y, rect.w, rect.h, shade(rug, -35));
      pixelRect(ctx, rect.x + 3, rect.y + 3, rect.w - 6, rect.h - 6, rug);
      pixelRect(ctx, rect.x + 8, rect.y + 8, rect.w - 16, rect.h - 16, shade(rug, 24));
      for (let x = rect.x + 5; x < rect.x + rect.w - 3; x += 8) {
        pixelRect(ctx, x, rect.y - 3, 2, 5, shade(rug, 22));
        pixelRect(ctx, x, rect.y + rect.h - 2, 2, 5, shade(rug, 22));
      }
      return;
    }
    pixelRect(ctx, rect.x, rect.y, rect.w, rect.h, base || shade(palette.groundAlt, -5));
    pixelRect(ctx, rect.x + 3, rect.y + 3, Math.max(2, rect.w - 6), 3, shade(base || palette.groundAlt, 18));
  }

  drawFenceRect(ctx, rect, color) {
    const dark = shade(color, -28);
    for (let x = rect.x; x <= rect.x + rect.w - 4; x += 24) {
      pixelRect(ctx, x, rect.y - 3, 4, 10, dark);
      pixelRect(ctx, x, rect.y + rect.h - 7, 4, 10, dark);
    }
    for (let y = rect.y; y <= rect.y + rect.h - 4; y += 24) {
      pixelRect(ctx, rect.x - 3, y, 10, 4, dark);
      pixelRect(ctx, rect.x + rect.w - 7, y, 10, 4, dark);
    }
    pixelRect(ctx, rect.x, rect.y, rect.w, 3, color);
    pixelRect(ctx, rect.x, rect.y + rect.h - 3, rect.w, 3, color);
    pixelRect(ctx, rect.x, rect.y, 3, rect.h, color);
    pixelRect(ctx, rect.x + rect.w - 3, rect.y, 3, rect.h, color);
  }

  drawTree(ctx, x, y, palette, variant = 0, snow = false) {
    const leafDark = snow ? "#3f6664" : shade(palette.edge, 1 + variant * 5);
    const leaf = snow ? "#4f7b70" : shade(palette.edge, 18 + variant * 4);
    const leafLight = snow ? "#6f9384" : shade(palette.groundAlt, -15);
    pixelRect(ctx, x + 10, y + 27, 7, 17, "#5d4434");
    pixelRect(ctx, x + 12, y + 27, 3, 17, "#8a6342");
    pixelRect(ctx, x + 3, y + 9, 24, 22, leafDark);
    pixelRect(ctx, x, y + 15, 30, 13, leafDark);
    pixelRect(ctx, x + 7, y + 3, 17, 25, leaf);
    pixelRect(ctx, x + 4, y + 11, 22, 13, leaf);
    pixelRect(ctx, x + 8, y + 7, 8, 5, leafLight);
    pixelRect(ctx, x + 3, y + 17, 5, 4, leafLight);
    pixelRect(ctx, x + 22, y + 14, 4, 5, shade(leaf, -12));
    if (snow) {
      pixelRect(ctx, x + 7, y + 2, 17, 4, "#eef4ed");
      pixelRect(ctx, x + 2, y + 13, 10, 3, "#e6f0eb");
      pixelRect(ctx, x + 17, y + 10, 9, 3, "#f4f7f1");
    }
  }

  drawPine(ctx, x, y, snow = false) {
    pixelRect(ctx, x + 11, y + 30, 6, 17, "#654939");
    pixelRect(ctx, x + 4, y + 22, 21, 12, "#315b55");
    pixelRect(ctx, x + 1, y + 28, 27, 10, "#315b55");
    pixelRect(ctx, x + 7, y + 12, 15, 14, "#3d6a60");
    pixelRect(ctx, x + 10, y + 3, 9, 14, "#4a7568");
    if (snow) {
      pixelRect(ctx, x + 9, y + 4, 10, 3, "#f5f7f0");
      pixelRect(ctx, x + 5, y + 15, 17, 3, "#e9f0ec");
      pixelRect(ctx, x + 1, y + 29, 15, 3, "#f8faf5");
    }
  }

  drawRock(ctx, x, y, color = "#7b776c", size = 1) {
    pixelRect(ctx, x + 2 * size, y, 8 * size, 2 * size, shade(color, 18));
    pixelRect(ctx, x, y + 2 * size, 13 * size, 6 * size, color);
    pixelRect(ctx, x + 2 * size, y + 8 * size, 10 * size, 2 * size, shade(color, -25));
    pixelRect(ctx, x + 2 * size, y + 2 * size, 3 * size, 2 * size, shade(color, 30));
  }

  drawFlower(ctx, x, y, color) {
    pixelRect(ctx, x + 2, y + 5, 2, 5, "#467044");
    pixelRect(ctx, x, y + 1, 3, 3, color);
    pixelRect(ctx, x + 4, y, 3, 3, shade(color, 18));
    pixelRect(ctx, x + 3, y + 3, 3, 3, "#f3cb65");
  }

  drawCapital(ctx, palette, seed) {
    const trees = [[20,20],[212,28],[520,34],[720,26],[18,195],[720,200],[102,245],[622,236]];
    trees.forEach(([x, y], index) => this.drawTree(ctx, x, y, palette, index % 2));
    for (let index = 0; index < 24; index += 1) {
      const x = 18 + (hashString(`${seed}-capital-flower-x-${index}`) % 720);
      const y = 150 + (hashString(`${seed}-capital-flower-y-${index}`) % 276);
      if (x > 305 && x < 455) continue;
      this.drawFlower(ctx, x, y, index % 3 === 0 ? "#f0c36e" : "#d9909c");
    }
    // Low clipped-stone wall makes the royal district feel inhabited without changing collision.
    for (let x = 16; x < 250; x += 24) {
      pixelRect(ctx, x, 210, 22, 7, "#8d8d78");
      pixelRect(ctx, x + 2, 210, 18, 2, "#b0aa8e");
    }
  }

  drawFarm(ctx, palette, seed) {
    const plots = [{ x: 42, y: 70, w: 260, h: 190 }, { x: 470, y: 80, w: 250, h: 180 }];
    plots.forEach((plot, plotIndex) => {
      pixelRect(ctx, plot.x - 4, plot.y - 4, plot.w + 8, plot.h + 8, "#80583b");
      pixelRect(ctx, plot.x, plot.y, plot.w, plot.h, "#93623f");
      for (let y = plot.y + 11; y < plot.y + plot.h - 6; y += 22) {
        pixelRect(ctx, plot.x + 5, y + 3, plot.w - 10, 6, "#654532");
        pixelRect(ctx, plot.x + 6, y, plot.w - 12, 3, "#ad774a");
        for (let x = plot.x + 13 + (plotIndex * 5); x < plot.x + plot.w - 8; x += 25) {
          const mature = hashString(`${seed}-${x}-${y}`) % 3;
          pixelRect(ctx, x + 2, y - 4 - mature, 2, 9 + mature, "#456d38");
          pixelRect(ctx, x - 2, y - 2 - mature, 6, 3, mature === 2 ? "#9aba45" : "#72a044");
          pixelRect(ctx, x + 3, y - 5, 6, 3, mature === 2 ? "#d9b546" : "#82aa43");
          if (mature === 2) pixelRect(ctx, x + 2, y - 9, 3, 3, "#e6ce65");
        }
      }
    });
    // Uneven split-rail fence, plus hay bales and a tiny scarecrow silhouette.
    for (let x = 25; x < 300; x += 28) {
      pixelRect(ctx, x, 278, 4, 16, "#81583a");
      pixelRect(ctx, x + 2, 281, 28, 4, "#b37a48");
      pixelRect(ctx, x + 2, 288, 28, 3, "#98623d");
    }
    pixelRect(ctx, 675, 282, 35, 17, "#d5aa42");
    pixelRect(ctx, 679, 285, 27, 3, "#f1ca5c");
    pixelRect(ctx, 691, 268, 4, 26, "#654735");
    pixelRect(ctx, 680, 272, 26, 4, "#80603c");
    pixelRect(ctx, 686, 260, 14, 12, "#b57243");
    pixelRect(ctx, 684, 258, 18, 4, "#d7a148");
  }

  drawGarden(ctx, palette, seed) {
    [[88,196,144],[582,196,108],[230,188,84],[456,188,84]].forEach(([x, y, w], hedgeIndex) => {
      pixelRect(ctx, x, y + 7, w, 11, shade(palette.edge, -8));
      for (let xx = x; xx < x + w; xx += 12) {
        pixelRect(ctx, xx, y + ((xx / 12 + hedgeIndex) % 2) * 2, 14, 12, shade(palette.edge, 12));
        pixelRect(ctx, xx + 3, y + 2, 5, 3, shade(palette.groundAlt, -8));
      }
    });
    const beds = [[65,220,170,28],[535,220,170,28],[60,342,190,30],[520,342,190,30]];
    beds.forEach(([x, y, w], bedIndex) => {
      pixelRect(ctx, x, y, w, 28, "#6f4d3c");
      for (let flowerX = x + 8; flowerX < x + w - 4; flowerX += 14) {
        const color = (flowerX + bedIndex) % 3 === 0 ? "#f1c66d" : bedIndex % 2 ? "#e895ab" : "#a9b6e6";
        this.drawFlower(ctx, flowerX, y + 9 + (hashString(`${seed}-${flowerX}`) % 4), color);
      }
    });
    this.drawTree(ctx, 18, 82, palette, 1);
    this.drawTree(ctx, 715, 86, palette, 0);
  }

  drawSnow(ctx, palette, seed) {
    [[18,112],[242,54],[526,136],[714,158],[28,284],[660,308]].forEach(([x, y]) => this.drawPine(ctx, x, y, true));
    for (let index = 0; index < 14; index += 1) {
      const x = 18 + (hashString(`${seed}-snow-rock-x-${index}`) % 710);
      const y = 170 + (hashString(`${seed}-snow-rock-y-${index}`) % 245);
      this.drawRock(ctx, x, y, "#789095", index % 5 === 0 ? 2 : 1);
      pixelRect(ctx, x + 2, y - 1, index % 5 === 0 ? 18 : 9, 3, "#eef3ef");
    }
    // Curved blue ice scar across the upper slope.
    for (let step = 0; step < 190; step += 8) {
      const x = 275 + step;
      const y = 155 - Math.floor(Math.sin(step / 36) * 12);
      pixelRect(ctx, x, y, 10, 3, step % 24 ? "#91c7d0" : "#c2e4e4");
    }
  }

  drawDesert(ctx, palette, seed) {
    for (let y = 138; y < HEIGHT; y += 84) {
      for (let x = -20; x < WIDTH; x += 18) {
        const rise = Math.round(Math.sin((x + y) / 58) * 7);
        pixelRect(ctx, x, y + rise, 20, 2, "rgba(126,77,42,.2)");
        if ((x / 18) % 3 === 0) pixelRect(ctx, x + 7, y + rise - 2, 9, 2, "rgba(246,198,111,.22)");
      }
    }
    [[250,156],[510,232],[62,403],[690,392]].forEach(([x, y], index) => {
      this.drawRock(ctx, x, y, index % 2 ? "#9e6845" : "#85604b", index === 1 ? 2 : 1);
    });
    [[92,126],[668,207],[130,414],[520,360]].forEach(([x, y], index) => {
      const cactus = index % 2 ? "#477a5c" : "#4d8862";
      pixelRect(ctx, x, y - 20, 7, 28, shade(cactus, -15));
      pixelRect(ctx, x + 2, y - 22, 4, 30, cactus);
      pixelRect(ctx, x - 8, y - 13, 10, 5, cactus);
      pixelRect(ctx, x - 8, y - 19, 4, 10, cactus);
      pixelRect(ctx, x + 6, y - 8, 10, 5, shade(cactus, -5));
      pixelRect(ctx, x + 12, y - 14, 4, 9, cactus);
      if (index === 0) pixelRect(ctx, x + 2, y - 25, 5, 4, "#df7d77");
    });
    for (let index = 0; index < 12; index += 1) {
      const x = hashString(`${seed}-desert-tuft-x-${index}`) % 730;
      const y = 130 + (hashString(`${seed}-desert-tuft-y-${index}`) % 320);
      pixelRect(ctx, x, y, 2, 8, "#987b43");
      pixelRect(ctx, x - 4, y + 3, 5, 2, "#987b43");
      pixelRect(ctx, x + 2, y + 1, 5, 2, "#b3934d");
    }
  }

  drawBuilding(ctx, building, palette) {
    const { x, y, w, h } = normalizeRect(building);
    const roofHeight = Math.max(18, Math.floor(h * .38));
    const wall = building.wallColor || palette.wall;
    const roof = building.roofColor || palette.roof;
    const id = building.id || "";

    if (/tent/.test(id)) {
      pixelRect(ctx, x + 7, y + h - 9, w, 9, "rgba(55,35,30,.26)");
      ctx.fillStyle = shade(roof, -30);
      ctx.beginPath();
      ctx.moveTo(x + w / 2, y - 3);
      ctx.lineTo(x + w + 7, y + h);
      ctx.lineTo(x - 7, y + h);
      ctx.closePath();
      ctx.fill();
      ctx.fillStyle = roof;
      ctx.beginPath();
      ctx.moveTo(x + w / 2, y + 2);
      ctx.lineTo(x + w - 1, y + h - 3);
      ctx.lineTo(x + 1, y + h - 3);
      ctx.closePath();
      ctx.fill();
      drawPixelLine(ctx, x + w / 2, y + 3, h - 5, shade(roof, 25), true);
      pixelRect(ctx, x + w / 2 - 12, y + h - 34, 24, 31, "#493c3b");
      pixelRect(ctx, x + w / 2 - 8, y + h - 29, 8, 26, shade(roof, -22));
      this.drawBuildingLabel(ctx, building, x, y, w, h);
      return;
    }

    pixelRect(ctx, x + 8, y + 12, w, h, "rgba(43,30,31,.28)");
    pixelRect(ctx, x - 2, y + roofHeight - 5, w + 4, h - roofHeight + 7, shade(wall, -32));
    pixelRect(ctx, x + 2, y + roofHeight - 2, w - 4, h - roofHeight, wall);
    // Stucco and timber texture keep the large facades from reading as flat vector blocks.
    for (let yy = y + roofHeight + 7; yy < y + h - 7; yy += 12) {
      const offset = ((yy - y) / 12) % 2 ? 7 : 0;
      for (let xx = x + 6 + offset; xx < x + w - 7; xx += 20) {
        pixelRect(ctx, xx, yy, Math.min(9, x + w - xx - 4), 2, shade(wall, yy % 3 ? -8 : 12));
      }
    }

    ctx.fillStyle = shade(roof, -38);
    ctx.beginPath();
    ctx.moveTo(x - 10, y + roofHeight + 3);
    ctx.lineTo(x + w / 2, y - 4);
    ctx.lineTo(x + w + 10, y + roofHeight + 3);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = roof;
    ctx.beginPath();
    ctx.moveTo(x - 6, y + roofHeight);
    ctx.lineTo(x + w / 2, y);
    ctx.lineTo(x + w + 6, y + roofHeight);
    ctx.closePath();
    ctx.fill();
    for (let row = 8; row < roofHeight - 3; row += 8) {
      const inset = Math.floor((roofHeight - row) * (w / 2) / roofHeight);
      const start = x + w / 2 - (w / 2 - inset) + 3;
      const end = x + w / 2 + (w / 2 - inset) - 3;
      if (end > start) {
        drawPixelLine(ctx, start, y + row, end - start, shade(roof, row % 16 ? 16 : -13));
        for (let shingle = start + 10; shingle < end; shingle += 18) pixelRect(ctx, shingle, y + row, 2, 4, shade(roof, -18));
      }
    }
    pixelRect(ctx, x - 8, y + roofHeight - 2, w + 16, 5, shade(roof, -22));
    pixelRect(ctx, x - 5, y + roofHeight - 2, w + 10, 2, shade(roof, 22));

    if (hashString(id) % 2 === 0 && w > 120) {
      pixelRect(ctx, x + 19, y + 7, 16, Math.max(14, roofHeight - 8), shade(wall, -28));
      pixelRect(ctx, x + 16, y + 5, 22, 6, shade(roof, -18));
      pixelRect(ctx, x + 19, y + 5, 16, 2, shade(roof, 24));
    }

    const doorW = Math.min(22, Math.max(14, w * .18));
    pixelRect(ctx, x + w / 2 - doorW / 2 - 2, y + h - 34, doorW + 4, 34, shade(roof, -42));
    pixelRect(ctx, x + w / 2 - doorW / 2, y + h - 31, doorW, 31, "#664337");
    pixelRect(ctx, x + w / 2 - doorW / 2 + 3, y + h - 28, doorW - 6, 3, "#815943");
    pixelRect(ctx, x + w / 2 + doorW / 4, y + h - 16, 3, 3, "#e5ba5c");
    const windowY = y + roofHeight + 14;
    if (w > 75) {
      this.drawWindow(ctx, x + 13, windowY, /studio/.test(id));
      this.drawWindow(ctx, x + w - 31, windowY, /studio/.test(id));
    }

    if (/palace|white_thorn/.test(id)) {
      const banner = /palace/.test(id) ? "#b45757" : "#7e547f";
      pixelRect(ctx, x + w / 2 - 34, y + roofHeight + 9, 12, 30, shade(banner, -22));
      pixelRect(ctx, x + w / 2 - 32, y + roofHeight + 9, 8, 25, banner);
      pixelRect(ctx, x + w / 2 + 22, y + roofHeight + 9, 12, 30, shade(banner, -22));
      pixelRect(ctx, x + w / 2 + 24, y + roofHeight + 9, 8, 25, banner);
    }
    if (/mill/.test(id)) this.drawMillWheel(ctx, x + w - 21, y + roofHeight + 5);
    if (/studio/.test(id)) {
      for (let glassX = x + 37; glassX < x + w - 37; glassX += 22) this.drawWindow(ctx, glassX, windowY - 5, true);
    }
    if (/apiary/.test(id)) {
      pixelRect(ctx, x + 10, y + h - 18, 13, 12, "#d1a140");
      pixelRect(ctx, x + 12, y + h - 21, 9, 3, "#f0c85e");
    }
    if (/watchtower/.test(id)) {
      for (let battlement = x + 6; battlement < x + w - 6; battlement += 22) pixelRect(ctx, battlement, y + roofHeight - 7, 11, 8, shade(wall, -25));
    }
    this.drawBuildingLabel(ctx, building, x, y, w, h);
  }

  drawWindow(ctx, x, y, tall = false) {
    const h = tall ? 19 : 15;
    pixelRect(ctx, x - 2, y - 2, 22, h + 4, "#664d43");
    pixelRect(ctx, x, y, 18, h, "#78afb1");
    pixelRect(ctx, x + 2, y + 2, 7, 4, "#b9d7c7");
    pixelRect(ctx, x + 8, y, 2, h, "#5d7778");
    pixelRect(ctx, x, y + Math.floor(h / 2), 18, 2, "#5d7778");
    pixelRect(ctx, x - 3, y + h, 24, 3, "#8c654c");
  }

  drawMillWheel(ctx, x, y) {
    pixelRect(ctx, x - 2, y + 15, 4, 44, "#64483b");
    pixelRect(ctx, x - 22, y + 35, 44, 4, "#64483b");
    for (let offset = -20; offset <= 20; offset += 40) {
      pixelRect(ctx, x + offset - 3, y + 31, 7, 12, "#c8a15d");
      pixelRect(ctx, x - 5, y + 15 + offset, 10, 9, "#c8a15d");
    }
    pixelRect(ctx, x - 6, y + 31, 12, 12, "#8e6743");
    pixelRect(ctx, x - 2, y + 35, 4, 4, "#d6b36a");
  }

  drawBuildingLabel(ctx, building, x, y, w, h) {
    if (!building.label) return;
    ctx.font = 'bold 10px "Microsoft YaHei", sans-serif';
    ctx.textAlign = "center";
    const labelWidth = Math.min(w - 8, Math.max(52, building.label.length * 11 + 12));
    const left = x + w / 2 - labelWidth / 2;
    pixelRect(ctx, left - 2, y + h + 3, labelWidth + 4, 17, "#5f4939");
    pixelRect(ctx, left, y + h + 5, labelWidth, 13, "#e1c589");
    pixelRect(ctx, left + 3, y + h + 6, labelWidth - 6, 2, "#f0d9a2");
    ctx.fillStyle = "#523e34";
    ctx.fillText(building.label, x + w / 2, y + h + 16);
  }

  drawPortal(ctx, portal, palette, interior = false) {
    const { x, y, w, h } = pointRect(portal, 24);
    const type = String(portal.type || portal.kind || "door").toLowerCase();
    const glow = portal.color || (interior ? "#efc66c" : palette.accent);
    const pulse = Math.sin(this.elapsed * 3 + hashString(portal.id || `${x}:${y}`)) > 0 ? 1 : 0;
    const cx = x + w / 2;
    const cy = y + h / 2;
    if (/cave|tunnel/.test(type)) {
      const caveW = Math.min(52, Math.max(26, w * .62));
      const caveH = Math.min(42, Math.max(22, h * .62));
      const caveX = cx - caveW / 2;
      const caveY = cy - caveH / 2;
      pixelRect(ctx, caveX, caveY + 8, caveW, Math.max(8, caveH - 8), "#37343a");
      pixelRect(ctx, caveX + 4, caveY + 3, Math.max(4, caveW - 8), 7, "#625d57");
      pixelRect(ctx, caveX + 5, caveY + 10, Math.max(4, caveW - 10), Math.max(5, caveH - 12), "#211f27");
    } else if (/stair|steps/.test(type)) {
      for (let step = 0; step < 4; step += 1) {
        const inset = step * 3;
        const stairW = Math.min(48, Math.max(24, w * .56));
        const stairH = Math.min(32, Math.max(16, h * .5));
        pixelRect(ctx, cx - stairW / 2 + inset, cy - stairH / 2 + step * Math.max(3, stairH / 5), Math.max(3, stairW - inset * 2), Math.max(3, stairH / 5), shade(palette.path, step * 8 - 20));
      }
    } else if (type === "road" || type === "trail") {
      const vertical = h > w;
      const span = Math.max(18, Math.min(vertical ? h : w, 52));
      for (let step = -1; step <= 1; step += 1) {
        const along = step * span * .28;
        const side = step % 2 ? -4 : 4;
        const px = vertical ? cx + side : cx + along;
        const py = vertical ? cy + along : cy + side;
        if (type === "road") {
          pixelRect(ctx, px - 8, py - 4, 16, 8, shade(palette.path, -22));
          pixelRect(ctx, px - 6, py - 3, 12, 5, step === 0 ? shade(palette.path, 18) : palette.path);
          pixelRect(ctx, px - 4, py - 2, 5, 2, shade(palette.path, 32));
        } else {
          pixelRect(ctx, px - 3, py - 4, 5, 7, "rgba(78,61,49,.58)");
          pixelRect(ctx, px + 1, py - 6, 3, 3, "rgba(78,61,49,.5)");
          pixelRect(ctx, px - 7, py + 3, 4, 3, shade(palette.edge, 12));
        }
      }
      const postX = vertical ? cx + 13 : cx - span * .43;
      const postY = vertical ? cy - span * .43 : cy - 15;
      pixelRect(ctx, postX, postY, 3, 17, "#694a35");
      pixelRect(ctx, postX - 5, postY, 15, 7, "#9b6c43");
      pixelRect(ctx, postX - 3, postY + 2, 10, 2, "#d0a567");
    } else if (type === "carriage" || type === "caravan") {
      const wagonW = Math.min(58, Math.max(36, w * .58));
      const wagonH = Math.min(38, Math.max(25, h * .46));
      const wagonX = cx - wagonW / 2;
      const wagonY = cy - wagonH / 2;
      pixelRect(ctx, wagonX + 5, wagonY + wagonH - 13, wagonW - 10, 12, "#604331");
      pixelRect(ctx, wagonX + 8, wagonY + wagonH - 20, wagonW - 16, 13, type === "caravan" ? "#b85f45" : "#755064");
      pixelRect(ctx, wagonX + 11, wagonY + wagonH - 18, wagonW - 22, 3, type === "caravan" ? "#e0ad69" : "#c69a77");
      if (type === "caravan") {
        pixelRect(ctx, wagonX + 12, wagonY + 2, 3, 14, "#76503a");
        pixelRect(ctx, wagonX + wagonW - 15, wagonY + 2, 3, 14, "#76503a");
        pixelRect(ctx, wagonX + 10, wagonY, wagonW - 20, 7, "#d78655");
        pixelRect(ctx, wagonX + 15, wagonY + 7, wagonW - 30, 3, "#f0c17a");
      } else {
        pixelRect(ctx, wagonX + 12, wagonY + 3, wagonW - 24, 14, "#4e3e52");
        pixelRect(ctx, wagonX + 16, wagonY + 6, wagonW - 32, 6, "#9c8798");
      }
      for (const wheelX of [wagonX + 10, wagonX + wagonW - 15]) {
        pixelRect(ctx, wheelX, wagonY + wagonH - 8, 10, 10, "#3e3431");
        pixelRect(ctx, wheelX + 3, wagonY + wagonH - 5, 4, 4, "#b48a55");
      }
    } else if (type === "lift") {
      const liftW = Math.min(56, Math.max(34, w * .55));
      const liftH = Math.min(50, Math.max(30, h * .54));
      const liftX = cx - liftW / 2;
      const liftY = cy - liftH / 2;
      pixelRect(ctx, liftX + 5, liftY, 3, liftH - 8, "#51463d");
      pixelRect(ctx, liftX + liftW - 8, liftY, 3, liftH - 8, "#51463d");
      pixelRect(ctx, liftX + 2, liftY + liftH - 12, liftW - 4, 10, "#66513c");
      pixelRect(ctx, liftX + 6, liftY + liftH - 10, liftW - 12, 5, "#b28b57");
      pixelRect(ctx, liftX + 8, liftY + 8, liftW - 16, 3, "#777069");
      pixelRect(ctx, cx - 8, liftY + 3, 16, 16, "#5b4e43");
      pixelRect(ctx, cx - 3, liftY + 8, 6, 6, "#c49a5d");
      pixelRect(ctx, cx - 1, y, 2, Math.max(4, liftY - y + 4), "#5b5550");
    } else if (type === "door") {
      const doorW = Math.min(interior ? 30 : 26, Math.max(18, w * .55));
      const doorH = Math.min(interior ? 26 : 32, Math.max(18, h * .8));
      const doorX = cx - doorW / 2;
      const doorY = y + h - doorH;
      pixelRect(ctx, doorX - 3, doorY - 3, doorW + 6, doorH + 3, "#4b342f");
      pixelRect(ctx, doorX, doorY, doorW, doorH, interior ? "#755039" : shade(palette.roof, -25));
      pixelRect(ctx, doorX + 3, doorY + 3, Math.max(3, doorW - 6), Math.max(4, doorH - 5), interior ? "#936746" : shade(palette.roof, 10));
      pixelRect(ctx, doorX + doorW - 7, doorY + doorH / 2, 3, 3, "#efd174");
      if (interior) pixelRect(ctx, cx - 18, y + h - 3, 36, 3, shade(palette.path, -20));
    } else {
      pixelRect(ctx, cx - 8, cy - 8, 16, 16, shade(glow, -28));
      pixelRect(ctx, cx - 5, cy - 5, 10, 10, glow);
      pixelRect(ctx, cx - 2, cy - 10, 4, 20, shade(glow, 28));
    }
    const hintW = Math.min(28, Math.max(12, w * .28));
    const hintY = Math.min(y + h - 3, cy + Math.min(24, h * .35));
    pixelRect(ctx, cx - hintW / 2, hintY, hintW, 2 + pulse, shade(glow, -8));
    pixelRect(ctx, cx - 2, hintY - 3 - pulse, 4, 2, shade(glow, 28));
  }

  drawFurniture(ctx, item, palette) {
    const { x, y, w, h } = normalizeRect(item);
    const type = String(item.type || item.kind || "furniture").toLowerCase();
    const wood = item.color || "#875c3c";
    const dark = shade(wood, -35);
    const light = shade(wood, 24);
    if (type === "bed") {
      pixelRect(ctx, x + 4, y + 6, w, h, "rgba(48,30,28,.22)");
      pixelRect(ctx, x, y, w, h, dark);
      pixelRect(ctx, x + 3, y + 3, w - 6, h - 6, item.fabricColor || "#9d655c");
      pixelRect(ctx, x + 5, y + 5, Math.max(8, w - 10), Math.min(12, h / 3), "#ead6aa");
      pixelRect(ctx, x + 5, y + Math.min(18, h / 2), w - 10, 3, shade(item.fabricColor || "#9d655c", 24));
      return;
    }
    if (type === "table" || type === "desk") {
      pixelRect(ctx, x + 4, y + 7, w, Math.max(5, h - 5), "rgba(49,31,27,.22)");
      pixelRect(ctx, x, y, w, Math.max(8, h * .55), dark);
      pixelRect(ctx, x + 2, y + 2, w - 4, Math.max(5, h * .42), wood);
      pixelRect(ctx, x + 4, y + 3, w - 8, 3, light);
      pixelRect(ctx, x + 4, y + h * .48, 5, Math.max(6, h * .45), dark);
      pixelRect(ctx, x + w - 9, y + h * .48, 5, Math.max(6, h * .45), dark);
      if (type === "desk") {
        pixelRect(ctx, x + w * .2, y - 3, Math.max(8, w * .42), 5, "#e2c987");
        pixelRect(ctx, x + w * .22, y - 4, Math.max(5, w * .18), 2, "#fff0b0");
      }
      return;
    }
    if (type === "chair") {
      pixelRect(ctx, x + 3, y, Math.max(5, w - 6), Math.max(8, h * .62), dark);
      pixelRect(ctx, x + 5, y + 3, Math.max(3, w - 10), Math.max(5, h * .4), wood);
      pixelRect(ctx, x + 2, y + h * .5, w - 4, Math.max(5, h * .28), light);
      pixelRect(ctx, x + 3, y + h * .72, 4, Math.max(4, h * .28), dark);
      pixelRect(ctx, x + w - 7, y + h * .72, 4, Math.max(4, h * .28), dark);
      return;
    }
    if (type === "shelf") {
      pixelRect(ctx, x + 4, y + 5, w, h, "rgba(47,29,26,.22)");
      pixelRect(ctx, x, y, w, h, dark);
      pixelRect(ctx, x + 4, y + 4, w - 8, h - 8, "#5f4936");
      for (let shelfY = y + 10; shelfY < y + h - 5; shelfY += 14) {
        pixelRect(ctx, x + 3, shelfY, w - 6, 4, wood);
        for (let bookX = x + 7; bookX < x + w - 7; bookX += 7) pixelRect(ctx, bookX, shelfY - 8, 4, 8, (bookX / 7) % 2 ? "#9d5d52" : "#718072");
      }
      return;
    }
    if (type === "counter") {
      pixelRect(ctx, x + 4, y + 6, w, h, "rgba(45,29,26,.24)");
      pixelRect(ctx, x, y + 5, w, h - 5, dark);
      pixelRect(ctx, x + 3, y + 8, w - 6, h - 11, wood);
      pixelRect(ctx, x - 2, y, w + 4, 8, light);
      for (let panelX = x + 10; panelX < x + w - 7; panelX += 24) pixelRect(ctx, panelX, y + 12, 3, h - 16, shade(wood, -17));
      return;
    }
    if (type === "throne") {
      pixelRect(ctx, x + 3, y, w - 6, h, "#694447");
      pixelRect(ctx, x, y + 5, 6, h - 4, "#d0a64f");
      pixelRect(ctx, x + w - 6, y + 5, 6, h - 4, "#d0a64f");
      pixelRect(ctx, x + 7, y + 7, w - 14, h * .62, item.fabricColor || "#9f4f59");
      pixelRect(ctx, x + 5, y + h * .62, w - 10, h * .3, "#b7794d");
      pixelRect(ctx, x + w / 2 - 2, y + 11, 4, 5, "#f2d477");
      return;
    }
    if (type === "fireplace") {
      pixelRect(ctx, x, y, w, h, "#756759");
      pixelRect(ctx, x + 4, y + 4, w - 8, 5, "#a79577");
      pixelRect(ctx, x + 7, y + h * .42, w - 14, h * .48, "#342b2b");
      const flameY = y + h * .7 + (Math.sin(this.elapsed * 8) > 0 ? -2 : 0);
      pixelRect(ctx, x + w / 2 - 6, flameY, 12, h * .2, "#d55d36");
      pixelRect(ctx, x + w / 2 - 3, flameY - 5, 6, h * .22, "#f0b544");
      pixelRect(ctx, x - 3, y + h - 7, w + 6, 7, "#554b43");
      return;
    }
    if (type === "crate") {
      pixelRect(ctx, x + 3, y + 4, w, h, "rgba(42,29,23,.22)");
      pixelRect(ctx, x, y, w, h, dark);
      pixelRect(ctx, x + 3, y + 3, w - 6, h - 6, wood);
      drawPixelLine(ctx, x + 5, y + 5, Math.max(4, w - 10), light);
      for (let step = 0; step < Math.min(w, h) - 8; step += 3) {
        pixelRect(ctx, x + 4 + step, y + 4 + step, 3, 3, dark);
        pixelRect(ctx, x + w - 7 - step, y + 4 + step, 3, 3, dark);
      }
      return;
    }
    if (type === "loom") {
      pixelRect(ctx, x + 2, y, 5, h, dark);
      pixelRect(ctx, x + w - 7, y, 5, h, dark);
      pixelRect(ctx, x + 2, y + 3, w - 4, 5, wood);
      pixelRect(ctx, x + 2, y + h - 8, w - 4, 5, wood);
      for (let thread = x + 9; thread < x + w - 8; thread += 5) pixelRect(ctx, thread, y + 8, 2, h - 16, thread % 2 ? "#d9b56f" : "#9b5f61");
      pixelRect(ctx, x + 7, y + h * .48, w - 14, 5, "#ede0b0");
      return;
    }
    if (type === "telescope") {
      pixelRect(ctx, x + w / 2 - 2, y + h * .35, 4, h * .65, dark);
      pixelRect(ctx, x + 4, y + h - 4, w - 8, 4, dark);
      ctx.fillStyle = "#6b7371";
      ctx.beginPath();
      ctx.moveTo(x + 2, y + h * .34);
      ctx.lineTo(x + w - 5, y);
      ctx.lineTo(x + w, y + 7);
      ctx.lineTo(x + 8, y + h * .42);
      ctx.closePath();
      ctx.fill();
      pixelRect(ctx, x + w - 7, y, 6, 9, "#b9aa73");
      return;
    }
    if (type === "barrel") {
      pixelRect(ctx, x + 3, y, w - 6, h, wood);
      pixelRect(ctx, x, y + 5, w, h - 10, shade(wood, 8));
      pixelRect(ctx, x + 2, y + 5, w - 4, 3, dark);
      pixelRect(ctx, x + 2, y + h - 8, w - 4, 3, dark);
      pixelRect(ctx, x + 4, y, w - 8, 3, light);
      pixelRect(ctx, x + 4, y + h - 3, w - 8, 3, dark);
      return;
    }
    pixelRect(ctx, x + 4, y + 5, w, h, "rgba(42,28,24,.22)");
    pixelRect(ctx, x, y, w, h, dark);
    pixelRect(ctx, x + 3, y + 3, w - 6, h - 6, wood);
    pixelRect(ctx, x + 5, y + 5, Math.max(2, w - 10), 3, light);
  }

  drawLandmark(ctx, item, palette) {
    const { x, y, w, h } = normalizeRect(item);
    const type = String(item.type || item.id || "marker").toLowerCase();
    const id = String(item.id || "").toLowerCase();
    const cx = x + w / 2;
    if (/water|pond|oasis|lake/.test(type)) {
      const water = item.color || palette.water;
      pixelRect(ctx, x - 5, y + 4, w + 10, h - 8, shade(palette.edge, -5));
      pixelRect(ctx, x + 3, y - 4, w - 6, h + 8, shade(palette.edge, -5));
      pixelRect(ctx, x - 2, y + 5, w + 4, h - 10, shade(water, -24));
      pixelRect(ctx, x + 5, y - 1, w - 10, h + 2, water);
      pixelRect(ctx, x + 1, y + 5, w - 2, h - 10, water);
      for (let yy = y + 9; yy < y + h - 5; yy += 13) {
        const phase = Math.floor(this.elapsed * 8 + yy) % 17;
        pixelRect(ctx, x + 9 + phase, yy, Math.min(30, w - 25), 2, shade(water, 33));
        if (w > 90) pixelRect(ctx, x + w - 43 - phase / 2, yy + 5, 21, 2, shade(water, -15));
      }
      if (/oasis/.test(type)) {
        for (let reed = x + 8; reed < x + w; reed += 22) {
          pixelRect(ctx, reed, y - 4 + (reed % 3), 2, 10, "#55794c");
          pixelRect(ctx, reed + 2, y, 4, 2, "#709553");
        }
      }
      return;
    }
    if (/fountain|well/.test(type)) {
      pixelRect(ctx, x + 4, y + h * .58, w - 8, h * .35, "#726f67");
      pixelRect(ctx, x, y + h * .55, w, 9, "#aaa58d");
      pixelRect(ctx, x + 6, y + h * .61, w - 12, h * .18, shade(palette.water, -12));
      pixelRect(ctx, x + 10, y + h * .61, w - 20, 3, shade(palette.water, 37));
      pixelRect(ctx, x + w / 2 - 5, y + 9, 10, h * .52, "#8f8d7e");
      pixelRect(ctx, x + w / 2 - 3, y + 7, 6, h * .46, "#c7bea0");
      pixelRect(ctx, x + w / 2 - 12, y + 7, 24, 6, "#b3aa90");
      pixelRect(ctx, x + w / 2 - 1, y, 2, 9, shade(palette.water, 35));
      pixelRect(ctx, x + w / 2 - 9, y + 4, 4, 12, shade(palette.water, 18));
      pixelRect(ctx, x + w / 2 + 5, y + 4, 4, 12, shade(palette.water, 18));
      return;
    }
    if (/dry_canal/.test(id)) {
      pixelRect(ctx, x, y + 5, w, h - 10, "#776555");
      pixelRect(ctx, x, y, w, 7, "#a88d6c");
      pixelRect(ctx, x, y + h - 7, w, 7, "#8c745b");
      for (let xx = x + 10; xx < x + w - 4; xx += 18) {
        pixelRect(ctx, xx, y + 8 + (xx % 3), 9, 2, "#5d5048");
        pixelRect(ctx, xx + 6, y + 10 + (xx % 3), 2, 6, "#5d5048");
      }
      return;
    }
    if (/scarecrow/.test(`${id} ${type}`)) {
      pixelRect(ctx, x + 4, y + h - 5, w - 8, 5, "rgba(62,45,35,.25)");
      pixelRect(ctx, cx - 2, y + 20, 4, h - 18, "#765035");
      pixelRect(ctx, x + 3, y + 28, w - 6, 4, "#765035");
      pixelRect(ctx, cx - 9, y + 23, 18, 21, "#8e5a46");
      pixelRect(ctx, cx - 7, y + 25, 14, 5, "#bb7a55");
      pixelRect(ctx, cx + 2, y + 34, 5, 5, "#d1a756");
      pixelRect(ctx, cx - 7, y + 9, 14, 14, "#d5aa72");
      pixelRect(ctx, cx - 5, y + 12, 2, 2, "#463a33");
      pixelRect(ctx, cx + 3, y + 12, 2, 2, "#463a33");
      pixelRect(ctx, cx - 9, y + 5, 18, 6, "#b98a45");
      pixelRect(ctx, cx - 14, y + 10, 28, 4, "#d1a353");
      pixelRect(ctx, cx - 5, y + 2, 13, 7, "#c49348");
      for (const strawX of [x + 2, x + w - 4]) {
        pixelRect(ctx, strawX, y + 31, 2, 8, "#dab65c");
        pixelRect(ctx, strawX - 2, y + 37, 2, 5, "#c79943");
      }
      return;
    }
    if (/chasm|fissure|rift/.test(`${id} ${type}`)) {
      pixelRect(ctx, x + 5, y + 9, w - 10, h - 13, "#695f5b");
      pixelRect(ctx, x, y + 18, w, h - 31, "#4b4546");
      pixelRect(ctx, x + 9, y + 12, w - 18, h - 21, "#292932");
      pixelRect(ctx, x + 17, y + 20, w - 34, h - 34, "#171b26");
      pixelRect(ctx, x + 3, y + 10, 18, 6, "#8c8176");
      pixelRect(ctx, x + w - 27, y + h - 15, 24, 7, "#746a64");
      for (let crack = 13; crack < w - 10; crack += 27) {
        const crackY = y + 9 + (hashString(`${id}-${crack}`) % Math.max(5, Math.floor(h * .25)));
        pixelRect(ctx, x + crack, crackY, 2, 8, "#272832");
        pixelRect(ctx, x + crack + 2, crackY + 6, 7, 2, "#272832");
      }
      const echo = Math.sin(this.elapsed * 4) > 0 ? 2 : 0;
      pixelRect(ctx, cx - 10 - echo, y + h * .48, 7, 2, "#7a849d");
      pixelRect(ctx, cx + 3 + echo, y + h * .58, 9, 2, "#59657d");
      return;
    }
    if (/bone|whale|skeleton/.test(`${id} ${type}`)) {
      const bone = item.color || "#d4c49f";
      const darkBone = shade(bone, -35);
      pixelRect(ctx, x + 8, y + h - 9, w - 16, 6, "rgba(89,58,39,.24)");
      pixelRect(ctx, x + 17, y + h * .52, w - 35, 5, darkBone);
      pixelRect(ctx, x + 20, y + h * .48, w - 41, 4, bone);
      for (let ribX = x + 35; ribX < x + w - 25; ribX += 23) {
        const ribH = Math.min(h * .48, 22 + (ribX % 3) * 4);
        pixelRect(ctx, ribX, y + h * .5 - ribH, 4, ribH, bone);
        pixelRect(ctx, ribX + 4, y + h * .5 - ribH, 10, 4, bone);
        pixelRect(ctx, ribX + 11, y + h * .5 - ribH + 3, 4, ribH - 3, darkBone);
      }
      pixelRect(ctx, x + w - 31, y + h * .38, 26, 24, darkBone);
      pixelRect(ctx, x + w - 28, y + h * .34, 22, 20, bone);
      pixelRect(ctx, x + w - 12, y + h * .42, 10, 5, bone);
      pixelRect(ctx, x + w - 23, y + h * .42, 4, 4, "#5d5148");
      return;
    }
    if (/five_seal_table|oath_table/.test(id) || type === "table") {
      const wood = item.color || "#835b43";
      pixelRect(ctx, x + 4, y + 7, w - 8, h - 7, "rgba(51,34,30,.25)");
      pixelRect(ctx, x + 5, y + 2, w - 10, h - 8, shade(wood, -30));
      pixelRect(ctx, x + 9, y, w - 18, h - 7, wood);
      pixelRect(ctx, x + 12, y + 3, w - 24, 4, shade(wood, 23));
      const seats = [[cx - 3, y - 4], [x + 1, y + h * .38], [x + w - 7, y + h * .38], [x + w * .25, y + h - 6], [x + w * .7, y + h - 6]];
      seats.forEach(([seatX, seatY], index) => {
        pixelRect(ctx, seatX, seatY, 6, 7, index === 0 ? "#8b5560" : "#b68b58");
        pixelRect(ctx, seatX + 1, seatY + 1, 4, 2, index === 0 ? "#cf8791" : "#d7ad6f");
      });
      for (let seal = 0; seal < 5; seal += 1) {
        const sealX = x + 14 + (seal % 3) * Math.max(5, (w - 29) / 2);
        const sealY = y + 10 + Math.floor(seal / 3) * 10;
        pixelRect(ctx, sealX, sealY, 4, 4, ["#b65b56", "#6f9b69", "#7799af", "#d0a553", "#8e72a1"][seal]);
      }
      return;
    }
    if (/clock/.test(`${id} ${type}`)) {
      const frameW = Math.min(w - 4, Math.max(34, h * .68));
      const frameH = Math.min(h - 2, Math.max(38, h * .86));
      const frameX = cx - frameW / 2;
      const frameY = y + h - frameH;
      if (/tunnel/.test(id)) {
        pixelRect(ctx, x + 4, y + 10, w - 8, h - 8, "#544b49");
        pixelRect(ctx, x + 11, y + 17, w - 22, h - 15, "#292a30");
        pixelRect(ctx, x + 16, y + 21, w - 32, h - 21, "#181c25");
      }
      pixelRect(ctx, frameX + 3, frameY + 4, frameW, frameH, "rgba(48,31,28,.24)");
      pixelRect(ctx, frameX, frameY, frameW, frameH, "#654a3d");
      pixelRect(ctx, frameX + 4, frameY + 4, frameW - 8, frameH - 8, "#a7744d");
      const face = Math.min(frameW - 10, frameH * .58);
      const faceX = cx - face / 2;
      const faceY = frameY + 6;
      pixelRect(ctx, faceX, faceY + 3, face, face - 6, "#57473c");
      pixelRect(ctx, faceX + 3, faceY, face - 6, face, "#57473c");
      pixelRect(ctx, faceX + 4, faceY + 4, face - 8, face - 8, "#e0d09d");
      pixelRect(ctx, cx - 1, faceY + 7, 2, 5, "#755e46");
      pixelRect(ctx, cx - 1, faceY + face - 12, 2, 5, "#755e46");
      pixelRect(ctx, faceX + 7, faceY + face / 2, 5, 2, "#755e46");
      pixelRect(ctx, faceX + face - 12, faceY + face / 2, 5, 2, "#755e46");
      pixelRect(ctx, cx - 1, faceY + face / 2 - 1, 2, face * .24, "#4b4038");
      pixelRect(ctx, cx - 1, faceY + face / 2 - 1, face * .2, 2, "#4b4038");
      pixelRect(ctx, cx - 3, frameY + frameH - 8, 6, 6, "#d4b15c");
      return;
    }
    if (/board|contract/.test(`${id} ${type}`)) {
      const board = item.color || "#8b6244";
      pixelRect(ctx, x + 4, y + 5, w, h, "rgba(46,31,27,.22)");
      pixelRect(ctx, x, y, w, h, shade(board, -31));
      pixelRect(ctx, x + 5, y + 5, w - 10, h - 10, board);
      pixelRect(ctx, x + 8, y + 8, w - 16, h - 16, "#d4bc83");
      const columns = w > 150 ? 3 : 1;
      const paperW = (w - 22 - (columns - 1) * 7) / columns;
      for (let column = 0; column < columns; column += 1) {
        const paperX = x + 11 + column * (paperW + 7);
        pixelRect(ctx, paperX, y + 10, paperW, h - 20, column % 2 ? "#e3d29d" : "#eadbad");
        pixelRect(ctx, paperX + 3, y + 15, Math.max(4, paperW - 7), 2, "#8d7158");
        for (let line = y + 21; line < y + h - 9; line += 6) pixelRect(ctx, paperX + 4, line, Math.max(3, paperW - 10 - ((line / 6) % 3) * 3), 2, "#9f8161");
        pixelRect(ctx, paperX + paperW - 9, y + h - 16, 5, 5, "#a94f4e");
      }
      return;
    }
    if (/canvas|painting|rubbing|ice_memory/.test(id)) {
      const icy = /ice_memory/.test(id);
      const paper = /rubbing/.test(id);
      const frame = paper ? "#785845" : icy ? "#557985" : "#765044";
      const picture = paper ? "#c8aa76" : icy ? "#8fc2cc" : "#8f6f79";
      pixelRect(ctx, x + 4, y + 5, w, h, "rgba(43,29,31,.22)");
      pixelRect(ctx, x, y, w, h, shade(frame, -26));
      pixelRect(ctx, x + 4, y + 4, w - 8, h - 8, frame);
      pixelRect(ctx, x + 9, y + 9, w - 18, h - 18, picture);
      pixelRect(ctx, x + 12, y + 12, w - 24, Math.max(5, h * .28), shade(picture, 28));
      if (paper) {
        for (let glyphX = x + 18; glyphX < x + w - 15; glyphX += 18) {
          pixelRect(ctx, glyphX, y + 20 + (glyphX % 5), 3, h - 37, "#725b4c");
          pixelRect(ctx, glyphX - 4, y + h * .48, 11, 2, "#725b4c");
        }
      } else {
        pixelRect(ctx, x + 13, y + h - 20, w - 26, 6, shade(picture, -28));
        const figureX = x + w * .48;
        pixelRect(ctx, figureX, y + h * .42, 6, 8, icy ? "#e2f1ed" : "#d9ad77");
        pixelRect(ctx, figureX - 3, y + h * .52, 12, Math.max(6, h * .22), icy ? "#6e91a0" : "#6f5267");
        if (icy) for (let crack = x + 18; crack < x + w - 10; crack += 31) pixelRect(ctx, crack, y + 14 + (crack % 7), 2, h - 27, "rgba(225,248,246,.48)");
      }
      return;
    }
    if (/notes|letters/.test(id)) {
      const sheets = Math.max(2, Math.min(4, Math.floor(w / 48)));
      const sheetW = Math.min(54, (w - 8) / sheets);
      for (let sheet = 0; sheet < sheets; sheet += 1) {
        const sheetX = x + 4 + sheet * ((w - sheetW - 8) / Math.max(1, sheets - 1));
        const sheetY = y + 4 + (sheet % 2) * 7;
        pixelRect(ctx, sheetX + 3, sheetY + 4, sheetW, h - 12, "rgba(53,37,31,.2)");
        pixelRect(ctx, sheetX, sheetY, sheetW, h - 14, sheet % 2 ? "#e2cf9a" : "#eedcac");
        pixelRect(ctx, sheetX + 5, sheetY + 6, sheetW - 10, 2, "#95765b");
        for (let line = sheetY + 12; line < sheetY + h - 20; line += 6) pixelRect(ctx, sheetX + 6, line, Math.max(4, sheetW - 14 - ((line / 6) % 2) * 5), 2, "#aa8965");
        if (/burned/.test(id)) {
          pixelRect(ctx, sheetX, sheetY + h - 23, sheetW, 9, "#6a4938");
          pixelRect(ctx, sheetX + 6, sheetY + h - 27, 5, 7, "#a65436");
        }
      }
      return;
    }
    if (/map/.test(`${id} ${type}`)) {
      pixelRect(ctx, x + 5, y + 5, w - 10, h - 5, "rgba(48,32,27,.22)");
      pixelRect(ctx, x, y + 3, w, h - 6, "#76533d");
      pixelRect(ctx, x + 6, y, w - 12, h, "#d8bd82");
      pixelRect(ctx, x + 10, y + 5, w - 20, h - 10, "#ead59d");
      for (let mark = 0; mark < 7; mark += 1) {
        const markX = x + 18 + mark * Math.max(8, (w - 42) / 6);
        const markY = y + h * .62 - Math.sin(mark * 1.7) * h * .22;
        pixelRect(ctx, markX, markY, 7, 3, mark === 6 ? "#a84e47" : "#6e7e57");
        if (mark < 6) pixelRect(ctx, markX + 5, markY - 2, Math.max(4, (w - 42) / 6), 2, "#8d654c");
      }
      pixelRect(ctx, x + w - 23, y + 10, 7, 7, "#a84e47");
      pixelRect(ctx, x + w - 21, y + 7, 3, 13, "#a84e47");
      return;
    }
    if (/scope|telescope/.test(`${id} ${type}`)) {
      const scopeY = y + h * .3;
      pixelRect(ctx, cx - 2, scopeY + 16, 4, h * .5, "#58473d");
      pixelRect(ctx, cx - 18, y + h - 5, 36, 5, "#58473d");
      ctx.fillStyle = "#657579";
      ctx.beginPath();
      ctx.moveTo(x + w * .2, scopeY + 12);
      ctx.lineTo(x + w * .72, y + 5);
      ctx.lineTo(x + w * .79, y + 15);
      ctx.lineTo(x + w * .27, scopeY + 21);
      ctx.closePath();
      ctx.fill();
      pixelRect(ctx, x + w * .69, y + 4, Math.max(8, w * .1), 13, "#c1aa6d");
      pixelRect(ctx, x + w * .24, scopeY + 10, Math.max(8, w * .12), 13, "#39474d");
      const sparkle = Math.sin(this.elapsed * 5) > 0 ? 2 : 0;
      pixelRect(ctx, x + w * .82, y + 3 - sparkle, 3, 10, "#d9eeee");
      pixelRect(ctx, x + w * .82 - 4, y + 6 - sparkle, 11, 3, "#d9eeee");
      return;
    }
    if (/chest/.test(`${id} ${type}`)) {
      const wood = item.color || "#80533c";
      const chestW = Math.min(w - 4, 68);
      const chestH = Math.min(h - 4, 45);
      const chestX = cx - chestW / 2;
      const chestY = y + h - chestH;
      const glowPulse = Math.sin(this.elapsed * 4) > 0 ? 2 : 0;
      pixelRect(ctx, chestX - 4, chestY - 5 - glowPulse, chestW + 8, chestH + 8, "rgba(89,170,188,.18)");
      pixelRect(ctx, chestX + 3, chestY + 5, chestW, chestH, "rgba(50,31,26,.24)");
      pixelRect(ctx, chestX, chestY + 10, chestW, chestH - 10, shade(wood, -30));
      pixelRect(ctx, chestX + 4, chestY + 14, chestW - 8, chestH - 18, wood);
      pixelRect(ctx, chestX + 3, chestY + 3, chestW - 6, 14, shade(wood, 15));
      pixelRect(ctx, chestX + 6, chestY, chestW - 12, 6, shade(wood, 31));
      pixelRect(ctx, cx - 5, chestY + 12, 10, 12, "#c6a34f");
      pixelRect(ctx, cx - 2, chestY + 14, 4, 5, "#5f513c");
      pixelRect(ctx, cx - 1, chestY - 8 - glowPulse, 3, 8, "#7cd0c0");
      pixelRect(ctx, cx - 5, chestY - 5 - glowPulse, 11, 3, "#a7e3cf");
      return;
    }
    if (/blue_honey|honey/.test(id)) {
      pixelRect(ctx, x, y + 6, w, h - 6, "#70503b");
      pixelRect(ctx, x + 4, y + 10, w - 8, h - 14, "#9a6c45");
      for (let jarX = x + 10; jarX < x + w - 8; jarX += 22) {
        pixelRect(ctx, jarX, y + 15, 13, h - 24, "#477d8c");
        pixelRect(ctx, jarX + 3, y + 18, 7, h - 30, "#74bdc2");
        pixelRect(ctx, jarX - 1, y + 11, 15, 5, "#d2b36c");
      }
      pixelRect(ctx, x, y + h * .52, w, 5, "#60422f");
      return;
    }
    if (/grain_wall/.test(id)) {
      pixelRect(ctx, x, y, w, h, "#614431");
      for (let plankX = x + 4; plankX < x + w - 3; plankX += 18) {
        pixelRect(ctx, plankX, y + 4, 14, h - 8, plankX % 2 ? "#9c7049" : "#ad7d50");
        pixelRect(ctx, plankX + 3, y + 8, 3, h - 16, "#bd8b58");
      }
      pixelRect(ctx, x + 4, y + h * .45, w - 8, 6, "#5b4132");
      pixelRect(ctx, x + w * .72, y + h * .45 - 6, 7, 18, "#d0a85d");
      return;
    }
    if (/statue|obelisk|shrine|crystal|ruin/.test(type)) {
      if (/ember_ruins/.test(id)) {
        pixelRect(ctx, x + 5, y + h - 19, w - 10, 17, "#795342");
        for (let column = x + 12; column < x + w - 8; column += 35) {
          const columnHeight = 34 + (hashString(`${id}-${column}`) % 38);
          pixelRect(ctx, column, y + h - columnHeight, 16, columnHeight - 13, "#9a6847");
          pixelRect(ctx, column - 3, y + h - columnHeight, 22, 7, "#b47b50");
          pixelRect(ctx, column + 3, y + h - columnHeight + 9, 3, columnHeight - 27, "#c18a59");
        }
        pixelRect(ctx, x, y + h - 10, w, 10, "#684a3f");
        return;
      }
      const accent = item.color || palette.accent;
      pixelRect(ctx, x + 6, y + 9, w, h, "rgba(44,36,42,.28)");
      if (/crystal/.test(type)) {
        ctx.fillStyle = shade(accent, -28);
        ctx.beginPath();
        ctx.moveTo(x + w / 2, y);
        ctx.lineTo(x + w * .76, y + h * .55);
        ctx.lineTo(x + w * .6, y + h * .78);
        ctx.lineTo(x + w * .35, y + h * .75);
        ctx.lineTo(x + w * .23, y + h * .48);
        ctx.closePath();
        ctx.fill();
        pixelRect(ctx, x + w * .42, y + 10, w * .12, h * .54, shade(accent, 38));
        pixelRect(ctx, x + w * .31, y + h * .28, 5, h * .32, shade(accent, 12));
      } else {
        pixelRect(ctx, x + w * .31, y + 7, w * .38, h * .68, shade(accent, -22));
        pixelRect(ctx, x + w * .37, y + 3, w * .26, h * .62, accent);
        pixelRect(ctx, x + w * .41, y + 8, 3, h * .42, shade(accent, 35));
      }
      pixelRect(ctx, x + w * .13, y + h * .69, w * .74, h * .22, shade(accent, -35));
      pixelRect(ctx, x + w * .2, y + h * .65, w * .6, 6, shade(accent, 12));
      return;
    }
    if (/tree|pine/.test(type)) {
      if (/pine/.test(type)) this.drawPine(ctx, x, y, /snow|frost/.test(id));
      else this.drawTree(ctx, x, y, { ...palette, edge: item.color || palette.edge }, 0);
      return;
    }
    pixelRect(ctx, x + 3, y + 4, w, h, "rgba(43,31,35,.22)");
    pixelRect(ctx, x, y, w, h, item.color || palette.accent);
    pixelRect(ctx, x + 3, y + 3, Math.max(2, w - 6), 3, shade(item.color || palette.accent, 25));
  }

  drawShadow(ctx, x, y, width = 22) {
    pixelRect(ctx, x - width / 2 + 4, y + 5, width - 8, 2, "rgba(43,31,36,.18)");
    pixelRect(ctx, x - width / 2 + 2, y + 7, width - 4, 3, "rgba(43,31,36,.25)");
    pixelRect(ctx, x - width / 2 + 5, y + 10, width - 10, 2, "rgba(43,31,36,.17)");
  }

  drawNpc(ctx, npc, npcState, state) {
    const x = Math.round(npcState.x);
    const y = Math.round(npcState.y);
    const targetDx = Number(npcState.targetX) - npcState.x;
    const targetDy = Number(npcState.targetY) - npcState.y;
    const intendedFacing = npcState.facing || (Number.isFinite(targetDx) && Number.isFinite(targetDy) && Math.hypot(targetDx, targetDy) > 1
      ? (Math.abs(targetDx) > Math.abs(targetDy) ? (targetDx > 0 ? "right" : "left") : (targetDy > 0 ? "down" : "up"))
      : "down");
    const motion = this.sampleActorMotion(`npc:${npc.id}`, npcState.x, npcState.y, intendedFacing);
    const { moving, walkFrame, facing } = motion;
    if (state.mode === "observer" && state.observer?.focusedNpcId === npc.id) {
      const focus = "#f2d579";
      pixelRect(ctx, x - 20, y - 48, 10, 2, focus);
      pixelRect(ctx, x - 20, y - 48, 2, 10, focus);
      pixelRect(ctx, x + 10, y - 48, 10, 2, focus);
      pixelRect(ctx, x + 18, y - 48, 2, 10, focus);
      pixelRect(ctx, x - 20, y + 10, 10, 2, focus);
      pixelRect(ctx, x - 20, y + 2, 2, 10, focus);
      pixelRect(ctx, x + 10, y + 10, 10, 2, focus);
      pixelRect(ctx, x + 18, y + 2, 2, 10, focus);
      pixelRect(ctx, x - 2, y - 53, 4, 4, "#fff1af");
      pixelRect(ctx, x, y - 55, 2, 2, "#fff7cf");
    }
    this.drawShadow(ctx, x, y, moving ? 29 : 27);
    const style = NPC_STYLE[npc.id] || { hair: "short", trim: shade(npc.color || "#8f6975", 25), outfit: "coat" };
    const skin = npc.skinColor || SKIN_TONES[hashString(npc.id) % SKIN_TONES.length];
    this.drawCharacter(ctx, x, y, {
      body: npc.color || "#9a6c78",
      hair: npc.hairColor || "#4c3841",
      skin,
      style,
      moving,
      walkFrame,
      facing,
    });
    if (state.mode === "observer" || distance(state.player, npcState) < 82) {
      ctx.font = 'bold 10px "Microsoft YaHei", sans-serif';
      ctx.textAlign = "center";
      const labelWidth = Math.max(43, npc.name.length * 11 + 11);
      pixelRect(ctx, x - labelWidth / 2 - 2, y - 64, labelWidth + 4, 16, "rgba(72,52,43,.9)");
      pixelRect(ctx, x - labelWidth / 2, y - 62, labelWidth, 12, "#f1dfad");
      pixelRect(ctx, x - 2, y - 50, 4, 3, "#795c45");
      ctx.fillStyle = "#514038";
      ctx.fillText(npc.name, x, y - 52);
    }
    if (npcState.memories[0]?.importance >= 3 && Math.sin(this.elapsed * 2.5) > .25) {
      pixelRect(ctx, x + 14, y - 44, 10, 10, "#6e5544");
      pixelRect(ctx, x + 16, y - 46, 8, 10, "#fff0b2");
      pixelRect(ctx, x + 14, y - 37, 3, 3, "#fff0b2");
      pixelRect(ctx, x + 19, y - 44, 2, 5, "#7d5a48");
      pixelRect(ctx, x + 19, y - 38, 2, 2, "#7d5a48");
    }
  }

  drawCharacter(ctx, x, y, character) {
    const { body, hair, skin, style = {}, stride = 0 } = character;
    const facing = ["up", "down", "left", "right"].includes(character.facing) ? character.facing : "down";
    const moving = Boolean(character.moving ?? stride);
    const frame = moving ? ((Number(character.walkFrame || 0) % 4) + 4) % 4 : 0;
    const gait = moving ? [1, 0, -1, 0][frame] : 0;
    const bob = moving && frame === 1 ? -1 : 0;
    const py = y + bob;
    const outline = "#3d3035";
    const trim = style.trim || shade(body, 30);
    const pants = shade(body, -42);
    const shoe = "#493b3a";
    const side = facing === "right" ? 1 : facing === "left" ? -1 : 0;
    const leftFootY = py + 3 + gait * 2;
    const rightFootY = py + 3 - gait * 2;

    // Hair and braids that sit behind the body.
    if (style.hair === "long") {
      const hairShift = side ? -side * 2 : 0;
      pixelRect(ctx, x - 11 + hairShift, py - 38, 22, 29, shade(hair, -28));
      pixelRect(ctx, x - 9 + hairShift, py - 36, 18, 25, hair);
      pixelRect(ctx, x - 6 + hairShift, py - 34, 6, 21, shade(hair, 13));
    } else if (style.hair === "braid") {
      const braidX = facing === "left" ? x + 7 : x - 11;
      pixelRect(ctx, braidX, py - 32, 6, 24, shade(hair, -28));
      pixelRect(ctx, braidX + 2, py - 30, 3, 20, hair);
      pixelRect(ctx, braidX + 1, py - 9, 5, 5, shade(hair, 18));
    }

    // Two separate legs use opposite gait offsets, leaving the collision foot point unchanged.
    pixelRect(ctx, x - 10, py - 8, 9, Math.max(9, leftFootY - py + 12), outline);
    pixelRect(ctx, x + 1, py - 8, 9, Math.max(9, rightFootY - py + 12), outline);
    pixelRect(ctx, x - 8, py - 7, 6, Math.max(7, leftFootY - py + 9), pants);
    pixelRect(ctx, x + 2, py - 7, 6, Math.max(7, rightFootY - py + 9), shade(pants, -5));
    const leftShoeX = side < 0 ? x - 12 : x - 10;
    const rightShoeX = side > 0 ? x + 1 : x + 2;
    pixelRect(ctx, leftShoeX, leftFootY, side < 0 ? 11 : 9, 5, outline);
    pixelRect(ctx, leftShoeX + (side < 0 ? 0 : 2), leftFootY + 1, side < 0 ? 9 : 7, 3, shoe);
    pixelRect(ctx, rightShoeX, rightFootY, side > 0 ? 11 : 9, 5, outline);
    pixelRect(ctx, rightShoeX + 1, rightFootY + 1, side > 0 ? 9 : 7, 3, shade(shoe, -3));

    const isDress = style.outfit === "dress" || style.outfit === "robe";
    const leftArmShift = moving ? -gait * 2 : 0;
    const rightArmShift = moving ? gait * 2 : 0;
    const leftArmX = side > 0 ? x - 10 : x - 15;
    const rightArmX = side < 0 ? x + 6 : x + 10;
    pixelRect(ctx, leftArmX, py - 19 + leftArmShift, 6, 17, outline);
    pixelRect(ctx, leftArmX + 2, py - 17 + leftArmShift, 3, 12, shade(body, 10));
    pixelRect(ctx, leftArmX + 2, py - 5 + leftArmShift, 4, 5, skin);
    pixelRect(ctx, rightArmX, py - 19 + rightArmShift, 6, 17, outline);
    pixelRect(ctx, rightArmX + 1, py - 17 + rightArmShift, 3, 12, shade(body, -12));
    pixelRect(ctx, rightArmX, py - 5 + rightArmShift, 4, 5, shade(skin, -8));

    if (isDress) {
      pixelRect(ctx, x - 13, py - 9, 26, 13, outline);
      pixelRect(ctx, x - 11, py - 10, 22, 12, body);
      pixelRect(ctx, x - 8, py - 8, 16, 3, shade(body, 16));
    }
    const torsoX = side ? x - 10 : x - 12;
    const torsoW = side ? 20 : 24;
    pixelRect(ctx, torsoX, py - 22, torsoW, 23, outline);
    pixelRect(ctx, torsoX + 2, py - 20, torsoW - 4, 20, body);
    pixelRect(ctx, torsoX + 2, py - 19, 4, 16, shade(body, 18));
    pixelRect(ctx, torsoX + torsoW - 5, py - 18, 3, 16, shade(body, -22));
    pixelRect(ctx, x - (side ? 8 : 10), py - 20, side ? 16 : 20, 4, shade(body, 10));

    if (facing === "up") {
      pixelRect(ctx, x - 1, py - 19, 2, 17, shade(body, -26));
      pixelRect(ctx, x - 7, py - 8, 14, 4, trim);
      if (style.outfit === "overalls") pixelRect(ctx, x - 6, py - 17, 12, 9, shade(body, -32));
    } else if (style.outfit === "overalls") {
      pixelRect(ctx, x - 7, py - 16, 14, 16, shade(body, -31));
      pixelRect(ctx, x - 7, py - 18, 3, 7, trim);
      pixelRect(ctx, x + 4, py - 18, 3, 7, trim);
      pixelRect(ctx, x - 3, py - 9, 6, 4, shade(trim, 18));
      pixelRect(ctx, x - 1, py - 4, 2, 2, "#d2ae62");
    } else if (style.outfit === "apron") {
      pixelRect(ctx, x - 7, py - 15, 14, 15, shade(trim, 18));
      pixelRect(ctx, x - 5, py - 5, 10, 3, shade(trim, -18));
    } else if (/coat|uniform|scholar/.test(style.outfit || "")) {
      pixelRect(ctx, x - 1, py - 20, 2, 20, trim);
      pixelRect(ctx, x - 6, py - 16, 5, 4, shade(body, 22));
      pixelRect(ctx, x + 2, py - 10, 3, 3, trim);
      if (style.outfit === "uniform") pixelRect(ctx, x - 10, py - 19, 20, 4, trim);
    } else if (style.outfit === "vest") {
      pixelRect(ctx, x - 8, py - 19, 7, 17, shade(body, -28));
      pixelRect(ctx, x + 1, py - 19, 7, 17, shade(body, -28));
      pixelRect(ctx, x - 1, py - 16, 2, 13, trim);
    } else if (/merchant|guide|artist/.test(style.outfit || "")) {
      pixelRect(ctx, x - 10, py - 7, 20, 4, trim);
      pixelRect(ctx, x - 7, py - 18, 14, 4, shade(trim, 8));
      if (style.outfit === "guide") pixelRect(ctx, x + (side < 0 ? -8 : 5), py - 14, 4, 9, shade(trim, -20));
    }

    pixelRect(ctx, x - 5, py - 27, 10, 7, outline);
    pixelRect(ctx, x - 3, py - 27, 6, 7, skin);
    if (facing === "up") {
      pixelRect(ctx, x - 11, py - 40, 22, 19, shade(hair, -30));
      pixelRect(ctx, x - 9, py - 39, 18, 17, hair);
      pixelRect(ctx, x - 6, py - 38, 7, 4, shade(hair, 23));
      pixelRect(ctx, x - 9, py - 27, 4, 7, shade(hair, -22));
      pixelRect(ctx, x + 5, py - 27, 4, 7, shade(hair, -28));
    } else if (side) {
      const headX = x - 10 + side;
      pixelRect(ctx, headX, py - 40, 21, 19, outline);
      pixelRect(ctx, headX + 2, py - 38, 17, 15, skin);
      pixelRect(ctx, x + side * 9 - (side < 0 ? 3 : 0), py - 32, 4, 5, shade(skin, -7));
      pixelRect(ctx, x - side * 8 - 2, py - 32, 4, 6, shade(skin, -13));
    } else {
      pixelRect(ctx, x - 11, py - 40, 22, 19, outline);
      pixelRect(ctx, x - 9, py - 38, 18, 15, skin);
      pixelRect(ctx, x - 11, py - 34, 3, 9, skin);
      pixelRect(ctx, x + 8, py - 34, 3, 9, shade(skin, -9));
    }

    this.drawHair(ctx, x, py, hair, style.hair || "short", facing);
    this.drawFace(ctx, x, py, facing, skin, style);
    this.drawAccessory(ctx, x, py, body, hair, skin, style, facing, gait);
  }

  drawHair(ctx, x, y, hair, hairStyle, facing = "down") {
    const dark = shade(hair, -28);
    if (facing === "up") {
      pixelRect(ctx, x - 10, y - 41, 20, 7, dark);
      pixelRect(ctx, x - 8, y - 40, 16, 6, hair);
      if (hairStyle === "bob" || hairStyle === "long") pixelRect(ctx, x - 10, y - 34, 20, 13, dark);
      return;
    }
    const side = facing === "right" ? 1 : facing === "left" ? -1 : 0;
    pixelRect(ctx, x - 10, y - 42, 20, 7, dark);
    pixelRect(ctx, x - 8, y - 41, 16, 6, hair);
    pixelRect(ctx, x - 10, y - 38, 4, hairStyle === "bob" ? 16 : 10, dark);
    if (side) {
      const backX = side > 0 ? x - 10 : x + 6;
      pixelRect(ctx, backX, y - 38, 5, hairStyle === "bob" ? 17 : 12, dark);
      pixelRect(ctx, x - side * 2 - 5, y - 39, 10, 5, hair);
    }
    if (hairStyle === "bob") {
      pixelRect(ctx, x + 6, y - 38, 4, 16, dark);
      pixelRect(ctx, x - 7, y - 42, 7, 3, shade(hair, 22));
    } else if (hairStyle === "side") {
      pixelRect(ctx, x + 3, y - 41, 7, 12, hair);
      pixelRect(ctx, x + 6, y - 34, 4, 11, dark);
      pixelRect(ctx, x - 5, y - 40, 8, 4, shade(hair, 18));
    } else if (hairStyle === "bun") {
      const bunX = side < 0 ? x + 6 : x - 13;
      pixelRect(ctx, bunX, y - 46, 10, 10, dark);
      pixelRect(ctx, bunX + 2, y - 45, 7, 7, hair);
      pixelRect(ctx, x - 7, y - 42, 6, 3, shade(hair, 26));
    } else if (hairStyle === "long") {
      pixelRect(ctx, x - 10, y - 35, 4, 15, dark);
      pixelRect(ctx, x + 6, y - 35, 4, 15, dark);
    } else if (hairStyle === "braid") {
      pixelRect(ctx, x - 8, y - 41, 7, 4, shade(hair, 20));
      pixelRect(ctx, side < 0 ? x + 6 : x - 10, y - 35, 4, 10, dark);
    }
  }

  drawFace(ctx, x, y, facing, skin, style) {
    const ink = "#40343a";
    if (facing === "up") return;
    if (facing === "left") {
      pixelRect(ctx, x - 5, y - 32, 3, 3, ink);
      pixelRect(ctx, x - 11, y - 29, 4, 3, shade(skin, -14));
      pixelRect(ctx, x - 5, y - 26, 4, 2, shade(skin, -25));
    }
    else if (facing === "right") {
      pixelRect(ctx, x + 3, y - 32, 3, 3, ink);
      pixelRect(ctx, x + 8, y - 29, 4, 3, shade(skin, -14));
      pixelRect(ctx, x + 2, y - 26, 4, 2, shade(skin, -25));
    }
    else if (facing === "down") {
      pixelRect(ctx, x - 5, y - 32, 3, 3, ink);
      pixelRect(ctx, x + 3, y - 32, 3, 3, ink);
      pixelRect(ctx, x - 2, y - 27, 5, 2, shade(skin, -22));
      pixelRect(ctx, x - 6, y - 29, 2, 2, shade(skin, 18));
      pixelRect(ctx, x + 5, y - 29, 2, 2, shade(skin, 12));
    }
    if (style.accessory === "glasses") {
      if (facing === "down") {
        pixelRect(ctx, x - 7, y - 34, 7, 6, "#4d4a4a");
        pixelRect(ctx, x + 1, y - 34, 7, 6, "#4d4a4a");
        pixelRect(ctx, x, y - 32, 2, 2, "#4d4a4a");
        pixelRect(ctx, x - 5, y - 32, 3, 3, "#b9d8d2");
        pixelRect(ctx, x + 3, y - 32, 3, 3, "#b9d8d2");
      } else {
        const lensX = facing === "left" ? x - 7 : x + 1;
        pixelRect(ctx, lensX, y - 34, 8, 6, "#4d4a4a");
        pixelRect(ctx, lensX + 2, y - 32, 3, 3, "#b9d8d2");
      }
    }
    if (style.accessory === "mustache") {
      if (facing === "down") {
        pixelRect(ctx, x - 6, y - 28, 6, 3, "#b9b4a8");
        pixelRect(ctx, x + 1, y - 28, 6, 3, "#b9b4a8");
      } else pixelRect(ctx, x + (facing === "left" ? -8 : 2), y - 28, 7, 3, "#b9b4a8");
    }
  }

  drawAccessory(ctx, x, y, body, hair, skin, style, facing = "down", gait = 0) {
    const trim = style.trim || shade(body, 30);
    const side = facing === "right" ? 1 : facing === "left" ? -1 : 0;
    switch (style.accessory) {
      case "straw":
        pixelRect(ctx, x - 16, y - 43, 32, 5, "#7d5836");
        pixelRect(ctx, x - 14, y - 45, 28, 5, "#e0b653");
        pixelRect(ctx, x - 9, y - 51, 18, 8, "#e9c462");
        pixelRect(ctx, x - 8, y - 46, 16, 3, "#ae7042");
        break;
      case "beekeeper":
        pixelRect(ctx, x - 15, y - 44, 30, 5, "#e2c16a");
        pixelRect(ctx, x - 10, y - 50, 20, 7, "#f0d47c");
        pixelRect(ctx, x - 12, y - 40, 24, 20, "rgba(220,231,203,.35)");
        pixelRect(ctx, x - 13, y - 40, 3, 20, "#8f8060");
        pixelRect(ctx, x + 10, y - 40, 3, 20, "#8f8060");
        pixelRect(ctx, x - 10, y - 23, 20, 3, "#8f8060");
        break;
      case "guard":
        pixelRect(ctx, x - 12, y - 43, 24, 5, "#3f555c");
        pixelRect(ctx, x - 9, y - 49, 18, 7, trim);
        pixelRect(ctx, x - 2, y - 54, 4, 7, "#b9c5b5");
        pixelRect(ctx, x - 15, y - 18, 6, 7, trim);
        pixelRect(ctx, x + 9, y - 18, 6, 7, trim);
        break;
      case "kerchief":
        pixelRect(ctx, x - 10, y - 42, 20, 6, trim);
        pixelRect(ctx, x + (side < 0 ? -11 : 7), y - 39, 6, 12, shade(trim, -18));
        break;
      case "jewel":
        pixelRect(ctx, x - 3, y - 43, 6, 6, "#f2cf68");
        pixelRect(ctx, x - 1, y - 46, 3, 3, "#f7e5a0");
        break;
      case "beret":
        pixelRect(ctx, x - 11, y - 44, 23, 6, shade(trim, -12));
        pixelRect(ctx, x - 6, y - 48, 16, 6, trim);
        pixelRect(ctx, x + 5, y - 50, 3, 4, shade(trim, 15));
        break;
      case "medic":
        pixelRect(ctx, x + (side < 0 ? -11 : 8), y - 17 + gait, 3, 20, "#735344");
        pixelRect(ctx, x + (side < 0 ? -15 : 7), y - 4 + gait, 11, 10, trim);
        pixelRect(ctx, x + (side < 0 ? -11 : 11), y - 3 + gait, 3, 8, "#c96565");
        pixelRect(ctx, x + (side < 0 ? -13 : 9), y, 7, 3, "#c96565");
        break;
      case "furhat":
        pixelRect(ctx, x - 12, y - 47, 24, 8, "#6c5a4d");
        pixelRect(ctx, x - 10, y - 50, 20, 6, "#8b7663");
        pixelRect(ctx, x - 12, y - 42, 6, 10, trim);
        pixelRect(ctx, x + 6, y - 42, 6, 10, trim);
        break;
      case "hood":
        pixelRect(ctx, x - 13, y - 43, 26, 8, shade(body, -25));
        pixelRect(ctx, x - 13, y - 38, 5, 16, shade(body, -25));
        pixelRect(ctx, x + 8, y - 38, 5, 16, shade(body, -35));
        pixelRect(ctx, x - 10, y - 44, 20, 4, trim);
        break;
      case "headwrap":
        pixelRect(ctx, x - 11, y - 46, 22, 8, trim);
        pixelRect(ctx, x - 8, y - 50, 17, 6, shade(trim, 15));
        pixelRect(ctx, x + (side < 0 ? -11 : 7), y - 40, 6, 13, shade(trim, -22));
        break;
      case "headband":
        pixelRect(ctx, x - 10, y - 41, 20, 4, trim);
        pixelRect(ctx, x + (side < 0 ? -13 : 8), y - 40, 6, 4, shade(trim, 15));
        break;
      default:
        break;
    }
  }

  drawPlayer(ctx, player) {
    const x = Math.round(player.x);
    const y = Math.round(player.y);
    const motion = this.sampleActorMotion("player", player.x, player.y, player.facing);
    this.drawShadow(ctx, x, y, motion.moving ? 30 : 28);
    this.drawCharacter(ctx, x, y, {
      body: "#3e8580",
      hair: "#513a43",
      skin: "#edbb8c",
      style: { hair: "side", trim: "#e1b454", outfit: "guide", accessory: "headband" },
      moving: motion.moving,
      walkFrame: motion.walkFrame,
      facing: motion.facing,
    });
  }

  drawInteriorLight(ctx, state, scene) {
    const hour = Number(state.minute || 0) / 60;
    const darkness = hour < 6 || hour >= 21 ? .2 : hour >= 18 ? (hour - 18) / 3 * .14 : 0;
    if (darkness > 0) {
      ctx.fillStyle = `rgba(45,36,58,${darkness})`;
      ctx.fillRect(0, 0, WIDTH, HEIGHT);
    }
    const ambient = scene.ambientColor || scene.palette?.ambient;
    if (ambient) {
      ctx.save();
      ctx.globalAlpha = Number(scene.ambientAlpha ?? .1);
      ctx.fillStyle = ambient;
      ctx.fillRect(0, 0, WIDTH, HEIGHT);
      ctx.restore();
    }
  }

  drawWeather(ctx, state, region, deltaSeconds) {
    const weather = state.weather || "晴";
    const isMist = /雾|阴/.test(weather);
    const isAurora = /极光/.test(weather);
    if (!/雪|尘|雨|星/.test(weather) && !isMist && !isAurora && region.id !== "snow") return;
    const isSnow = /雪/.test(weather) || region.id === "snow";
    const isDust = /尘/.test(weather) || (region.id === "desert" && /风/.test(weather));
    const isRain = /雨/.test(weather);
    if (isMist) {
      for (let band = 0; band < 4; band += 1) {
        const x = ((this.elapsed * (5 + band) + band * 220) % (WIDTH + 260)) - 180;
        pixelRect(ctx, x, 92 + band * 89, 210, 9, "rgba(225,232,217,.09)");
        pixelRect(ctx, x + 35, 101 + band * 89, 260, 6, "rgba(225,232,217,.06)");
      }
    }
    if (isAurora) {
      ctx.fillStyle = "rgba(87,182,152,.1)";
      ctx.fillRect(0, 0, WIDTH, 96);
      for (let x = 0; x < WIDTH; x += 12) {
        const height = 22 + Math.round((Math.sin(x / 58 + this.elapsed * .35) + 1) * 17);
        pixelRect(ctx, x, 28, 12, height, x % 36 ? "rgba(113,216,177,.12)" : "rgba(165,134,219,.11)");
      }
    }
    this.particles.forEach((particle, index) => {
      particle.y += particle.speed * deltaSeconds * (isSnow ? .65 : 1.2);
      particle.x += Math.sin(this.elapsed + particle.phase) * deltaSeconds * (isDust ? 18 : 5);
      if (particle.y > HEIGHT + 5) { particle.y = -5; particle.x = (index * 83) % WIDTH; }
      if (particle.x > WIDTH) particle.x = 0;
      if (particle.x < 0) particle.x = WIDTH;
      ctx.fillStyle = isDust ? "rgba(250,205,130,.45)" : isSnow ? "rgba(255,255,245,.75)" : isRain ? "rgba(174,213,219,.5)" : "rgba(206,172,239,.58)";
      const size = 2 + (index % 3);
      if (isRain) pixelRect(ctx, particle.x, particle.y, 2, size * 3, ctx.fillStyle);
      else pixelRect(ctx, particle.x, particle.y, isDust ? size * 2 : size, size, ctx.fillStyle);
    });
  }

  drawDaylight(ctx, state) {
    const hour = state.minute / 60;
    let darkness = 0;
    let color = "31,35,66";
    if (hour < 5 || hour >= 22) darkness = .43;
    else if (hour < 7) { darkness = (7 - hour) / 2 * .27; color = "81,58,83"; }
    else if (hour >= 18) { darkness = Math.min(.43, (hour - 18) / 4 * .43); color = "44,38,75"; }
    if (darkness > 0) {
      ctx.fillStyle = `rgba(${color},${darkness})`;
      ctx.fillRect(0, 0, WIDTH, HEIGHT);
      if (hour >= 21 || hour < 5) {
        for (let index = 0; index < 32; index += 1) {
          const x = hashString(`night-star-x-${index}`) % WIDTH;
          const y = hashString(`night-star-y-${index}`) % 118;
          const flicker = Math.sin(this.elapsed * 1.5 + index) > .5;
          pixelRect(ctx, x, y, flicker ? 2 : 1, flicker ? 2 : 1, "rgba(255,238,180,.45)");
        }
      }
    }
    if ((hour >= 5.2 && hour < 7.2) || (hour >= 17 && hour < 19.4)) {
      const progress = hour < 8 ? (hour - 5.2) / 2 : (hour - 17) / 2.4;
      ctx.fillStyle = `rgba(235,142,72,${Math.sin(progress * Math.PI) * .105})`;
      ctx.fillRect(0, 0, WIDTH, HEIGHT);
    }
  }

  drawBorder(ctx, palette) {
    pixelRect(ctx, 0, 0, WIDTH, 5, shade(palette.edge, -25));
    pixelRect(ctx, 0, HEIGHT - 5, WIDTH, 5, shade(palette.edge, -25));
    pixelRect(ctx, 0, 0, 5, HEIGHT, shade(palette.edge, -25));
    pixelRect(ctx, WIDTH - 5, 0, 5, HEIGHT, shade(palette.edge, -25));
    pixelRect(ctx, 5, 5, WIDTH - 10, 2, shade(palette.edge, 20));
    pixelRect(ctx, 5, HEIGHT - 7, WIDTH - 10, 2, shade(palette.edge, 8));
    pixelRect(ctx, 5, 5, 2, HEIGHT - 10, shade(palette.edge, 20));
    pixelRect(ctx, WIDTH - 7, 5, 2, HEIGHT - 10, shade(palette.edge, 8));
  }
}

export const CANVAS_SIZE = { width: WIDTH, height: HEIGHT };
