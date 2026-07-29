import { deepClone, formatTime } from "./utils.js";

export const LOOP_START_MINUTE = 6 * 60;
export const LOOP_GAME_MINUTES = 24 * 60;
export const LOOP_REAL_SECONDS = 12 * 60;
export const GAME_MINUTES_PER_REAL_SECOND = LOOP_GAME_MINUTES / LOOP_REAL_SECONDS;
// 循环第 1435 分钟触发逆向白线 = 起点 06:00 + 23h55m → HUD 时钟显示 05:55（次日）
export const RESET_WARNING_AT = LOOP_GAME_MINUTES - 5;

const REPAIR_IDS = ["master", "chapel", "tide"];
const PHOTO_ITEMS = new Set(["unfinished_portrait", "fixed_portrait"]);

function initialNpcState(npc) {
  return {
    regionId: npc.regionId || "town",
    placeId: npc.placeId || npc.regionId || "town",
    x: Number(npc.x || 384),
    y: Number(npc.y || 280),
    targetX: Number(npc.x || 384),
    targetY: Number(npc.y || 280),
    facing: "down",
    relationshipLevel: "stranger",
    evidenceLevel: "none",
    memoryPressure: "stable",
    actionState: "unavailable",
    memories: [],
  };
}

export function createInitialState(content, persistent = null) {
  const meta = persistent || {};
  const state = {
    version: 1,
    seed: Number(meta.seed || Math.floor(Math.random() * 0x7fffffff)),
    rngState: Number(meta.rngState || 73129),
    mode: "player",
    regionId: "town",
    placeId: "player-room",
    player: { x: 384, y: 370, facing: "down", present: true },
    loopCount: Number(meta.loopCount || 0),
    loopElapsed: 0,
    minute: LOOP_START_MINUTE,
    dayLabel: "SATURDAY",
    speed: 1,
    weather: "晴",
    flags: { repair_orders_read: false },
    repairs: { master: false, chapel: false, tide: false },
    inventory: {},
    evidence: {},
    knowledge: deepClone(meta.knowledge || {}),
    photos: deepClone(meta.photos || {}),
    journal: deepClone(meta.journal || []),
    npcNotes: deepClone(meta.npcNotes || {}),
    npcs: Object.fromEntries((content.npcs || []).map((npc) => [npc.id, initialNpcState(npc)])),
    conversationOpen: false,
    cinematic: null,
    endingId: null,
    lastLocation: null,
  };
  if (state.photos.unfinished_portrait) state.inventory.unfinished_portrait = 1;
  if (state.photos.fixed_portrait) state.inventory.fixed_portrait = 1;
  // Ada is never rendered merely because the player remembers her.
  if (state.npcs.ada) state.npcs.ada.placeId = "erased-space";
  addJournal(state, "loop", state.loopCount ? `第 ${state.loopCount + 1} 次醒来。床边的钟仍是星期六 06:00。` : "星期六 06:00，在湖畔旅店八号房醒来。", true);
  syncWorldFlags(state);
  syncNpcSchedules(state, content);
  return state;
}

export function normalizeLoadedState(raw, content) {
  if (!raw || typeof raw !== "object") return createInitialState(content);
  const state = createInitialState(content, raw);
  Object.assign(state, raw);
  state.player = { x: 384, y: 370, facing: "down", present: true, ...(raw.player || {}) };
  state.flags = { ...(raw.flags || {}) };
  state.repairs = { master: false, chapel: false, tide: false, ...(raw.repairs || {}) };
  state.inventory = { ...(raw.inventory || {}) };
  state.evidence = { ...(raw.evidence || {}) };
  state.knowledge = { ...(raw.knowledge || {}) };
  state.photos = { ...(raw.photos || {}) };
  state.npcs = { ...state.npcs, ...(raw.npcs || {}) };
  syncClock(state);
  syncWorldFlags(state);
  syncNpcSchedules(state, content);
  return state;
}

export function addJournal(state, type, text, persistent = true) {
  if (!text) return;
  const entry = {
    id: `${state.loopCount}:${Math.floor(state.loopElapsed)}:${state.journal.length}`,
    loop: state.loopCount + 1,
    stamp: `${state.dayLabel} ${formatTime(state.minute)}`,
    type,
    text,
    persistent,
  };
  const duplicate = state.journal.slice(-4).some((item) => item.text === text);
  if (!duplicate) state.journal.push(entry);
  if (state.journal.length > 180) state.journal.splice(0, state.journal.length - 180);
}

export function addItem(state, itemId, amount = 1) {
  state.inventory[itemId] = Math.max(0, Number(state.inventory[itemId] || 0) + amount);
  return state.inventory[itemId];
}

export function hasItem(state, itemId) {
  return Number(state.inventory[itemId] || 0) > 0;
}

export function addEvidence(state, evidenceId, note = "") {
  if (!state.evidence[evidenceId]) {
    state.evidence[evidenceId] = true;
    state.knowledge[evidenceId] = true;
    if (note) addJournal(state, "evidence", note);
  }
}

export function learn(state, knowledgeId, note = "") {
  if (!state.knowledge[knowledgeId]) {
    state.knowledge[knowledgeId] = true;
    if (note) addJournal(state, "knowledge", note);
  }
}

export function repairCount(state) {
  return REPAIR_IDS.filter((id) => state.repairs[id]).length;
}

export function syncClock(state) {
  const elapsed = Math.max(0, Math.min(LOOP_GAME_MINUTES, Number(state.loopElapsed || 0)));
  state.minute = (LOOP_START_MINUTE + elapsed) % LOOP_GAME_MINUTES;
  state.dayLabel = elapsed < 18 * 60 ? "SATURDAY" : "SUNDAY";
}

export function syncWorldFlags(state) {
  const elapsed = Number(state.loopElapsed || 0);
  state.flags.low_tide = elapsed >= 20 * 60 && elapsed < 21 * 60;
  state.flags.basement_open = repairCount(state) === REPAIR_IDS.length;
  state.flags.hidden_darkroom_open = Boolean(
    state.flags.counterweight_raised
    && state.flags.light_route_inn_studio
    && hasItem(state, "unnumbered_key"),
  );
  state.flags.slot_seven_filled = Boolean(state.flags.slot_seven_filled || state.photos.fixed_portrait_installed);
}

export function scenePausesTime(state) {
  return ["hidden-darkroom", "low-tide-cave"].includes(state.placeId);
}

export function advanceWorld(state, content, deltaRealSeconds) {
  const events = [];
  if (state.endingId || state.cinematic || state.speed <= 0) return events;
  const previous = Number(state.loopElapsed || 0);
  const modalScale = state.conversationOpen ? 0.25 : 1;
  const sceneScale = scenePausesTime(state) ? 0 : 1;
  state.loopElapsed = Math.min(
    LOOP_GAME_MINUTES,
    previous + Math.max(0, Number(deltaRealSeconds || 0)) * GAME_MINUTES_PER_REAL_SECOND * state.speed * modalScale * sceneScale,
  );
  syncClock(state);
  syncWorldFlags(state);
  syncNpcSchedules(state, content);
  if (previous < RESET_WARNING_AT && state.loopElapsed >= RESET_WARNING_AT) events.push({ type: "reset-warning" });
  if (previous < LOOP_GAME_MINUTES && state.loopElapsed >= LOOP_GAME_MINUTES) events.push({ type: "loop-reset" });
  return events;
}

export function advanceTravel(state, content, realSeconds) {
  if (scenePausesTime(state)) return [];
  const previousConversation = state.conversationOpen;
  state.conversationOpen = false;
  const events = advanceWorld(state, content, Number(realSeconds || 0));
  state.conversationOpen = previousConversation;
  return events;
}

export function resetLoop(state, content) {
  const persistent = {
    seed: state.seed,
    rngState: state.rngState,
    loopCount: state.loopCount + 1,
    knowledge: state.knowledge,
    photos: state.photos,
    journal: state.journal.filter((entry) => entry.persistent !== false),
    npcNotes: state.npcNotes,
  };
  return createInitialState(content, persistent);
}

function moveNpc(state, npcId, placeId, x, y, facing = "down") {
  if (npcId === 'ada' && placeId === 'erased-space' && state.flags.hidden_darkroom_open) {
    placeId = 'hidden-darkroom';
    x = 560;
    y = 280;
    facing = 'left';
  }
  const npc = state.npcs[npcId];
  if (!npc) return;
  const changedPlace = npc.placeId !== placeId;
  npc.regionId = "town";
  npc.placeId = placeId;
  if (changedPlace || !Number.isFinite(npc.x) || !Number.isFinite(npc.y)) {
    npc.x = x;
    npc.y = y;
  }
  npc.targetX = x;
  npc.targetY = y;
  npc.facing = facing;
}

export function syncNpcSchedules(state) {
  const t = Number(state.loopElapsed || 0);
  const wander = Math.floor(t / 35) % 2 ? 22 : -18;
  // Everyone has a credible workplace and a small late-night routine. They never wait in a generic outdoor pen.
  moveNpc(state, "dorothea", t < 16 * 60 ? "inn-lobby" : "inn-upstairs", t < 16 * 60 ? 430 + wander : 470, t < 16 * 60 ? 275 : 335);
  moveNpc(state, "arthur", t < 17 * 60 ? "clock-cabin" : "inn-upstairs", t < 17 * 60 ? 385 + wander : 130, t < 17 * 60 ? 300 : 335);
  moveNpc(state, "beatrice", t < 17 * 60 + 30 ? "chapel-interior" : "inn-upstairs", t < 17 * 60 + 30 ? 545 : 240, t < 17 * 60 + 30 ? 320 + wander * .5 : 335);
  moveNpc(state, "conrad", t < 19 * 60 ? "harbor" : "harbor-control", t < 19 * 60 ? 770 + wander * 2 : 560, t < 19 * 60 ? 465 : 315);
  moveNpc(state, "elias", t < 18 * 60 ? "photo-studio" : "inn-upstairs", t < 18 * 60 ? 430 + wander : 590, t < 18 * 60 ? 315 : 335);
  moveNpc(state, "florence", t < 18 * 60 ? "archive-room" : "inn-upstairs", t < 18 * 60 ? 430 + wander : 700, t < 18 * 60 ? 270 : 335);
  if (state.flags.slot_seven_filled && state.placeId === "hidden-darkroom") moveNpc(state, "ada", "hidden-darkroom", 560, 280);
  else if (state.npcs.ada) state.npcs.ada.placeId = "erased-space";
}

function ruleMet(rule, state) {
  if (!rule) return true;
  const value = rule.value ?? true;
  if (rule.type === "flag") return Boolean(state.flags?.[rule.id]) === Boolean(value);
  if (rule.type === "repair") return Boolean(state.repairs?.[rule.id]) === Boolean(value);
  if (rule.type === "item") return hasItem(state, rule.id) === Boolean(value);
  if (rule.type === "evidence") return Boolean(state.evidence?.[rule.id]) === Boolean(value);
  if (rule.type === "knowledge") return Boolean(state.knowledge?.[rule.id]) === Boolean(value);
  if (rule.type === "photo") return Boolean(state.photos?.[rule.id]) === Boolean(value);
  if (rule.type === "repairCount") return repairCount(state) >= Number(rule.value || 0);
  if (rule.type === "timeBetween") return state.loopElapsed >= rule.start && state.loopElapsed < rule.end;
  return true;
}

export function requirementsMet(subject, state) {
  const rules = subject?.requirements || [];
  const missing = rules.filter((rule) => !ruleMet(rule, state));
  return { ok: missing.length === 0, missing };
}

export function getStoryLandmarks(state, _content, scene) {
  if (!scene) return [];
  const landmarks = [];
  if (scene.id === "town" && state.repairs.master) {
    landmarks.push({ id: "master_clock_repaired_glow", type: "clock", label: "重新运转的主钟", description: "秒针已经恢复，却每隔七拍迟疑一次。", interactive: true, x: 537, y: 118, w: 78, h: 76, layer: "foreground" });
  }
  if (scene.id === "harbor" && state.flags.low_tide) {
    landmarks.push({ id: "low_tide_foam", type: "water", x: 1085, y: 454, w: 125, h: 52, layer: "ground", collision: false });
  }
  if (scene.id === "photo-studio" && state.flags.counterweight_raised) {
    landmarks.push({ id: "raised_counterweight_chain", type: "tool", label: "升起的主钟配重", description: "西墙露出了原先被压住的银盐门框。", interactive: true, x: 38, y: 118, w: 48, h: 76, layer: "wall" });
  }
  if (scene.id === "clock-basement" && state.flags.slot_seven_filled) {
    landmarks.push({ id: "ada_fixed_portrait_display", type: "portrait", label: "艾达·罗文的见证肖像", description: "七枚信号灯第一次同时保持稳定。", interactive: true, x: 635, y: 122, w: 48, h: 64, layer: "foreground", color: "#d7b568" });
  }
  return landmarks;
}

export function markRepair(state, repairId) {
  if (!REPAIR_IDS.includes(repairId) || state.repairs[repairId]) return false;
  state.repairs[repairId] = true;
  state.flags[`${repairId}_repaired`] = true;
  const names = { master: "广场主钟", chapel: "礼拜堂六声钟", tide: "港口潮汐钟" };
  addJournal(state, "repair", `${names[repairId]}恢复运转。它没有解决时间异常，却打开了一条新的调查路径。`);
  syncWorldFlags(state);
  return true;
}

export function identifyPossessedTools(state) {
  const identified = [];
  const mapping = {
    installation_wrench: ["wrench_identified", "安装扳手：母钟原设计的紧急制动扳手，可安全断开主擒纵，而不是锁死主轮。"],
    silver_tuning_fork: ["fork_identified", "银色音叉：第七锤的专用校准器。"],
    spare_lens: ["lens_identified", "双槽备用镜片：灯塔的双路维护镜，可同时建立主、备用光路。"],
    flashlight: ["flashlight_identified", "防水手电：普通洞穴照明工具，没有协议用途。"],
  };
  Object.entries(mapping).forEach(([itemId, [flag, text]]) => {
    if (hasItem(state, itemId) && !state.flags[flag]) {
      state.flags[flag] = true;
      learn(state, flag, text);
      identified.push(text);
    }
  });
  return identified;
}

export function getNpcActions(npcId, state) {
  if (npcId === 'ada') {
    const actions = [{ id: 'ask_work', label: '问她现在能记住什么' }];
    const recordReady = state.knowledge.ada_identity && state.evidence.master_ar_record && state.evidence.chapel_ar_log;
    const residenceReady = state.knowledge.ada_residence_anchor && hasItem(state, 'unnumbered_key');
    const faceReady = state.knowledge.portrait_face_anchor && hasItem(state, 'unfinished_portrait');
    if (recordReady && !state.flags.ada_name_anchored) actions.push({ id: 'anchor_ada_name', label: '用两份 A.R. 记录确认她的姓名' });
    if (residenceReady && !state.flags.ada_residence_anchored) actions.push({ id: 'anchor_ada_residence', label: '用七号房钥匙确认她的住处' });
    if (recordReady && !state.flags.ada_duty_anchored) actions.push({ id: 'anchor_ada_duty', label: '用中央校准记录确认她的职责' });
    if (faceReady && !state.flags.ada_face_anchored) actions.push({ id: 'anchor_ada_face', label: '让她认领底片中的面孔' });
    actions.push({ id: 'ask_ada_truth', label: '问她镇子为什么需要第七位见证人' });
    return actions;
  }
  const actions = [{ id: "ask_work", label: "问他今天在做什么" }];
  if (npcId === "dorothea") {
    actions.push({ id: "ask_rooms", label: "问登记簿为什么跳过七号房" });
    if (hasItem(state, "room7_tag") && state.evidence.ledger_gap && !hasItem(state, "unnumbered_key")) actions.push({ id: "exchange_room7_key", label: "把七号房钥匙牌放在柜台上" });
  }
  if (npcId === "arthur") {
    if (state.repairs.master && !state.evidence.master_ar_record) actions.push({ id: "ask_master_record", label: "请他解释七信号控制台" });
    if (state.repairs.master && state.evidence.brake_interface && state.flags.wrench_identified && hasItem(state, "installation_wrench") && !state.flags.arthur_stops_clock) {
      actions.push({ id: "commit_stop_clock", label: "用接口和扳手证明：必须由他亲手停钟" });
    }
  }
  if (npcId === "beatrice") {
    if (state.repairs.chapel) actions.push({ id: "ask_six_bells", label: "问第七锤为什么独立存在" });
    if (state.repairs.chapel && state.evidence.master_ar_record && state.flags.fork_identified && hasItem(state, "silver_tuning_fork") && !state.flags.beatrice_rings_seventh) {
      actions.push({ id: "commit_seventh_bell", label: "出示记录与音叉，说明七声是机械终止确认，请她执行" });
    }
  }
  if (npcId === "conrad") {
    if (state.repairs.tide && !hasItem(state, "flashlight")) actions.push({ id: "receive_flashlight", label: "问最低潮时露出的维护洞穴" });
    if (state.flags.lens_identified && state.evidence.chapel_ar_log && hasItem(state, "spare_lens")) {
      if (!state.flags.light_route_chapel_square) actions.push({ id: "route_surface_light", label: "出示双路镜与安装记录，说明副光不熄主航道，请他导向礼拜堂与广场" });
      if (state.evidence.inn_roof_reflector && hasItem(state, "spare_lens") && !state.flags.light_route_inn_studio) actions.push({ id: "route_darkroom_light", label: "出示双路镜与屋顶光路图，说明副光不熄主航道，请他导向照相馆西墙" });
    }
  }
  if (npcId === "elias" && hasItem(state, "cave_negative") && !state.photos.unfinished_portrait) {
    actions.push({ id: "develop_cave_negative", label: "请他显影洞穴里找到的底片" });
  }
  if (npcId === "florence") {
    const toolActions = [
      ["identify_wrench", "installation_wrench", "wrench_identified", "把安装扳手放到索引卡旁鉴定"],
      ["identify_fork", "silver_tuning_fork", "fork_identified", "把银色音叉放到索引卡旁鉴定"],
      ["identify_lens", "spare_lens", "lens_identified", "把双槽备用镜放到索引卡旁鉴定"],
      ["identify_flashlight", "flashlight", "flashlight_identified", "把防水手电放到索引卡旁鉴定"],
    ];
    toolActions.forEach(([actionId, itemId, flagId, label]) => {
      if (hasItem(state, itemId) && !state.flags[flagId]) actions.push({ id: actionId, label });
    });
    if (state.evidence.master_ar_record && state.evidence.chapel_ar_log && !state.flags.ar_records_compared && !state.knowledge.ada_identity) {
      actions.push({ id: "compare_ar_records", label: "把两份 A.R. 原件放在桌上核验" });
    }
    if (state.evidence.master_ar_record && state.evidence.chapel_ar_log && state.photos.unfinished_portrait && !state.knowledge.ada_identity) {
      actions.push({ id: "cross_reference_ada", label: "把两份 A.R. 记录和残缺肖像并排核验" });
    }
    if (!state.evidence.inn_roof_reflector || !state.knowledge.return_exposure) actions.push({ id: "research_return_exposure", label: "查找“回返曝光”和旅店屋顶光路" });
  }
  if (npcId === "ada") actions.push({ id: "ask_ada_truth", label: "问她镇子为什么需要第七位见证人" });
  return actions;
}

export function applyNpcAction(npcId, actionId, state) {
  if (npcId === 'ada') {
    const answer = { speaker: 'ada', text: '', puzzle: null };
    if (actionId === 'ask_work') {
      answer.text = state.flags.ada_duty_anchored
        ? '我是中央校准员，负责让光、节拍和钟声共同确认一天结束。我的记录被删除后，这项确认就再也无法完整发生。'
        : '我记得自己在这里工作过，也记得母钟、礼拜堂和灯塔，可职位和具体职责都断开了。现在我不能替缺失的记录补答案。';
    }
    else if (actionId === 'anchor_ada_name' && state.knowledge.ada_identity && state.evidence.master_ar_record && state.evidence.chapel_ar_log) {
      state.flags.ada_name_anchored = true;
      answer.text = 'Ada Rowan。不是缩写，也不是档案员补出的猜测。那是我在两份独立维修记录上写下的名字。';
      addJournal(state, 'identity', '身份锚点 1/4：两份独立 A.R. 记录共同确认 Ada Rowan 的姓名。');
    } else if (actionId === 'anchor_ada_residence' && state.knowledge.ada_residence_anchor && hasItem(state, 'unnumbered_key')) {
      state.flags.ada_residence_anchored = true;
      answer.text = '七号房。窗框朝湖，夜里主钟的影子会落到床尾。钥匙磨损的位置，是我每天握住它留下的。';
      addJournal(state, 'identity', '身份锚点 2/4：七号房缺失登记、钥匙牌与无编号钥匙共同确认 Ada 的住处。');
    } else if (actionId === 'anchor_ada_duty' && state.knowledge.ada_identity && state.evidence.master_ar_record && state.evidence.chapel_ar_log) {
      state.flags.ada_duty_anchored = true;
      answer.text = '中央校准员，第七见证人。我不负责让时间倒退；我负责确认七个人都能一起继续。';
      addJournal(state, 'identity', '身份锚点 3/4：主钟与礼拜堂记录共同确认 Ada 的职责。');
    } else if (actionId === 'anchor_ada_face' && state.knowledge.portrait_face_anchor && hasItem(state, 'unfinished_portrait')) {
      state.flags.ada_face_anchored = true;
      answer.text = '底片里站在主钟前的人是我。请保留重影——那不是瑕疵，是每一次被删除后仍然留下的边缘。';
      addJournal(state, 'identity', '身份锚点 4/4：洞穴底片与 Ada 的亲自认领共同确认她的面孔。');
    } else if (actionId === 'ask_ada_truth') {
      const anchored = ['ada_name_anchored', 'ada_residence_anchored', 'ada_duty_anchored', 'ada_face_anchored'].every((flag) => state.flags[flag]);
      answer.text = anchored
        ? '地下协议没有坏。镇子每次都选择更容易的星期日：让六个人继续，让第七个人从共同记忆里消失。白色旋钮保留的是七个人都在场的时间。'
        : '我能解释协议，但现在每句话都会从不完整的身份旁边滑过去。先用你真正带来的证据，让名字、住处、职责和面孔都指向我。';
    } else answer.text = '这段记忆还没有足够的本轮证据固定。不要替我猜；把能共同核验的东西带来。';
    return answer;
  }
  const response = { speaker: npcId, text: "", puzzle: null };
  if (actionId === "ask_work") {
    const lines = {
      arthur: "母钟里有三枚错位齿轮，三条红色标记全部朝上才算修复。维修舱下方还有旧校准设施，但入口要等三座钟都恢复才会解锁。",
      beatrice: "礼钟本应有六声。现在第四枚擒纵销不见了，而第七锤仍锁在楼上。",
      conrad: "先读三根系船柱的水线，再调潮汐盘。别拿猜测和湖面赌。",
      dorothea: "早餐在炉边。三份维修单都送到了八号房——是的，一直都是八号房。",
      elias: "我只相信能重复显影的东西。带来底片，我会查重影、反差和反射。",
      florence: "一份记录只能证明它自己存在。要恢复一个被删掉的名字，至少需要两个独立来源和一件影像证据。",
      ada: "你已经不是第一次走到这里。不同的是，这一次你带来的是我的完整身份，而不只是一个名字。",
    };
    response.text = lines[npcId] || "他正在完成自己的日常工作。";
  } else if (npcId === "dorothea" && actionId === "ask_rooms") {
    response.text = state.evidence.ledger_gap
      ? "我看见那道缺口。可若真有七号房，为什么我会连铺床的习惯都想不起来？拿一件属于那间房的东西给我。"
      : "登记簿在柜台上。请先亲眼看那一页；我不想用你的说法替代它。";
  } else if (npcId === "dorothea" && actionId === "exchange_room7_key" && hasItem(state, "room7_tag") && state.evidence.ledger_gap) {
    addItem(state, "unnumbered_key");
    state.flags.room7_key_verified = true;
    learn(state, "ada_residence_anchor", "七号钥匙牌与旅店缺失登记行共同证明：被删去的人住在七号房。多萝西娅交出了无编号钥匙。");
    response.text = "这块铜牌的磨损……我记得每天擦过它。柜台后的钥匙不是‘没有房间’，是我们把号码忘了。你拿去吧。";
  } else if (npcId === "arthur" && actionId === "ask_master_record") {
    addEvidence(state, "master_ar_record", "从修复后的主钟控制台抄下 A.R. 记录：七次连续击发确认终止。");
    response.text = "记录写的是“A.R.：七次连续击发确认终止”。它能证明七声是机械终止信号；A.R. 是谁、七路接口对应什么，这份记录本身不能确认。";
  } else if (npcId === "arthur" && actionId === "commit_stop_clock" && state.repairs.master && state.evidence.brake_interface && state.flags.wrench_identified && hasItem(state, "installation_wrench")) {
    state.flags.arthur_stops_clock = true;
    state.flags.counterweight_raised = true;
    addJournal(state, "commitment", "阿瑟确认紧急制动接口并亲手停下主钟；西侧配重随之升起。");
    response.text = "接口、档案型号和扳手都对得上。它会断开主擒纵，不是锁死主轮；安全操作由我负责。到时候由我停钟。西侧配重现在会保持升起。";
  } else if (npcId === "beatrice" && actionId === "ask_six_bells") {
    response.text = "六声用于日常报时。第七锤不参与普通报时，旧规只把它当作送终禁忌；我没有证据证明它真正用于什么。";
  } else if (npcId === "beatrice" && actionId === "commit_seventh_bell" && state.repairs.chapel && state.evidence.master_ar_record && state.flags.fork_identified && hasItem(state, "silver_tuning_fork")) {
    state.flags.beatrice_rings_seventh = true;
    addJournal(state, "commitment", "贝娅特丽斯核验终止记录与银音叉，答应在协议启动时敲响第七声。");
    response.text = "终止记录与校准器相符。我不喜欢这个答案，但我会亲手完成第七声，确保没有别人替我承担这项不可逆的决定。";
  } else if (npcId === "conrad" && actionId === "receive_flashlight" && state.repairs.tide) {
    addItem(state, "flashlight");
    learn(state, "low_tide_cave_known", "潮汐钟修复后，康拉德确认凌晨 02:00–03:00 港口东侧露出维护洞穴，并交出防水手电。");
    response.text = "潮汐盘现在可信了。02:00 到 03:00，灯塔脚下会露出旧维护洞。带上这支手电，潮回来前别在入口磨蹭。";
  } else if (npcId === "conrad" && actionId === "route_surface_light" && state.flags.lens_identified && state.evidence.chapel_ar_log && hasItem(state, "spare_lens")) {
    state.flags.light_route_chapel_square = true;
    state.flags.light_route_inn_studio = false;
    state.flags.conrad_routes_light = true;
    addJournal(state, "commitment", "康拉德按 A.R. 安装记录建立灯塔→礼拜堂→广场的主光路。");
    response.text = "记录、镜片和视线都吻合。主航道光保持不变；维修副光会经过礼拜堂反射器，再落到广场。";
  } else if (npcId === "conrad" && actionId === "route_darkroom_light" && state.flags.lens_identified && state.evidence.inn_roof_reflector && hasItem(state, "spare_lens")) {
    state.flags.light_route_inn_studio = true;
    state.flags.light_route_chapel_square = false;
    state.flags.conrad_routes_light = false;
    addJournal(state, "commitment", "康拉德用双路镜建立灯塔→旅店屋顶→照相馆西墙的备用光路。");
    response.text = "主光不动，维修副光经过旅店屋顶落到照相馆西墙。我现在把镜片锁进副槽。";
    syncWorldFlags(state);
  } else if (npcId === "elias" && actionId === "develop_cave_negative" && hasItem(state, "cave_negative")) {
    response.puzzle = "photo";
    response.text = "可以显影。但别急着猜人名：先查重影，再拉反差，最后确认湖面反射。三步次序错了，乳剂只会变成你想看见的样子。";
  } else if (npcId === "florence" && actionId.startsWith("identify_")) {
    const toolActions = {
      identify_wrench: ["installation_wrench", "wrench_identified", "安装扳手：母钟原设计的紧急制动扳手，可安全断开主擒纵，而不是锁死主轮。"],
      identify_fork: ["silver_tuning_fork", "fork_identified", "银色音叉：第七锤的专用校准器。"],
      identify_lens: ["spare_lens", "lens_identified", "双槽备用镜片：灯塔的双路维护镜，可分离维修副光。"],
      identify_flashlight: ["flashlight", "flashlight_identified", "防水手电：普通洞穴照明工具，没有协议用途。"],
    };
    const [itemId, flagId, text] = toolActions[actionId] || [];
    if (itemId && hasItem(state, itemId) && !state.flags[flagId]) {
      state.flags[flagId] = true;
      learn(state, flagId, text);
      response.text = text;
    }
  } else if (npcId === "florence" && actionId === "compare_ar_records" && state.evidence.master_ar_record && state.evidence.chapel_ar_log) {
    state.flags.ar_records_compared = true;
    addJournal(state, "evidence", "弗洛伦斯核验两份本轮 A.R. 原件：来源彼此独立，签署者相同；交叉核验仍缺一件影像证据。");
    response.text = "两份都是本轮原件，纸张来源和登记位置彼此独立，签名栏却都是 A.R.。这足以确认同一个人参与了主钟和礼拜堂安装，但还不足以补全姓名；交叉核验台还缺一件影像证据。";
  } else if (npcId === "florence" && actionId === "cross_reference_ada" && state.evidence.master_ar_record && state.evidence.chapel_ar_log && state.photos.unfinished_portrait) {
    state.flags.ar_records_compared = true;
    learn(state, "ada_identity", "两份 A.R. 维修记录与残缺肖像交叉核验：Ada Rowan，中央校准员，第七见证人。");
    response.text = "两个独立地点都由 A.R. 签字，肖像背面残留的字母位置一致。旧雇员索引补全为 Ada Rowan——中央校准员，第七席。现在这是结论，不是猜测。";
  } else if (npcId === "florence" && actionId === "research_return_exposure") {
    addEvidence(state, "inn_roof_reflector", "档案图纸证明旅店屋顶反射器可把备用光导向照相馆西墙。");
    learn(state, "return_exposure", "档案称回返曝光会重新投射最后一次有效记录，但没有说明记录的范围。");
    response.text = "档案把那种白光称为“回返曝光”：它会重新投射最后一次有效记录。这里没有说明“记录”指钟表读数、人员名单，还是整个镇子的状态。附图还标出旅店屋顶的维护反射器，它能照到照相馆西墙。";
  } else if (npcId === "ada" && actionId === "ask_ada_truth") {
    response.text = "地下协议不是坏掉了。镇子每次都按设计选择一个更容易的星期日：让六个人继续，让第七个人从所有共同记忆里消失。白色旋钮保留的是七个人都在场的时间。";
  }
  return response;
}

export function completePhotoDevelopment(state) {
  if (!hasItem(state, "cave_negative") || state.photos.unfinished_portrait) return false;
  state.photos.unfinished_portrait = true;
  addItem(state, "unfinished_portrait");
  learn(state, "portrait_face_anchor", "洞穴底片经过重影、反差、反射三步显影，得到一张带有 A.R. 缩写的未完成肖像。面孔可以作为身份定影锚点。");
  return true;
}

export function completeIdentityFixing(state) {
  const dialogueAnchorsReady = ['ada_name_anchored', 'ada_residence_anchored', 'ada_duty_anchored', 'ada_face_anchored'].every((flag) => state.flags[flag]);
  if (!dialogueAnchorsReady) return false;
  const ready = Boolean(
    state.knowledge.ada_identity
    && state.knowledge.ada_residence_anchor
    && state.knowledge.portrait_face_anchor
    && state.evidence.master_ar_record
    && state.evidence.chapel_ar_log
    && hasItem(state, "unfinished_portrait")
    && hasItem(state, "unnumbered_key"),
  );
  if (!ready || state.photos.fixed_portrait) return false;
  state.photos.fixed_portrait = true;
  addItem(state, "fixed_portrait");
  learn(state, "ada_fixed", "姓名、住处、职责和面孔四个身份锚点完成定影：Ada Rowan 的第七见证肖像不再随循环褪色。");
  syncNpcSchedules(state);
  return true;
}

export function installAdaPortrait(state) {
  if (!hasItem(state, "fixed_portrait")) return false;
  state.flags.slot_seven_filled = true;
  state.photos.fixed_portrait_installed = true;
  addJournal(state, "world", "艾达·罗文的定影肖像进入第七见证位。红色删除杆失去电源，白色继续旋钮从面板下弹出。");
  syncNpcSchedules(state);
  return true;
}

export function surfaceProtocolReady(state) {
  return Boolean(state.flags.conrad_routes_light && state.flags.arthur_stops_clock && state.flags.beatrice_rings_seventh);
}

export function describeMissingIdentityAnchors(state) {
  return [
    [state.flags.ada_name_anchored, '姓名：让 Ada 核验两份独立 A.R. 记录'],
    [state.flags.ada_residence_anchored, '住处：让 Ada 核验七号房登记链与无编号钥匙'],
    [state.flags.ada_duty_anchored, '职责：让 Ada 核验中央校准员与第七见证职责'],
    [state.flags.ada_face_anchored, '面孔：让 Ada 亲自认领显影底片中的面孔'],
  ].filter(([ok]) => !ok).map(([, label]) => label);
  const anchors = [
    [state.knowledge.ada_identity && state.evidence.master_ar_record && state.evidence.chapel_ar_log, "姓名与职责：两份本轮 A.R. 记录 + 档案交叉核验"],
    [state.knowledge.ada_residence_anchor && hasItem(state, "unnumbered_key"), "住处：七号钥匙牌 + 登记簿缺失行 + 无编号钥匙"],
    [state.knowledge.portrait_face_anchor && hasItem(state, "unfinished_portrait"), "面孔：洞穴底片的三步显影肖像"],
  ];
  return anchors.filter(([ok]) => !ok).map(([, label]) => label);
}
