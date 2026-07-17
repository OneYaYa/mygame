import AIService from "./ai.js";
import Game from "./game.js";

function validateContent(world, maps) {
  if (!world?.game || !Array.isArray(world.npcs) || world.npcs.length !== 7) throw new Error("world.json 必须包含游戏配置与七名居民");
  if (!Array.isArray(maps?.regions) || maps.regions.length < 1 || !Array.isArray(maps?.places)) throw new Error("maps.json 缺少 regions 或 places");
  const ids = new Set([...maps.regions, ...maps.places].map((scene) => scene.id));
  ["town", "inn-yard", "chapel-hill", "photo-lane", "archive-lane", "harbor", "clock-basement", "hidden-darkroom", "low-tide-cave"].forEach((id) => {
    if (!ids.has(id)) throw new Error(`地图缺少关键场景：${id}`);
  });
  const npcIds = new Set(world.npcs.map((npc) => npc.id));
  ["arthur", "beatrice", "conrad", "dorothea", "elias", "florence", "ada"].forEach((id) => {
    if (!npcIds.has(id)) throw new Error(`剧情缺少居民：${id}`);
  });
  return {
    ...world,
    regions: maps.regions,
    places: maps.places,
    story_context: world.storyContext,
  };
}

function showFatal(error) {
  console.error(error);
  const loading = document.getElementById("loading-screen");
  loading.innerHTML = `<div style="max-width:620px;padding:32px;text-align:center;color:#d9c89f"><h1 style="font-family:Georgia,serif;font-weight:400">THE CLOCK FAILED TO START</h1><p style="line-height:1.8;color:#a99f88">${String(error?.message || error)}</p><p style="font-size:11px;color:#687875">请在 mygame_new 目录运行 <code>python server.py</code>，不要直接双击 index.html。</p></div>`;
}

async function boot() {
  try {
    const [worldResponse, mapsResponse] = await Promise.all([
      fetch("./data/world.json", { cache: "no-store" }),
      fetch("./data/maps.json", { cache: "no-store" }),
    ]);
    if (!worldResponse.ok) throw new Error(`world.json 读取失败：HTTP ${worldResponse.status}`);
    if (!mapsResponse.ok) throw new Error(`maps.json 读取失败：HTTP ${mapsResponse.status}`);
    const content = validateContent(await worldResponse.json(), await mapsResponse.json());
    const ai = new AIService({ timeoutMs: 12000 });
    const game = new Game(content, ai);
    window.__TIME_ECHO__ = { game, content, ai };
    game.initialize();
    // Local visual QA shortcut: useful for checking any large scene with a
    // headless browser without adding debug buttons to the actual title menu.
    const params = new URLSearchParams(window.location.search);
    if (["scene", "puzzle", "dialogue", "ending"].includes(params.get("qa"))) {
      game.newGame();
      game.ui.closeModal("prologue-modal", false);
      const requested = params.get("place");
      const scene = content.regions.concat(content.places).find((item) => item.id === requested);
      if (scene) {
        game.state.placeId = scene.id;
        game.state.regionId = scene.regionId || scene.id;
        game.state.player.x = Number(scene.spawn?.x ?? scene.width / 2 ?? 384);
        game.state.player.y = Number(scene.spawn?.y ?? scene.height * .72 ?? 340);
        game.ui.update(game.state);
        game.ui.showBanner(scene);
      }
      if (params.get("qa") === "puzzle") game.ui.openPuzzle(params.get("type") || "master", game.state, () => {});
      if (params.get("qa") === "dialogue") {
        const npc = content.npcs.find((item) => item.id === (params.get("npc") || "arthur"));
        if (npc) game.openConversation(npc);
      }
      if (params.get("qa") === "ending") game.ui.showEnding(params.get("id") === "surface" ? "surface" : "true");
    }
    ai.checkBackend().catch(() => {});
  } catch (error) {
    showFatal(error);
  }
}

boot();
