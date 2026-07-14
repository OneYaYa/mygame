import { clamp, deepClone, formatStamp, getByPath, hashString, nextRandom } from "./utils.js";

export const METRIC_META = {
  food: { label: "粮食", color: "#d6a85e", icon: "穗" },
  water: { label: "水源", color: "#63afca", icon: "滴" },
  order: { label: "秩序", color: "#cb7771", icon: "冠" },
  hope: { label: "希望", color: "#82c99d", icon: "芽" },
  aether: { label: "星辉", color: "#a98ac8", icon: "星" },
};

export const FACTION_META = {
  crown: { label: "王冠议会", color: "#d17d69" },
  commons: { label: "众民同盟", color: "#7ebd8e" },
  keepers: { label: "守秘人", color: "#9481b8" },
  caravan: { label: "远途商队", color: "#d2a55f" },
};

const DEFAULT_METRICS = { food: 54, water: 52, order: 58, hope: 48, aether: 35 };
const DEFAULT_FACTIONS = { crown: 50, commons: 45, keepers: 35, caravan: 40 };
const SURVIVAL_METRICS = new Set(["food", "water", "order", "hope"]);
const DIFFICULTY_LABELS = ["简单", "普通", "困难"];
const REGION_ACTIONS = {
  capital: [
    { id: "patrol", label: "巡视街巷", effects: { order: .8, hope: -.15 }, faction: "crown" },
    { id: "petition", label: "倾听请愿", effects: { hope: .65, order: .15 }, faction: "commons" },
    { id: "archive", label: "查阅旧档", effects: { aether: .5 }, faction: "keepers" },
  ],
  farm: [
    { id: "cultivate", label: "照料作物", effects: { food: 1.05, hope: .12 }, faction: "commons" },
    { id: "irrigate", label: "疏通水渠", effects: { water: .7, food: .35 }, faction: "commons" },
    { id: "share", label: "分享收成", effects: { hope: .75, food: -.18 }, faction: "commons" },
  ],
  mansion: [
    { id: "negotiate", label: "斡旋宴席", effects: { order: .55, hope: .18 }, faction: "crown" },
    { id: "scheme", label: "交换密信", effects: { order: -.2, aether: .4 }, faction: "keepers" },
    { id: "patronage", label: "资助城民", effects: { food: .25, hope: .65 }, faction: "commons" },
  ],
  snow: [
    { id: "meltwater", label: "引导融雪", effects: { water: 1.05, aether: .12 }, faction: "keepers" },
    { id: "rescue", label: "搜寻旅人", effects: { hope: .75, order: .2 }, faction: "commons" },
    { id: "ward", label: "加固星辉封印", effects: { aether: -.65, order: .35 }, faction: "keepers" },
  ],
  desert: [
    { id: "trade", label: "组织商队", effects: { food: .5, water: .38 }, faction: "caravan" },
    { id: "excavate", label: "勘探遗迹", effects: { aether: .95, order: -.15 }, faction: "keepers" },
    { id: "guide", label: "护送旅人", effects: { hope: .55, water: -.1 }, faction: "caravan" },
  ],
};

const GENERIC_ACTIONS = [
  { id: "rest", label: "安静休息", effects: { hope: .15 } },
  { id: "talk", label: "与邻人交谈", effects: { hope: .3, order: .1 }, faction: "commons" },
  { id: "observe", label: "观察天象", effects: { aether: .25 }, faction: "keepers" },
];

function mergeNumbers(target, modifiers = {}) {
  Object.entries(modifiers || {}).forEach(([key, value]) => {
    if (typeof value === "number") target[key] = clamp((target[key] ?? 0) + value);
  });
}

function parseClock(value, fallback = 0) {
  if (typeof value === "number") return value < 24 ? Math.floor(value * 60) : Math.floor(value);
  if (typeof value !== "string") return fallback;
  const [hours, minutes = "0"] = value.split(":");
  const result = Number(hours) * 60 + Number(minutes);
  return Number.isFinite(result) ? result : fallback;
}

export function getTimelineDifficulty(content, timelineId) {
  const timeline = (content?.timelines || []).find((item) => item.id === timelineId);
  const configured = timeline?.difficulty || {};
  const numberOr = (value, fallback) => Number.isFinite(Number(value)) ? Number(value) : fallback;
  const rank = Math.round(clamp(numberOr(configured.rank, 2), 1, 3));
  return {
    rank,
    label: String(configured.label || DIFFICULTY_LABELS[rank - 1]),
    dailyDrain: clamp(numberOr(configured.dailyDrain, 1), .25, 3),
    npcRecovery: clamp(numberOr(configured.npcRecovery, 1), .25, 3),
  };
}

function initialNpcState(npc, minute = 420) {
  const firstSchedule = scheduleFor(npc, minute) || npc.schedule?.[0];
  const regionId = firstSchedule?.regionId || firstSchedule?.region || npc.regionId || npc.region || "capital";
  const placeId = firstSchedule?.placeId || regionId;
  return {
    id: npc.id,
    regionId,
    placeId,
    x: Number(firstSchedule?.x ?? npc.x ?? 384),
    y: Number(firstSchedule?.y ?? npc.y ?? 240),
    targetX: Number(firstSchedule?.x ?? npc.x ?? 384),
    targetY: Number(firstSchedule?.y ?? npc.y ?? 240),
    relationship: clamp(Number(npc.relationship ?? npc.initialRelationship ?? 10), -100, 100),
    mood: "平静",
    activity: firstSchedule?.activity || "开始新的一天",
    actionId: "idle",
    memories: [{ type: "thought", day: 1, minute: 420, text: `我想先完成自己的目标：${npc.goal || "平安度过这几日"}` }],
    reflection: "尚未看清这条世界线会通向哪里。",
    knownToPlayer: false,
    conversations: 0,
    lastActionHour: -1,
    scheduleSlotKey: `${firstSchedule?.start || ""}-${firstSchedule?.end || ""}-${placeId}`,
  };
}

export function createInitialState(content, timelineId, mode = "player") {
  const gameMode = mode === "observer" ? "observer" : "player";
  const isObserver = gameMode === "observer";
  const timelines = content.timelines || [];
  const timeline = timelines.find((item) => item.id === timelineId) || timelines[0] || { id: "default", name: "无名线", seed: 1 };
  const startRegion = timeline.startRegion || content.game?.startRegion || "capital";
  const region = (content.regions || []).find((item) => item.id === startRegion) || content.regions?.[0] || {};
  const spawn = region.spawn || { x: 384, y: 390 };
  const startMinute = Number(content.game?.startMinute ?? 420);
  const state = {
    version: 2,
    contentVersion: content.game?.contentVersion || 1,
    mode: gameMode,
    timelineId: timeline.id,
    timelineName: timeline.name,
    difficulty: getTimelineDifficulty(content, timeline.id),
    seed: Number(timeline.seed ?? hashString(timeline.id)),
    rngState: Number(timeline.seed ?? hashString(timeline.id)) >>> 0,
    day: 1,
    minute: startMinute,
    lastProcessedHour: -1,
    regionId: startRegion,
    placeId: startRegion,
    visitedRegions: [startRegion],
    visitedPlaces: [startRegion],
    player: { present: !isObserver, x: Number(spawn.x ?? 384), y: Number(spawn.y ?? 390), facing: "down", speed: 112 },
    observer: { focusedNpcId: null, cameraX: Number(spawn.x ?? 384), cameraY: Number(spawn.y ?? 390) },
    metrics: deepClone(content.game?.initialMetrics || DEFAULT_METRICS),
    factions: deepClone(content.game?.initialFactions || DEFAULT_FACTIONS),
    npcs: Object.fromEntries((content.npcs || []).map((npc) => [npc.id, initialNpcState(npc, startMinute)])),
    completedEvents: [],
    pendingEvents: [],
    flags: { playerArrived: !isObserver, observerWorld: isObserver },
    journal: [],
    weather: "晴",
    speed: 1,
    pausedByModal: false,
    endingId: null,
    endingShown: false,
    statistics: { conversations: 0, journeys: 0, observerSwitches: 0, choices: 0, observedChoices: 0, npcActions: 0, llmPlans: 0, lastLlmPlanDay: 0 },
  };
  const modifiers = timeline.modifiers || timeline.initialModifiers || {};
  mergeNumbers(state.metrics, modifiers.metrics || {});
  mergeNumbers(state.factions, modifiers.factions || {});
  Object.assign(state.flags, modifiers.flags || {});
  state.flags.playerArrived = !isObserver;
  state.flags.observerWorld = isObserver;
  if (modifiers.relationships) {
    Object.entries(modifiers.relationships).forEach(([npcId, value]) => {
      if (state.npcs[npcId]) state.npcs[npcId].relationship = clamp(state.npcs[npcId].relationship + value, -100, 100);
    });
  }
  state.journal.push({
    id: `arrival-${Date.now()}`,
    day: 1,
    minute: state.minute,
    type: isObserver ? "world" : "player",
    text: isObserver
      ? `「${timeline.name}」开始自行运转。没有旅行者进入这条世界线，九日后的结局将完全由 NPC 写下。`
      : `你踏入了「${timeline.name}」。九日之后，坠星会为所有选择作证。`,
  });
  syncNpcSchedules(state, content);
  updateWeather(state, content);
  return state;
}

export function addJournal(state, text, type = "world", extra = {}) {
  const entry = {
    id: `${state.day}-${state.minute}-${state.journal.length}-${Math.floor(nextRandom(state) * 9999)}`,
    day: state.day,
    minute: Math.floor(state.minute),
    type,
    text,
    ...extra,
  };
  state.journal.unshift(entry);
  state.journal = state.journal.slice(0, 160);
  return entry;
}

export function remember(state, npcId, text, type = "event", importance = 1) {
  const npcState = state.npcs[npcId];
  if (!npcState || !text) return;
  npcState.memories.unshift({ type, day: state.day, minute: Math.floor(state.minute), text, importance });
  npcState.memories = npcState.memories.slice(0, 12);
  if (npcState.memories.length >= 5 && npcState.memories.length % 4 === 1) {
    const lowest = Object.entries(state.metrics).sort((a, b) => a[1] - b[1])[0];
    const label = METRIC_META[lowest?.[0]]?.label || lowest?.[0];
    npcState.reflection = `最近的迹象都指向同一件事：${label}正在成为这个世界最脆弱的部分。`;
  }
}

function scheduleFor(npc, minute) {
  const schedule = npc.schedule || [];
  if (!schedule.length) return null;
  return schedule.find((slot) => {
    const start = parseClock(slot.start, 0);
    const end = parseClock(slot.end, 1440);
    if (end < start) return minute >= start || minute < end;
    return minute >= start && minute < end;
  }) || schedule[schedule.length - 1];
}

export function syncNpcSchedules(state, content) {
  (content.npcs || []).forEach((npc) => {
    const npcState = state.npcs[npc.id];
    if (!npcState) return;
    const slot = scheduleFor(npc, state.minute);
    if (!slot) return;
    const nextRegionId = slot.regionId || slot.region || npcState.regionId;
    const nextPlaceId = slot.placeId || nextRegionId;
    const targetX = Number(slot.x ?? npcState.targetX ?? npc.x ?? 384);
    const targetY = Number(slot.y ?? npcState.targetY ?? npc.y ?? 240);
    const slotKey = `${slot.start || ""}-${slot.end || ""}-${nextRegionId}-${nextPlaceId}`;
    const changedScene = npcState.regionId !== nextRegionId || (npcState.placeId || npcState.regionId) !== nextPlaceId;
    npcState.activity = slot.activity || slot.label || npcState.activity;
    npcState.targetX = targetX;
    npcState.targetY = targetY;
    npcState.regionId = nextRegionId;
    npcState.placeId = nextPlaceId;
    if (changedScene || (npcState.scheduleSlotKey && npcState.scheduleSlotKey !== slotKey && slot.teleport === true)) {
      npcState.x = Number(slot.entryX ?? targetX);
      npcState.y = Number(slot.entryY ?? targetY);
    }
    npcState.scheduleSlotKey = slotKey;
  });
}

function scoreAction(action, npc, npcState, state) {
  let score = 1;
  const weights = npc.actionWeights || {};
  score += Number(weights[action.id] || 0);
  Object.entries(action.effects || {}).forEach(([metric, delta]) => {
    if (delta > 0) score += (100 - (state.metrics[metric] || 50)) / 65;
    if (delta < 0) score -= Math.max(0, 45 - (state.metrics[metric] || 50)) / 40;
  });
  const words = `${npc.goal || ""} ${(npc.values || []).join(" ")} ${(npc.traits || []).join(" ")}`;
  if (/粮|农|收成|分享/.test(words) && action.effects?.food > 0) score += 1.1;
  if (/水|治疗|守护|生命/.test(words) && action.effects?.water > 0) score += 1.1;
  if (/秩序|责任|王|律/.test(words) && action.effects?.order > 0) score += .9;
  if (/自由|人民|希望|善良/.test(words) && action.effects?.hope > 0) score += .9;
  if (/秘密|星|知识|遗迹/.test(words) && action.effects?.aether) score += .8;
  if (npcState?.strategicActionId === action.id && Number(npcState.strategicPlanDay || 0) >= state.day - 1) score += 3.2;
  score += nextRandom(state) * 1.4;
  return score;
}

export function getNpcActionOptions(npc) {
  return [...(REGION_ACTIONS[npc.regionId || npc.region] || []), ...GENERIC_ACTIONS].map((action) => ({
    id: action.id,
    label: action.label,
    effects: deepClone(action.effects || {}),
  }));
}

function chooseNpcAction(npc, state) {
  const npcState = state.npcs[npc.id];
  const pool = [...(REGION_ACTIONS[npc.regionId || npc.region] || []), ...GENERIC_ACTIONS];
  return pool.map((action) => ({ action, score: scoreAction(action, npc, npcState, state) }))
    .sort((a, b) => b.score - a.score)[0].action;
}

function updateNpcMood(npcState, state) {
  const average = Object.values(state.metrics).reduce((sum, value) => sum + value, 0) / Object.values(state.metrics).length;
  if (npcState.relationship >= 65) npcState.mood = "见到你很安心";
  else if (npcState.relationship <= -25) npcState.mood = "对你保持戒心";
  else if (average < 30) npcState.mood = "忧心忡忡";
  else if (state.metrics.aether > 76) npcState.mood = "被星辉扰得不安";
  else if (state.metrics.hope > 70) npcState.mood = "心怀期待";
  else npcState.mood = "专注于眼前的事";
}

export function runAutonomousHour(state, content, hourIndex) {
  const logs = [];
  const difficulty = getTimelineDifficulty(content, state.timelineId);
  (content.npcs || []).forEach((npc) => {
    const npcState = state.npcs[npc.id];
    if (!npcState || npcState.lastActionHour === hourIndex) return;
    // A meaningful decision every three hours keeps fifteen agents active
    // without letting hundreds of tiny actions saturate every world metric.
    if ((hourIndex + hashString(npc.id)) % 3 !== 0) return;
    const action = chooseNpcAction(npc, state);
    npcState.lastActionHour = hourIndex;
    npcState.actionId = action.id;
    Object.entries(action.effects || {}).forEach(([metric, delta]) => {
      const recovery = SURVIVAL_METRICS.has(metric) && delta > 0 ? difficulty.npcRecovery : 1;
      state.metrics[metric] = clamp((state.metrics[metric] || 0) + delta * .28 * recovery);
    });
    if (action.faction) state.factions[action.faction] = clamp((state.factions[action.faction] || 0) + .2);
    state.statistics.npcActions += 1;
    const consequence = Object.entries(action.effects || {})
      .filter(([, value]) => Math.abs(value) >= .25)
      .map(([key, value]) => `${METRIC_META[key]?.label || key}${value > 0 ? "略有改善" : "受到损耗"}`)
      .join("、");
    const memoryText = `${formatStamp(state.day, state.minute)}，我${action.label}，${consequence || "局势暂时没有明显变化"}。`;
    remember(state, npc.id, memoryText, "event", 1);
    updateNpcMood(npcState, state);
    // Journal sampling must never depend on the observer's current camera region.
    // It also must not consume the simulation RNG, otherwise merely looking at a
    // different map could change later NPC choices and the eventual ending.
    const logRoll = Math.abs(hashString(`${state.seed}:${hourIndex}:${npc.id}:log`)) % 100;
    if (hourIndex % 3 === 0 || logRoll >= 78) {
      logs.push({ npcId: npc.id, text: `${npc.name}${action.label}。${consequence ? `${consequence}。` : ""}`, reason: `${npc.goal || "维持日常"}；当前最关注${METRIC_META[Object.entries(state.metrics).sort((a,b) => a[1]-b[1])[0][0]]?.label}。` });
    }
  });
  return logs;
}

export function updateWeather(state, content) {
  const timeline = (content.timelines || []).find((item) => item.id === state.timelineId);
  const options = timeline?.weather || ["晴", "薄云", "微风", "星尘"];
  const index = Math.abs(hashString(`${state.seed}-${state.day}`)) % options.length;
  state.weather = options[index] || "晴";
}

export function dueEvents(state, content) {
  return (content.events || []).filter((event) => {
    if (state.completedEvents.includes(event.id) || state.pendingEvents.includes(event.id)) return false;
    const eventMinute = parseClock(event.hour ?? event.time, 720);
    return state.day > Number(event.day) || (state.day === Number(event.day) && state.minute >= eventMinute);
  });
}

export function advanceWorld(state, content, minutes) {
  if (!Number.isFinite(minutes) || minutes <= 0 || state.endingId) return { logs: [], events: [] };
  const logs = [];
  const beforeAbsolute = (state.day - 1) * 1440 + state.minute;
  let afterAbsolute = beforeAbsolute + minutes;
  const totalDays = Number(content.game?.totalDays || 9);
  const endingClock = parseClock(content.game?.endingHour ?? content.game?.endingTime, Number(content.game?.endingMinute ?? 1260));
  const maxAbsolute = Math.max(0, totalDays - 1) * 1440 + endingClock;
  afterAbsolute = Math.min(afterAbsolute, maxAbsolute);
  state.day = Math.floor(afterAbsolute / 1440) + 1;
  state.minute = Math.floor(afterAbsolute % 1440);

  const firstHour = Math.floor(beforeAbsolute / 60) + 1;
  const lastHour = Math.floor(afterAbsolute / 60);
  for (let hour = firstHour; hour <= lastHour; hour += 1) {
    state.day = Math.floor(hour * 60 / 1440) + 1;
    state.minute = (hour * 60) % 1440;
    syncNpcSchedules(state, content);
    logs.push(...runAutonomousHour(state, content, hour));
    if (state.minute === 360) {
      // Daily consumption and the approaching star counterbalance NPC work.
      const dailyDrain = getTimelineDifficulty(content, state.timelineId).dailyDrain;
      state.metrics.food = clamp(state.metrics.food - 2.2 * dailyDrain);
      state.metrics.water = clamp(state.metrics.water - 1.7 * dailyDrain);
      state.metrics.order = clamp(state.metrics.order - .8 * dailyDrain);
      state.metrics.hope = clamp(state.metrics.hope - .65 * dailyDrain);
      state.metrics.aether = clamp(state.metrics.aether + 1.45);
      updateWeather(state, content);
      addJournal(state, `第 ${state.day} 日清晨，天气是${state.weather}。五地的人们继续各自的生活。`, "world");
    }
  }
  state.day = Math.floor(afterAbsolute / 1440) + 1;
  state.minute = Math.floor(afterAbsolute % 1440);
  syncNpcSchedules(state, content);
  const events = dueEvents(state, content);
  events.forEach((event) => state.pendingEvents.push(event.id));
  return { logs, events };
}

function applyNumericEffects(target, effects = {}) {
  Object.entries(effects || {}).forEach(([key, value]) => {
    if (typeof value === "number") target[key] = clamp((target[key] || 0) + value, key === "relationship" ? -100 : 0, 100);
  });
}

export function requirementsMet(choice, state) {
  const requirements = choice.requirements || choice.requires;
  if (!requirements) return { ok: true, reason: "" };
  const checks = Array.isArray(requirements) ? requirements : requirements.all || [requirements];
  for (const check of checks) {
    if (typeof check === "string") {
      if (!state.flags[check]) return { ok: false, reason: `需要先获得线索：${check}` };
      continue;
    }
    const actual = getByPath(state, check.path);
    const expected = check.value;
    const passed = compare(actual, check.op || ">=", expected);
    if (!passed) return { ok: false, reason: check.label || `需要 ${check.path} ${check.op || ">="} ${expected}` };
  }
  return { ok: true, reason: "" };
}

export function applyEventChoice(state, event, choice, content, options = {}) {
  const effects = choice.effects || {};
  applyNumericEffects(state.metrics, effects.metrics);
  applyNumericEffects(state.factions, effects.factions);
  if (state.mode !== "observer") {
    Object.entries(effects.relationships || {}).forEach(([npcId, delta]) => {
      if (state.npcs[npcId]) state.npcs[npcId].relationship = clamp(state.npcs[npcId].relationship + Number(delta), -100, 100);
    });
  }
  if (Array.isArray(effects.flags)) effects.flags.forEach((flag) => { state.flags[flag] = true; });
  else Object.assign(state.flags, effects.flags || {});
  state.flags[`event:${event.id}`] = choice.id;
  state.pendingEvents = state.pendingEvents.filter((id) => id !== event.id);
  if (!state.completedEvents.includes(event.id)) state.completedEvents.push(event.id);
  const isAutonomous = options.actor === "world";
  if (isAutonomous) state.statistics.observedChoices = Number(state.statistics.observedChoices || 0) + 1;
  else state.statistics.choices += 1;
  const isObserver = state.mode === "observer";
  const memory = isAutonomous
    ? choice.autonomousMemory || (isObserver
      ? `在「${event.title}」中，没有旅行者出现，我们自行决定：${choice.label}。`
      : `在「${event.title}」中，旅行者保持沉默，我们自行决定：${choice.label}。`)
    : choice.memory || `在「${event.title}」中，旅行者选择了：${choice.label}。`;
  const involved = event.npcIds || event.npcs || (content.npcs || []).filter((npc) => (npc.regionId || npc.region) === event.regionId || (npc.regionId || npc.region) === event.region).map((npc) => npc.id);
  involved.forEach((npcId) => remember(state, npcId, memory, "event", 3));
  const subject = isAutonomous
    ? isObserver ? "没有旅行者介入，NPC 们共同选择了" : "你没有介入，NPC 们共同选择了"
    : "你选择了";
  addJournal(state, `${event.title}：${subject}「${choice.label}」。${choice.outcome || "世界的走向因此发生了变化。"}`, "event", { eventId: event.id, choiceId: choice.id, autonomous: isAutonomous });
  return { memory, involved };
}

function compare(actual, operator, expected) {
  switch (operator) {
    case ">": return actual > expected;
    case ">=": return actual >= expected;
    case "<": return actual < expected;
    case "<=": return actual <= expected;
    case "==": case "=": return actual === expected;
    case "!=": return actual !== expected;
    case "includes": return Array.isArray(actual) ? actual.includes(expected) : String(actual || "").includes(String(expected));
    default: return Boolean(actual);
  }
}

export function endingMatches(ending, state) {
  const condition = ending.condition || ending.conditions || {};
  const all = condition.all || [];
  const any = condition.any || [];
  const flags = condition.flags || [];
  const allPass = all.every((rule) => compare(getByPath(state, rule.path), rule.op || ">=", rule.value));
  const anyPass = !any.length || any.some((rule) => compare(getByPath(state, rule.path), rule.op || ">=", rule.value));
  const flagsPass = flags.every((flag) => typeof flag === "string" ? Boolean(state.flags[flag]) : compare(getByPath(state, `flags.${flag.key}`), flag.op || "==", flag.value));
  return allPass && anyPass && flagsPass;
}

export function resolveEnding(state, content) {
  const endings = [...(content.endings || [])].sort((a, b) => Number(b.priority || 0) - Number(a.priority || 0));
  let result = endings.find((ending) => !ending.fallback && endingMatches(ending, state));
  if (!result) result = endings.find((ending) => ending.fallback);
  if (!result && endings.length) result = endings[endings.length - 1];
  state.endingId = result?.id || "unwritten";
  addJournal(state, `这条世界线抵达结局：${result?.title || "未写完的故事"}。`, "event");
  return result || { id: "unwritten", title: "未写完的故事", subtitle: "时间仍在纸页外流动。", epilogue: "没有任何一种预言能够完整描述人们共同写下的未来。" };
}

export function shouldResolveEnding(state, content) {
  const endingDay = Number(content.game?.endingDay || content.game?.totalDays || 9);
  const endingMinute = parseClock(content.game?.endingHour ?? content.game?.endingTime, 1260);
  return !state.endingId && state.day >= endingDay && state.minute >= endingMinute && state.pendingEvents.length === 0;
}

export function travelTo(state, content, regionId) {
  const region = (content.regions || []).find((item) => item.id === regionId);
  if (!region || regionId === state.regionId) return false;
  state.regionId = regionId;
  state.placeId = regionId;
  state.player.x = Number(region.spawn?.x ?? 384);
  state.player.y = Number(region.spawn?.y ?? 390);
  if (!state.visitedRegions.includes(regionId)) state.visitedRegions.push(regionId);
  state.visitedPlaces ||= [];
  if (!state.visitedPlaces.includes(regionId)) state.visitedPlaces.push(regionId);
  state.statistics.journeys += 1;
  addJournal(state, `你经过界碑，抵达${region.name}。`, "player");
  return true;
}

export function observeRegion(state, content, regionId) {
  const region = (content.regions || []).find((item) => item.id === regionId);
  const currentPlaceId = state.placeId || state.regionId;
  if (!region || (regionId === state.regionId && currentPlaceId === regionId)) return false;
  state.regionId = regionId;
  state.placeId = regionId;
  const spawn = region.spawn || { x: Number(region.width || 768) / 2, y: Number(region.height || 480) / 2 };
  state.observer ||= {};
  state.observer.focusedNpcId = null;
  state.observer.cameraX = Number(spawn.x ?? 384);
  state.observer.cameraY = Number(spawn.y ?? 240);
  if (!state.visitedRegions.includes(regionId)) state.visitedRegions.push(regionId);
  state.visitedPlaces ||= [];
  if (!state.visitedPlaces.includes(regionId)) state.visitedPlaces.push(regionId);
  state.statistics.observerSwitches = Number(state.statistics.observerSwitches || 0) + 1;
  return true;
}

export function transitionToPlace(state, content, target, options = {}) {
  const regionId = target?.regionId || state.regionId;
  const placeId = target?.placeId || regionId;
  const region = (content.regions || []).find((item) => item.id === regionId);
  const place = placeId === regionId
    ? region
    : (content.places || []).find((item) => item.id === placeId && item.regionId === regionId);
  if (!region || !place) return false;

  state.regionId = regionId;
  state.placeId = placeId;
  state.player.x = Number(target.x ?? place.spawn?.x ?? Number(place.width || 768) / 2);
  state.player.y = Number(target.y ?? place.spawn?.y ?? Number(place.height || 480) - 64);
  state.player.facing = target.facing || state.player.facing || "down";
  if (!state.visitedRegions.includes(regionId)) state.visitedRegions.push(regionId);
  state.visitedPlaces ||= [];
  if (!state.visitedPlaces.includes(placeId)) state.visitedPlaces.push(placeId);
  if (options.countJourney) state.statistics.journeys = Number(state.statistics.journeys || 0) + 1;
  if (options.journalText) addJournal(state, options.journalText, "player");
  return true;
}

export function describeEffects(effects = {}) {
  const pieces = [];
  Object.entries(effects.metrics || {}).forEach(([key, value]) => pieces.push(`${METRIC_META[key]?.label || key} ${value >= 0 ? "+" : ""}${value}`));
  Object.entries(effects.factions || {}).forEach(([key, value]) => pieces.push(`${FACTION_META[key]?.label || key} ${value >= 0 ? "+" : ""}${value}`));
  return pieces.join(" · ");
}
