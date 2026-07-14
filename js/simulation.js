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

function storyClock(day, minute) {
  return Math.max(0, Number(day || 1) - 1) * 1440 + Math.max(0, Number(minute || 0));
}

function eventStartClock(event) {
  const starts = event?.story?.starts || {};
  const day = Number(starts.day ?? Math.max(1, Number(event?.day || 1) - 1));
  return storyClock(day, parseClock(starts.hour, 9 * 60));
}

function eventResolutionClock(event) {
  return storyClock(Number(event?.day || 1), parseClock(event?.hour ?? event?.time, 12 * 60));
}

function freshStoryState(event, observer = false) {
  return {
    status: "dormant",
    discovered: observer,
    processKnown: observer,
    outcomeKnown: false,
    learnedLate: false,
    heardRumors: [],
    clues: [],
    autonomousDiscoveries: [],
    influencedNpcs: {},
    rejectedNpcs: {},
    influenceHistory: [],
    outcomeId: null,
    activatedAt: null,
    resolvedAt: null,
    resolutionScores: {},
    eventId: event.id,
  };
}

function ensureStoryState(state, event) {
  state.story ||= {};
  const fresh = freshStoryState(event, state.mode === "observer");
  if (!state.story[event.id]) {
    state.story[event.id] = fresh;
    return state.story[event.id];
  }
  const story = state.story[event.id];
  Object.entries(fresh).forEach(([key, value]) => {
    if (story[key] !== undefined) return;
    story[key] = Array.isArray(value) ? [...value] : value && typeof value === "object" ? { ...value } : value;
  });
  story.processKnown ??= story.discovered ?? fresh.processKnown;
  story.outcomeKnown ??= false;
  for (const key of ["heardRumors", "clues", "autonomousDiscoveries", "influenceHistory"]) {
    if (!Array.isArray(story[key])) story[key] = [];
  }
  for (const key of ["influencedNpcs", "rejectedNpcs", "resolutionScores"]) {
    if (!story[key] || typeof story[key] !== "object" || Array.isArray(story[key])) story[key] = {};
  }
  Object.entries(story.rejectedNpcs).forEach(([npcId, choiceIds]) => {
    if (!Array.isArray(choiceIds)) story.rejectedNpcs[npcId] = choiceIds ? [choiceIds] : [];
  });
  return story;
}

function addStoryJournal(state, eventId, text, phase = "world") {
  const id = `story-${eventId}-${phase}`;
  if ((state.journal || []).some((entry) => entry.id === id)) return;
  state.journal.unshift({ id, day: state.day, minute: Math.floor(state.minute), type: "world", text });
  state.journal = state.journal.slice(0, 160);
}

export function normalizeStoryState(state, content) {
  state.story ||= {};
  state.flags ||= {};
  state.completedEvents ||= [];
  state.statistics ||= {};
  state.statistics.influences = Number(state.statistics.influences || 0);
  state.statistics.rejections = Number(state.statistics.rejections || 0);
  state.statistics.rumorsHeard = Number(state.statistics.rumorsHeard || 0);
  state.statistics.missedEvents = Number(state.statistics.missedEvents || 0);
  state.pendingEvents = [];
  (content.events || []).forEach((event) => {
    const story = ensureStoryState(state, event);
    const legacyOutcome = state.flags?.[`event:${event.id}`];
    if ((state.completedEvents || []).includes(event.id) || legacyOutcome) {
      story.status = "resolved";
      story.outcomeId ||= legacyOutcome || null;
      if (state.mode === "observer") story.outcomeKnown = true;
      state.flags[`story:${event.id}:active`] = false;
      state.flags[`story:${event.id}:resolved`] = true;
    }
  });
  return state.story;
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
    memories: [{ type: "thought", day: 1, minute: 420, text: `我想先完成自己的目标：${npc.goal || "平安度过这几日"}`, importance: 1 }],
    // Core memories are social turning points. Routine hourly memories may fade,
    // but a promise made face-to-face must still matter when the event resolves.
    coreMemories: [],
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
    version: 3,
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
    story: Object.fromEntries((content.events || []).map((event) => [event.id, freshStoryState(event, isObserver)])),
    flags: { playerArrived: !isObserver, observerWorld: isObserver },
    spokenNpcIds: [],
    journal: [],
    weather: "晴",
    speed: 1,
    pausedByModal: false,
    endingId: null,
    endingShown: false,
    statistics: {
      conversations: 0,
      conversationTurns: 0,
      journeys: 0,
      observerSwitches: 0,
      choices: 0,
      observedChoices: 0,
      influences: 0,
      rejections: 0,
      rumorsHeard: 0,
      missedEvents: 0,
      npcActions: 0,
      llmPlans: 0,
      lastLlmPlanDay: 0,
    },
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
  normalizeStoryState(state, content);
  return state;
}

export function addJournal(state, text, type = "world", extra = {}) {
  state.journalSequence = Number(state.journalSequence || state.journal?.length || 0) + 1;
  const entry = {
    // UI logging must never advance the simulation RNG. Observer cameras,
    // journal filters and the "show thoughts" preference are presentation only.
    id: `${state.day}-${Math.floor(state.minute)}-${state.journalSequence}-${Math.abs(hashString(text)) % 9999}`,
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
  const memory = { type, day: state.day, minute: Math.floor(state.minute), text, importance };
  npcState.memories ||= [];
  npcState.memories.unshift(memory);
  npcState.memories = npcState.memories.slice(0, 12);
  if (Number(importance) >= 3) {
    npcState.coreMemories ||= [];
    npcState.coreMemories = [memory, ...npcState.coreMemories.filter((item) => item.text !== text)].slice(0, 10);
  }
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
      logs.push({
        npcId: npc.id,
        regionId: npcState.regionId,
        placeId: npcState.placeId || npcState.regionId,
        text: `${npc.name}${action.label}。${consequence ? `${consequence}。` : ""}`,
        reason: `${npc.goal || "维持日常"}；当前最关注${METRIC_META[Object.entries(state.metrics).sort((a,b) => a[1]-b[1])[0][0]]?.label}。`,
      });
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

function currentStoryClock(state) {
  return storyClock(state.day, state.minute);
}

function uniquePush(list, value) {
  if (value && !list.includes(value)) list.push(value);
}

function storyParticipants(event) {
  const ids = new Set(event.npcIds || event.npcs || []);
  (event.story?.rumors || []).forEach((rumor) => ids.add(rumor.npcId));
  (event.choices || []).forEach((choice) => (choice.social?.npcIds || []).forEach((npcId) => ids.add(npcId)));
  return [...ids].filter(Boolean);
}

function npcSupportsChoice(npc, choice, state) {
  if (!npc) return 0;
  const words = `${(npc.values || []).join(" ")} ${(npc.traits || []).join(" ")} ${npc.goal || ""}`;
  const effects = choice.effects || {};
  let score = 0;
  if (/生命|同伴|朋友|回家|安全/.test(words) && Number(effects.metrics?.hope || 0) > 0) score += .8;
  if (/清水|土地|季节|水/.test(words) && Number(effects.metrics?.water || 0) > 0) score += .7;
  if (/秩序|职责|责任|王室|可控/.test(words) && Number(effects.metrics?.order || 0) > 0) score += .7;
  if (/真相|证据|公开|历史|记忆/.test(words) && /公开|证据|原件|记录|誓/.test(`${choice.label} ${choice.social?.topic || ""}`)) score += .9;
  if (/公平|选择权|互助|普通人|自愿/.test(words) && /共同|公开|自愿|每|民|分享/.test(`${choice.label} ${choice.social?.topic || ""}`)) score += .9;
  if (/旧誓|平衡|长久|古代技术/.test(words) && Number(effects.metrics?.aether || 0) !== 0) score += .7;
  const npcState = state.npcs?.[npc.id];
  score += Math.max(-.35, Math.min(.55, Number(npcState?.relationship || 0) / 160));
  return score;
}

function choiceAvailableToSociety(state, content, event, choice, story) {
  if (!requirementsMet({ requirements: choice.worldRequirements }, state).ok) return false;
  if (!choice.requirements && !choice.requires) return true;
  if (choice.requirementsScope !== "player-evidence") return requirementsMet(choice, state).ok;

  const socialNpcIds = choice.social?.npcIds || [];
  if (socialNpcIds.some((npcId) => story.influencedNpcs?.[npcId] === choice.id)) return true;
  if (story.autonomousDiscoveries.includes(choice.id)) return true;

  const investigatorDrive = socialNpcIds.reduce((sum, npcId) => {
    const npc = (content.npcs || []).find((item) => item.id === npcId);
    const words = `${(npc?.values || []).join(" ")} ${(npc?.traits || []).join(" ")}`;
    return sum + (/证据|真相|好奇|古代|旧誓|知识|记忆|水/.test(words) ? 3 : 0);
  }, 0);
  const threshold = Math.min(55, 20 + Number(state.factions?.keepers || 0) / 5 + investigatorDrive);
  const roll = Math.abs(hashString(`${state.seed}:${event.id}:${choice.id}:npc-discovery`)) % 100;
  if (roll >= threshold) return false;

  uniquePush(story.autonomousDiscoveries, choice.id);
  const discovererId = socialNpcIds[Math.abs(hashString(`${event.id}:${choice.id}:discoverer`)) % Math.max(1, socialNpcIds.length)];
  if (discovererId) {
    remember(
      state,
      discovererId,
      `在「${event.title}」商议前，我们从自己的调查中找到了支持「${choice.label}」的新依据。`,
      "discovery",
      2,
    );
  }
  return true;
}

function choiceAlignment(left, right) {
  let score = 0;
  for (const section of ["factions", "metrics"]) {
    const leftEffects = left?.effects?.[section] || {};
    const rightEffects = right?.effects?.[section] || {};
    Object.entries(leftEffects).forEach(([key, leftValue]) => {
      const rightValue = Number(rightEffects[key] || 0);
      const leftNumber = Number(leftValue || 0);
      if (!leftNumber || !rightValue) return;
      const sameDirection = Math.sign(leftNumber) === Math.sign(rightValue);
      const unit = section === "factions" ? .07 : .025;
      score += Math.min(Math.abs(leftNumber), Math.abs(rightValue)) * unit * (sameDirection ? 1 : -.4);
    });
  }
  return score;
}

function historicalChoiceScore(state, content, event, choice) {
  const finalProcess = event.id === "ember-key";
  let score = 0;
  for (const previousEvent of content.events || []) {
    if (previousEvent.id === event.id) break;
    const previousStory = ensureStoryState(state, previousEvent);
    if (previousStory.status !== "resolved") continue;
    const outcome = (previousEvent.choices || []).find((item) => item.id === previousStory.outcomeId);
    if (outcome) score += choiceAlignment(choice, outcome) * (finalProcess ? 1.15 : .35);
    const rememberedChoices = new Set((previousStory.influenceHistory || [])
      .filter((item) => item.accepted !== false)
      .map((item) => item.choiceId));
    rememberedChoices.forEach((choiceId) => {
      const promised = (previousEvent.choices || []).find((item) => item.id === choiceId);
      if (promised) score += choiceAlignment(choice, promised) * (finalProcess ? .65 : .18);
    });
    const rejectedChoices = new Set((previousStory.influenceHistory || [])
      .filter((item) => item.accepted === false)
      .map((item) => item.choiceId));
    rejectedChoices.forEach((choiceId) => {
      const rejected = (previousEvent.choices || []).find((item) => item.id === choiceId);
      if (rejected) score -= choiceAlignment(choice, rejected) * (finalProcess ? .18 : .05);
    });
  }
  return score;
}

function resolveStoryEvent(state, content, event) {
  const story = ensureStoryState(state, event);
  if (story.status === "resolved") return null;
  const scored = (event.choices || []).map((choice) => {
    const available = choiceAvailableToSociety(state, content, event, choice, story);
    if (!available) return { choice, score: -10000, available: false };
    let score = Number(choice.storySupport ?? choice.social?.baseSupport ?? 1);
    const socialNpcIds = choice.social?.npcIds || [];
    const influencedSupporters = socialNpcIds.filter((npcId) => story.influencedNpcs?.[npcId] === choice.id);
    const rejectingParticipants = socialNpcIds.filter((npcId) => story.rejectedNpcs?.[npcId]?.includes(choice.id));
    score += influencedSupporters.length * 3.25 + Math.max(0, influencedSupporters.length - 1) * 1.1;
    score -= rejectingParticipants.length * 1.75;
    influencedSupporters.forEach((npcId) => {
      const keptPromise = (state.npcs?.[npcId]?.coreMemories || []).some((memory) => (
        memory.type === "promise"
        && String(memory.text || "").includes(event.title)
        && String(memory.text || "").includes(choice.label)
      ));
      if (keptPromise) score += .65;
    });
    socialNpcIds.forEach((npcId) => {
      const npc = (content.npcs || []).find((item) => item.id === npcId);
      score += npcSupportsChoice(npc, choice, state);
    });
    Object.entries(choice.effects?.factions || {}).forEach(([factionId, delta]) => {
      if (Number(delta) > 0) score += Number(delta) * Number(state.factions?.[factionId] || 0) / 750;
    });
    Object.entries(choice.effects?.metrics || {}).forEach(([metricId, delta]) => {
      if (Number(delta) > 0) score += Number(delta) * Math.max(0, 55 - Number(state.metrics?.[metricId] || 0)) / 1100;
    });
    score += historicalChoiceScore(state, content, event, choice);
    // Stable uncertainty lets the same untouched timeline reproduce exactly,
    // while different timeline seeds can still grow into different histories.
    score += (Math.abs(hashString(`${state.seed}:${event.id}:${choice.id}:council`)) % 1000) / 1000;
    return { choice, score, available: true };
  }).sort((a, b) => b.score - a.score);
  const winner = scored.find((item) => item.available)?.choice || null;
  if (!winner) return null;

  const influenced = Object.values(story.influencedNpcs || {}).some((choiceId) => choiceId === winner.id);
  applyEventChoice(state, event, winner, content, {
    actor: "world",
    silent: state.mode !== "observer" && !story.processKnown,
    influenced,
    storyProcess: true,
  });
  story.status = "resolved";
  story.outcomeId = winner.id;
  story.resolvedAt = currentStoryClock(state);
  story.resolutionScores = Object.fromEntries(scored.map((item) => [item.choice.id, Math.round(item.score * 100) / 100]));
  state.flags[`story:${event.id}:active`] = false;
  state.flags[`story:${event.id}:resolved`] = true;
  if (state.mode === "observer") {
    story.outcomeKnown = true;
    addStoryJournal(state, event.id, `${event.title}并没有等待谁来裁决。参与者最终形成了「${winner.label}」的结果。`, "resolved");
  } else if (!story.processKnown) {
    state.statistics.missedEvents = Number(state.statistics.missedEvents || 0) + 1;
  }
  story.discovered = Boolean(story.processKnown || story.outcomeKnown);
  return { type: "resolved", eventId: event.id, choiceId: winner.id, discovered: story.processKnown, outcomeKnown: story.outcomeKnown };
}

export function advanceStoryEvents(state, content, throughAbsolute = currentStoryClock(state)) {
  normalizeStoryState(state, content);
  const changes = [];
  (content.events || []).forEach((event) => {
    const story = ensureStoryState(state, event);
    if (story.status === "dormant" && throughAbsolute >= eventStartClock(event)) {
      story.status = "active";
      story.activatedAt = eventStartClock(event);
      state.flags[`story:${event.id}:active`] = true;
      if (state.mode === "observer") {
        story.discovered = true;
        story.processKnown = true;
        addStoryJournal(state, event.id, `${event.title}开始在${event.regionId || event.region || "五地"}形成征兆。`, "active");
      }
      changes.push({ type: "active", eventId: event.id, discovered: story.processKnown });
    }
    if (story.status === "active" && throughAbsolute >= eventResolutionClock(event)) {
      const resolved = resolveStoryEvent(state, content, event);
      if (resolved) changes.push(resolved);
    }
  });
  return changes;
}

export function discoverStoryClue(state, content, eventId, clueId, source = "world") {
  const event = (content.events || []).find((item) => item.id === eventId);
  if (!event) return null;
  const story = ensureStoryState(state, event);
  const learningOutcome = story.status === "resolved";
  const wasDiscovered = learningOutcome ? story.outcomeKnown : story.processKnown;
  if (learningOutcome) story.outcomeKnown = true;
  else story.processKnown = true;
  story.discovered = Boolean(story.processKnown || story.outcomeKnown);
  uniquePush(story.clues, clueId || source);
  if (clueId) state.flags[`clue:${clueId}`] = true;
  if (!wasDiscovered && learningOutcome) story.learnedLate = true;
  return { event, story, firstDiscovery: !wasDiscovered, learnedLate: story.learnedLate, source };
}

export function revealNpcStoryKnowledge(state, content, npcId) {
  if (state.mode === "observer") return null;
  const npcState = state.npcs?.[npcId];
  if (!npcState) return null;
  const activeEvents = (content.events || [])
    .filter((event) => ensureStoryState(state, event).status === "active")
    .sort((left, right) => eventResolutionClock(left) - eventResolutionClock(right));
  // Current, expiring knowledge always takes precedence over old history.
  for (const event of activeEvents) {
    const story = ensureStoryState(state, event);
    const rumor = (event.story?.rumors || []).find((item) => (
      item.npcId === npcId
      && !story.heardRumors.includes(item.id)
      && Number(npcState.relationship || 0) >= Number(item.minRelationship || 0)
      && requirementsMet(item, state).ok
    ));
    if (!rumor) continue;
    story.discovered = true;
    story.processKnown = true;
    uniquePush(story.heardRumors, rumor.id);
    uniquePush(story.clues, rumor.clue || rumor.id);
    state.flags[`clue:${rumor.clue || rumor.id}`] = true;
    (rumor.grantsFlags || []).forEach((flag) => { state.flags[flag] = true; });
    state.statistics.rumorsHeard = Number(state.statistics.rumorsHeard || 0) + 1;
    addStoryJournal(state, event.id, `${rumor.memory || rumor.text}`, `rumor-${rumor.id}`);
    return { type: "rumor", event, story, rumor, text: rumor.text, memory: rumor.memory || rumor.text };
  }

  const unresolvedKnowledge = (content.events || [])
    .filter((event) => {
      const story = ensureStoryState(state, event);
      return story.status === "resolved" && !story.outcomeKnown && storyParticipants(event).includes(npcId);
    })
    .sort((left, right) => eventResolutionClock(right) - eventResolutionClock(left));
  for (const event of unresolvedKnowledge) {
    const story = ensureStoryState(state, event);
    const outcome = (event.choices || []).find((choice) => choice.id === story.outcomeId);
    story.discovered = true;
    story.outcomeKnown = true;
    story.learnedLate = true;
    uniquePush(story.clues, `aftermath:${event.id}`);
    const text = `${event.title}已经过去了。${outcome?.outcome || `人们最后采取了「${outcome?.label || "自己的办法"}」。`}`;
    addStoryJournal(state, event.id, `${npcState.knownToPlayer ? "后来你从当事人口中得知" : "后来有人提起"}：${text}`, "learned-late");
    return { type: "aftermath", event, story, outcome, text, memory: text };
  }
  return null;
}

function eligibleSocialChoices(state, content, npcId) {
  const result = [];
  (content.events || []).forEach((event) => {
    const story = ensureStoryState(state, event);
    if (story.status !== "active" || !story.processKnown || story.influencedNpcs?.[npcId]) return;
    (event.choices || []).forEach((choice) => {
      const social = choice.social;
      if (!social || !(social.npcIds || []).includes(npcId)) return;
      if (story.rejectedNpcs?.[npcId]?.includes(choice.id)) return;
      const requiredPlace = social.requiredPlaces?.[npcId];
      if (requiredPlace && (state.placeId || state.regionId) !== requiredPlace) return;
      if (Number(state.npcs?.[npcId]?.relationship || 0) < Number(social.minRelationship || 0)) return;
      if (!requirementsMet(choice, state).ok || !requirementsMet(social, state).ok) return;
      result.push({ event, choice, social });
    });
  });
  return result;
}

export function getStoryConversationTopics(state, content, npcId) {
  const byEvent = new Map();
  eligibleSocialChoices(state, content, npcId).forEach(({ event }) => {
    if (!byEvent.has(event.id)) byEvent.set(event.id, event);
  });
  return [...byEvent.values()].map((event) => ({
    id: `ask:${event.id}`,
    eventId: event.id,
    choiceId: null,
    label: `继续问「${event.title}」`,
    message: `关于「${event.title}」，你真正担心的是什么？`,
    intent: "custom",
  }));
}

export function getNpcStoryCandidates(state, content, npcId) {
  return eligibleSocialChoices(state, content, npcId).map(({ event, choice, social }) => ({ event, choice, social }));
}

function matchNpcStoryProposal(state, content, npcId, message, intent = "custom") {
  const normalized = String(message || "").toLowerCase().replace(/\s+/g, "");
  if (!normalized) return null;
  const candidates = eligibleSocialChoices(state, content, npcId).map((item) => {
    const keywords = item.social.keywords || [];
    const hits = keywords.filter((word) => normalized.includes(String(word).toLowerCase().replace(/\s+/g, ""))).length;
    const exact = normalized === String(item.social.playerLine || "").toLowerCase().replace(/\s+/g, "");
    return { ...item, hits, exact };
  }).filter((item) => item.exact || item.hits >= (intent === "story" ? 1 : 2))
    .sort((a, b) => Number(b.exact) - Number(a.exact) || b.hits - a.hits);
  return candidates[0] || null;
}

export function getNpcStoryProposal(state, content, npcId, message, intent = "custom") {
  const match = matchNpcStoryProposal(state, content, npcId, message, intent);
  if (!match) return null;
  return { event: match.event, choice: match.choice, social: match.social };
}

function commitNpcStoryProposal(state, content, npcId, message, match, accepted) {
  if (!match) return null;
  const story = ensureStoryState(state, match.event);
  if (!accepted) {
    story.rejectedNpcs[npcId] ||= [];
    uniquePush(story.rejectedNpcs[npcId], match.choice.id);
    story.influenceHistory.push({
      npcId,
      choiceId: match.choice.id,
      accepted: false,
      day: state.day,
      minute: Math.floor(state.minute),
      message: String(message || "").slice(0, 220),
    });
    state.flags[`rejection:${match.event.id}:${npcId}:${match.choice.id}`] = true;
    state.statistics.rejections = Number(state.statistics.rejections || 0) + 1;
    return {
      accepted: false,
      event: match.event,
      choice: match.choice,
      story,
      text: "对方听完了，但没有答应把这项主张带进商议。",
    };
  }
  story.influencedNpcs[npcId] = match.choice.id;
  story.influenceHistory.push({
    npcId,
    choiceId: match.choice.id,
    accepted: true,
    day: state.day,
    minute: Math.floor(state.minute),
    message: String(message || "").slice(0, 220),
  });
  state.flags[`influence:${match.event.id}:${npcId}:${match.choice.id}`] = true;
  state.statistics.influences = Number(state.statistics.influences || 0) + 1;
  return {
    accepted: true,
    event: match.event,
    choice: match.choice,
    story,
    text: match.social.acceptTextByNpc?.[npcId]
      || (match.social.npcIds?.[0] === npcId ? match.social.acceptText : "")
      || `${(content.npcs || []).find((npc) => npc.id === npcId)?.name || "对方"}没有替其他人答应，只说会把你的主张带进商议。`,
  };
}

export function recordNpcStoryInfluence(state, content, npcId, message, intent = "custom", accepted = true) {
  return commitNpcStoryProposal(
    state,
    content,
    npcId,
    message,
    matchNpcStoryProposal(state, content, npcId, message, intent),
    accepted,
  );
}

export function recordNpcStoryInfluenceByChoice(state, content, npcId, eventId, choiceId, message, accepted = true) {
  const match = eligibleSocialChoices(state, content, npcId)
    .find((item) => item.event.id === eventId && item.choice.id === choiceId);
  return commitNpcStoryProposal(state, content, npcId, message, match, accepted);
}

export function getNpcStoryContext(state, content, npcId) {
  const facts = [];
  const npcState = state.npcs?.[npcId];
  (content.events || []).forEach((event) => {
    const story = ensureStoryState(state, event);
    if (story.status === "active") {
      if (npcState?.regionId === (event.regionId || event.region)) {
        (event.story?.signs || []).forEach((sign) => facts.push(`公共迹象：${sign.description}`));
      }
      (event.story?.rumors || []).filter((rumor) => (
        rumor.npcId === npcId
        && Number(npcState?.relationship || 0) >= Number(rumor.minRelationship || 0)
        && requirementsMet(rumor, state).ok
      )).forEach((rumor) => facts.push(`你可以透露：${rumor.text}`));
      eligibleSocialChoices(state, content, npcId)
        .filter((item) => item.event.id === event.id)
        .forEach((item) => facts.push(`你正在权衡：${item.social.topic || item.choice.label}`));
    } else if (story.status === "resolved" && storyParticipants(event).includes(npcId)) {
      const outcome = (event.choices || []).find((choice) => choice.id === story.outcomeId);
      if (outcome) facts.push(`你亲历的结果：${event.title}最终形成「${outcome.label}」。${outcome.outcome || ""}`);
    }
  });
  return facts.slice(0, 8);
}

export function getStoryLandmarks(state, content, scene) {
  if (!scene) return [];
  const result = [];
  (content.events || []).forEach((event) => {
    const story = ensureStoryState(state, event);
    const items = story.status === "active"
      ? (event.story?.signs || [])
      : story.status === "resolved"
        ? (event.story?.aftermath?.[story.outcomeId] || [])
        : [];
    items.filter((item) => item.sceneId === scene.id).forEach((item) => result.push({
      ...item,
      id: `story-${event.id}-${story.status}-${item.id}`,
      interactive: true,
      collision: false,
      layer: item.layer || "object",
      storyEventId: event.id,
      storyClue: item.clue || item.id,
      storyPhase: story.status,
    }));
  });
  return result;
}

export function dueEvents(state, content) {
  return (content.events || []).filter((event) => {
    const story = ensureStoryState(state, event);
    return story.status !== "resolved" && currentStoryClock(state) >= eventResolutionClock(event);
  });
}

export function advanceWorld(state, content, minutes) {
  if (!Number.isFinite(minutes) || minutes <= 0 || state.endingId) return { logs: [], events: [], storyChanges: [] };
  const logs = [];
  const storyChanges = [];
  normalizeStoryState(state, content);
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
    storyChanges.push(...advanceStoryEvents(state, content, hour * 60));
  }
  state.day = Math.floor(afterAbsolute / 1440) + 1;
  state.minute = Math.floor(afterAbsolute % 1440);
  syncNpcSchedules(state, content);
  storyChanges.push(...advanceStoryEvents(state, content, afterAbsolute));
  return { logs, events: [], storyChanges };
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
  if (state.mode !== "observer" || options.actor === "world") {
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
  const memory = isAutonomous
    ? choice.autonomousMemory || (options.influenced
      ? `在「${event.title}」中，我们经过各自的争论形成了「${choice.label}」；此前的谈话也改变了部分人的立场。`
      : `在「${event.title}」中，我们经过各自的争论形成了「${choice.label}」。`)
    : choice.memory || `在「${event.title}」中，旅行者选择了：${choice.label}。`;
  const involved = storyParticipants(event).length
    ? storyParticipants(event)
    : (content.npcs || []).filter((npc) => (npc.regionId || npc.region) === event.regionId || (npc.regionId || npc.region) === event.region).map((npc) => npc.id);
  // Outcome knowledge belongs to participants, but only an actual conversation
  // with the player becomes an enduring core memory.
  involved.forEach((npcId) => remember(state, npcId, memory, "event", isAutonomous ? 2 : 3));
  if (!options.silent && !options.storyProcess) {
    const subject = isAutonomous ? "当地人最终形成了" : "你选择了";
    addJournal(state, `${event.title}：${subject}「${choice.label}」。${choice.outcome || "世界的走向因此发生了变化。"}`, "event", { eventId: event.id, choiceId: choice.id, autonomous: isAutonomous });
  }
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
  const allStoriesResolved = (content.events || []).every((event) => ensureStoryState(state, event).status === "resolved");
  return !state.endingId && state.day >= endingDay && state.minute >= endingMinute && allStoriesResolved;
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
