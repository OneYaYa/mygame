import AIService from "./ai.js";
import { Game } from "./game.js";
import { initTitleScene } from "./title-scene.js";

function validateContent(content) {
  const requiredArrays = ["timelines", "regions", "npcs", "events", "endings"];
  if (!content || typeof content !== "object") throw new Error("世界数据不是有效对象");
  requiredArrays.forEach((key) => {
    if (!Array.isArray(content[key]) || !content[key].length) throw new Error(`世界数据缺少 ${key}`);
  });
  const regionIds = new Set(content.regions.map((region) => region.id));
  if (regionIds.size !== content.regions.length) throw new Error("地图 ID 存在重复");
  const places = Array.isArray(content.places) ? content.places : [];
  const placeIds = new Set(places.map((place) => place.id));
  if (placeIds.size !== places.length) throw new Error("室内地点 ID 存在重复");
  places.forEach((place) => {
    if (!place.id || !regionIds.has(place.regionId)) throw new Error(`地点 ${place.id || "(未命名)"} 指向未知地区 ${place.regionId}`);
    if (Number(place.width || 0) < 768 || Number(place.height || 0) < 480) throw new Error(`地点 ${place.id} 小于游戏视口`);
  });
  const validPlaceIds = new Set([...regionIds, ...placeIds]);
  [...content.regions, ...places].forEach((scene) => {
    if (Number(scene.width || 768) < 768 || Number(scene.height || 480) < 480) throw new Error(`地图 ${scene.id} 小于游戏视口`);
    (scene.portals || []).forEach((portal) => {
      const target = portal.target || {};
      if (!regionIds.has(target.regionId)) throw new Error(`出口 ${scene.id}/${portal.id} 指向未知地区 ${target.regionId}`);
      if (!validPlaceIds.has(target.placeId || target.regionId)) throw new Error(`出口 ${scene.id}/${portal.id} 指向未知地点 ${target.placeId}`);
    });
  });
  content.npcs.forEach((npc) => {
    const regionId = npc.regionId || npc.region;
    if (!regionIds.has(regionId)) throw new Error(`NPC ${npc.id} 指向未知地图 ${regionId}`);
    (npc.schedule || []).forEach((slot) => {
      const slotPlaceId = slot.placeId || slot.regionId || regionId;
      if (!validPlaceIds.has(slotPlaceId)) throw new Error(`NPC ${npc.id} 的日程指向未知地点 ${slotPlaceId}`);
    });
  });
  return content;
}

function mergeMapData(world, maps) {
  if (!maps || typeof maps !== "object" || !maps.regions || !Array.isArray(maps.places)) {
    throw new Error("地图数据不是有效对象");
  }
  const layouts = maps.regions;
  world.regions = world.regions.map((region) => {
    const layout = layouts[region.id];
    if (!layout) throw new Error(`地图数据缺少 ${region.id}`);
    return { ...region, ...layout, palette: { ...(region.palette || {}), ...(layout.palette || {}) } };
  });
  world.places = maps.places;
  world.mapSchemaVersion = Number(maps.schemaVersion || 1);
  return world;
}

function showFatalError(error) {
  console.error(error);
  document.getElementById("loading-screen").innerHTML = `
    <div style="max-width:620px;padding:2rem;text-align:center">
      <h1 style="color:#f0bd62">世界线编织失败</h1>
      <p style="line-height:1.8">${String(error.message || error)}</p>
      <p style="color:#a99fab;font-size:.8rem">请确认通过 <code>python server.py</code> 启动，并检查 <code>data/world.json</code> 与 <code>data/maps.json</code>。</p>
    </div>`;
}

async function boot() {
  try {
    initTitleScene();
    const [worldResponse, mapsResponse] = await Promise.all([
      fetch("./data/world.json", { cache: "no-store" }),
      fetch("./data/maps.json", { cache: "no-store" }),
    ]);
    if (!worldResponse.ok) throw new Error(`无法读取世界数据（HTTP ${worldResponse.status}）`);
    if (!mapsResponse.ok) throw new Error(`无法读取地图数据（HTTP ${mapsResponse.status}）`);
    const content = validateContent(mergeMapData(await worldResponse.json(), await mapsResponse.json()));
    const ai = new AIService({ timeoutMs: 12000 });
    const game = new Game(content, ai);
    window.__EMBER_ECHOES__ = { game, content, ai };
    await game.initialize();
    const params = new URLSearchParams(window.location.search);
    const requestedTimeline = params.get("timeline");
    const requestedMode = params.get("mode") === "observer" ? "observer" : "player";
    if (requestedTimeline && content.timelines.some((timeline) => timeline.id === requestedTimeline)) {
      game.startNewGame(requestedTimeline, requestedMode);
    }
  } catch (error) {
    showFatalError(error);
  }
}

boot();
