import { AudioManager } from "./audio.js";
import { WorldRenderer, movePlayer, nearestLandmark, nearestNpc, nearestPortal, resolveScene, updateNpcMovement } from "./renderer.js";
import {
  addJournal,
  advanceStoryEvents,
  advanceWorld,
  createInitialState,
  discoverStoryClue,
  getNpcActionOptions,
  getNpcStoryCandidates,
  getNpcStoryContext,
  getNpcStoryProposal,
  getStoryConversationTopics,
  normalizeStoryState,
  observeRegion,
  recordNpcStoryInfluenceByChoice,
  remember,
  requirementsMet,
  revealNpcStoryKnowledge,
  resolveEnding,
  shouldResolveEnding,
  syncNpcSchedules,
  transitionToPlace,
} from "./simulation.js";
import { GameUI } from "./ui.js";
import { clamp, deepClone, pick } from "./utils.js";

const SAVE_KEY = "ember_echoes.save.v1";
const META_KEY = "ember_echoes.meta.v1";
const MINUTES_PER_SECOND = 8;

function readStorage(key, fallback) {
  try {
    const value = window.localStorage.getItem(key);
    return value ? JSON.parse(value) : fallback;
  } catch (error) {
    console.warn(`Unable to read ${key}`, error);
    return fallback;
  }
}

function writeStorage(key, value) {
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
    return true;
  } catch (error) {
    console.warn(`Unable to save ${key}`, error);
    return false;
  }
}

export class Game {
  constructor(content, aiService) {
    this.content = content;
    this.ai = aiService;
    this.canvas = document.getElementById("game-canvas");
    this.renderer = new WorldRenderer(this.canvas, content);
    this.audio = new AudioManager();
    this.state = null;
    this.meta = readStorage(META_KEY, { endings: [], sound: true, llm: false, thoughts: false });
    this.keys = new Set();
    this.modalOpen = false;
    this.lastFrame = performance.now();
    this.uiAccumulator = 0;
    this.timeRemainder = 0;
    this.stepTimer = 0;
    this.autosaveTimer = 0;
    this.activeConversation = null;
    this.conversationSession = 0;
    this.planningPromise = null;
    this.nearby = null;
    this.nearbyLandmark = null;
    this.nearbyPortal = null;
    this.nearbyInteraction = null;
    this.transitionLock = false;
    this.ui = new GameUI(content, this.createCallbacks());
    this.bindInput();
    this.audio.setEnabled(this.meta.sound !== false);
    this.ui.setSoundEnabled(this.audio.enabled);
    this.ui.elements.thought_toggle.checked = Boolean(this.meta.thoughts);
  }

  createCallbacks() {
    return {
      onNewGame: (timelineId, mode) => this.startNewGame(timelineId, mode),
      onContinue: () => this.continueGame(),
      onSave: () => this.save(true),
      onSpeed: (speed) => this.setSpeed(speed),
      onToggleSound: () => this.toggleSound(),
      onModalChange: (open, id) => this.onModalChange(open, id),
      onTravel: (regionId) => this.travel(regionId),
      onWait: () => this.waitOneHour(),
      onTalk: (message, intent) => this.talk(message, intent),
      onInspectNpc: (npcId) => this.inspectNpc(npcId),
      onToggleLlm: (enabled) => this.toggleLlm(enabled),
      onToggleThoughts: (enabled) => this.toggleThoughts(enabled),
      onKeepWandering: () => this.keepWandering(),
      getUnlockedEndings: () => this.meta.endings || [],
    };
  }

  async initialize() {
    const saved = readStorage(SAVE_KEY, null);
    this.ui.finishLoading(Boolean(saved), saved?.mode === "observer" ? "observer" : "player");
    let backend = { configured: false };
    try {
      backend = await this.ai.checkBackend();
    } catch (error) {
      console.info("LLM backend unavailable; using local brain.", error);
    }
    this.ui.updateAiStatus(backend);
    this.ai.setEnabled?.(Boolean(this.meta.llm && backend.configured));
    this.ui.setLlmEnabled(Boolean(this.meta.llm && backend.configured));
    requestAnimationFrame((time) => this.loop(time));
  }

  startNewGame(timelineId, mode = "player") {
    this.state = createInitialState(this.content, timelineId, mode);
    this.state.speed = this.state.mode === "observer" ? 4 : 1;
    this.activeConversation = null;
    this.ui.showGame();
    this.ui.showLocation(this.currentRegion(), this.currentScene());
    this.ui.update(this.state, null);
    this.ui.setSpeedIndicator(this.state.speed);
    this.canvas.focus();
    this.audio.play("event");
    this.save(false);
    this.maybeRefreshStrategicPlans();
    this.ui.toast(this.state.mode === "observer"
      ? `开始观察「${this.state.timelineName}」：世界中没有玩家。`
      : `世界线「${this.state.timelineName}」已开始。`, "success");
  }

  continueGame() {
    const saved = readStorage(SAVE_KEY, null);
    if (!saved) {
      this.ui.toast("没有找到可用存档。", "error");
      return;
    }
    try {
      this.state = this.normalizeLoadedState(saved);
      this.ui.showGame();
      this.ui.showLocation(this.currentRegion(), this.currentScene());
      this.ui.update(this.state, this.state.mode === "observer" ? null : nearestNpc(this.state, this.content));
      this.ui.setSpeedIndicator(this.state.speed);
      this.canvas.focus();
      if (this.state.endingId && !this.state.endingShown) {
        const ending = this.content.endings.find((item) => item.id === this.state.endingId);
        if (ending) this.ui.showEnding(ending, this.state);
      }
      this.maybeRefreshStrategicPlans();
    } catch (error) {
      console.error(error);
      this.ui.toast("存档版本不兼容，请开启一条新世界线。", "error");
    }
  }

  normalizeLoadedState(saved) {
    const mode = saved.mode === "observer" ? "observer" : "player";
    const fresh = createInitialState(this.content, saved.timelineId, mode);
    const merged = { ...fresh, ...saved };
    merged.mode = mode;
    merged.timelineName = fresh.timelineName;
    merged.difficulty = fresh.difficulty;
    merged.player = { ...fresh.player, ...(saved.player || {}) };
    merged.player.present = mode !== "observer";
    merged.observer = { ...fresh.observer, ...(saved.observer || {}) };
    const savedContentVersion = Number(saved.contentVersion || 1);
    const savedRegion = this.content.regions.find((item) => item.id === merged.regionId) || this.content.regions[0];
    const savedPlaceId = saved.placeId || merged.regionId;
    const savedPlace = resolveScene(this.content, savedRegion.id, savedPlaceId);
    merged.regionId = savedRegion.id;
    merged.placeId = savedPlace?.id || savedRegion.id;
    if (savedContentVersion < 2) {
      merged.placeId = savedRegion.id;
      merged.player.x = Number(savedRegion.spawn?.x ?? 384);
      merged.player.y = Number(savedRegion.spawn?.y ?? 390);
    }
    merged.metrics = { ...fresh.metrics, ...(saved.metrics || {}) };
    merged.factions = { ...fresh.factions, ...(saved.factions || {}) };
    merged.flags = { ...fresh.flags, ...(saved.flags || {}) };
    merged.flags.playerArrived = mode !== "observer";
    merged.flags.observerWorld = mode === "observer";
    merged.statistics = { ...fresh.statistics, ...(saved.statistics || {}) };
    merged.story = { ...fresh.story, ...(saved.story || {}) };
    merged.npcs = { ...fresh.npcs };
    Object.entries(saved.npcs || {}).forEach(([id, npcState]) => {
      if (merged.npcs[id]) {
        const memories = npcState.memories || merged.npcs[id].memories;
        const legacyCore = memories.filter((memory) => Number(memory?.importance || 0) >= 3);
        merged.npcs[id] = {
          ...merged.npcs[id],
          ...npcState,
          memories,
          coreMemories: npcState.coreMemories || legacyCore || merged.npcs[id].coreMemories || [],
        };
      }
    });
    merged.pendingEvents = [];
    merged.completedEvents = saved.completedEvents || [];
    merged.journal = saved.journal || fresh.journal;
    merged.spokenNpcIds = saved.spokenNpcIds || [];
    merged.visitedRegions = saved.visitedRegions || [saved.regionId || fresh.regionId];
    merged.visitedPlaces = saved.visitedPlaces || [...merged.visitedRegions];
    Object.values(merged.npcs).forEach((npcState) => {
      npcState.placeId ||= npcState.regionId;
    });
    syncNpcSchedules(merged, this.content);
    normalizeStoryState(merged, this.content);
    if (Number(saved.version || 2) < 3) {
      const completed = new Set(saved.completedEvents || []);
      const pending = new Set(saved.pendingEvents || []);
      (this.content.events || []).forEach((event) => {
        const story = merged.story[event.id];
        if (completed.has(event.id) || saved.flags?.[`event:${event.id}`]) {
          story.processKnown = true;
          story.outcomeKnown = true;
          story.discovered = true;
        } else if (pending.has(event.id)) {
          story.processKnown = true;
          story.discovered = true;
        }
      });
    }
    // Old saves may have stopped on a pending choice screen. The social world
    // now settles every already-due process immediately and never reopens it.
    advanceStoryEvents(merged, this.content);
    merged.version = 3;
    merged.contentVersion = this.content.game?.contentVersion || 2;
    return merged;
  }

  bindInput() {
    window.addEventListener("keydown", (event) => {
      const tag = event.target?.tagName;
      const typing = tag === "INPUT" || tag === "TEXTAREA";
      if (!this.ui.elements.title_screen.classList.contains("hidden")) return;
      if (!typing && ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", " "].includes(event.key)) event.preventDefault();
      if (typing && event.key !== "Escape") return;
      const key = event.key.toLowerCase();
      if (this.state && ["w", "a", "s", "d", "arrowup", "arrowdown", "arrowleft", "arrowright"].includes(key)) this.keys.add(key);
      if (event.repeat) return;
      if (key === "e" && !this.modalOpen && !this.transitionLock && this.state?.mode !== "observer") this.interact();
      else if (key === "m" && this.state && !this.modalOpen && !this.transitionLock) this.ui.showMap();
      else if (key === "j" && this.state && !this.modalOpen && !this.transitionLock) this.ui.showJournal();
      else if (key === "b" && this.state && !this.modalOpen && !this.transitionLock) this.ui.toggleSidebar();
      else if (key === "escape") this.ui.closeTopModal();
      else if (["1", "2", "3", "4", "5"].includes(key) && this.state && !this.modalOpen && !this.transitionLock) {
        const speed = [0, 1, 2, 4, 8][Number(key) - 1];
        document.querySelector(`[data-speed="${speed}"]`)?.click();
      }
    });
    window.addEventListener("keyup", (event) => this.keys.delete(event.key.toLowerCase()));
    window.addEventListener("blur", () => this.keys.clear());
    this.canvas.addEventListener("pointerdown", () => this.canvas.focus());
  }

  loop(now) {
    const delta = Math.min(.05, Math.max(0, (now - this.lastFrame) / 1000));
    this.lastFrame = now;
    if (this.state) {
      this.update(delta);
      this.renderer.render(this.state, delta);
    }
    requestAnimationFrame((time) => this.loop(time));
  }

  update(delta) {
    const scene = this.currentScene();
    const observer = this.state.mode === "observer";
    const canMove = !this.modalOpen && !this.transitionLock;
    let dx = 0;
    let dy = 0;
    if (canMove) {
      if (this.keys.has("a") || this.keys.has("arrowleft")) dx -= 1;
      if (this.keys.has("d") || this.keys.has("arrowright")) dx += 1;
      if (this.keys.has("w") || this.keys.has("arrowup")) dy -= 1;
      if (this.keys.has("s") || this.keys.has("arrowdown")) dy += 1;
    }
    if (dx && dy) { dx *= Math.SQRT1_2; dy *= Math.SQRT1_2; }
    const moving = Boolean(dx || dy);
    if (moving && observer) {
      const panSpeed = 310;
      this.state.observer.focusedNpcId = null;
      this.state.observer.cameraX = clamp(Number(this.state.observer.cameraX ?? Number(scene.width || 768) / 2) + dx * panSpeed * delta, 0, Number(scene.width || 768));
      this.state.observer.cameraY = clamp(Number(this.state.observer.cameraY ?? Number(scene.height || 480) / 2) + dy * panSpeed * delta, 0, Number(scene.height || 480));
    } else if (moving) {
      if (Math.abs(dx) > Math.abs(dy)) this.state.player.facing = dx > 0 ? "right" : "left";
      else this.state.player.facing = dy > 0 ? "down" : "up";
      movePlayer(this.state, scene, dx * this.state.player.speed * delta, dy * this.state.player.speed * delta);
      this.stepTimer -= delta;
      if (this.stepTimer <= 0) { this.audio.play("step"); this.stepTimer = .34; }
    }
    this.renderer.setMoving(moving && !observer);
    if (!this.modalOpen && !this.state.endingId && this.state.speed > 0) {
      updateNpcMovement(this.state, this.content, delta * Math.min(4, Math.max(1, this.state.speed)));
    }

    const modalTimeScale = observer || !this.modalOpen ? 1 : this.activeConversation ? .15 : 0;
    if (!this.state.endingId && modalTimeScale > 0 && this.state.speed > 0) {
      this.timeRemainder += delta * MINUTES_PER_SECOND * this.state.speed * modalTimeScale;
      if (this.timeRemainder >= 1) {
        const minutes = Math.floor(this.timeRemainder);
        this.timeRemainder -= minutes;
        this.advance(minutes);
      }
    }

    this.autosaveTimer += delta;
    if (this.autosaveTimer > 25) { this.save(false); this.autosaveTimer = 0; }
    this.uiAccumulator += delta;
    if (this.uiAccumulator > .16) {
      this.refreshNearbyInteraction(scene);
      this.ui.update(this.state, this.nearby);
      this.ui.setInteraction(this.nearbyInteraction);
      this.uiAccumulator = 0;
    }
  }

  refreshNearbyInteraction(scene = this.currentScene()) {
    if (!this.state || this.state.mode === "observer") {
      this.nearby = null;
      this.nearbyLandmark = null;
      this.nearbyPortal = null;
      this.nearbyInteraction = null;
      return null;
    }
    this.nearby = nearestNpc(this.state, this.content);
    this.nearbyLandmark = nearestLandmark(this.state, scene, 48, this.content);
    this.nearbyPortal = nearestPortal(this.state, scene);
    const candidates = [];
    if (this.nearby) candidates.push({ kind: "npc", prompt: `与 ${this.nearby.profile.name} 交谈`, distance: this.nearby.distance, ...this.nearby });
    if (this.nearbyLandmark) candidates.push({ kind: "landmark", prompt: `调查 ${this.nearbyLandmark.name || "这里"}`, distance: this.nearbyLandmark.distance, landmark: this.nearbyLandmark });
    if (this.nearbyPortal) candidates.push({ kind: this.nearbyPortal.kind || "portal", prompt: this.nearbyPortal.label || "前往另一地点", distance: this.nearbyPortal.distance, portal: this.nearbyPortal });
    candidates.sort((left, right) => (left.distance - (left.portal ? 4 : 0)) - (right.distance - (right.portal ? 4 : 0)));
    this.nearbyInteraction = candidates[0] || null;
    return this.nearbyInteraction;
  }

  advance(minutes) {
    const { logs, storyChanges } = advanceWorld(this.state, this.content, minutes);
    logs.forEach((log) => {
      const playerCanWitness = this.state.mode === "observer"
        || (log.regionId === this.state.regionId && (log.placeId || log.regionId) === (this.state.placeId || this.state.regionId));
      if (!playerCanWitness) return;
      addJournal(this.state, log.text, "npc", { npcId: log.npcId });
      if (this.meta.thoughts && log.reason) addJournal(this.state, `思考：${log.reason}`, "thought", { npcId: log.npcId });
    });
    this.maybeRefreshStrategicPlans();
    if (storyChanges.length) this.save(false);
    if (shouldResolveEnding(this.state, this.content)) this.finishTimeline();
  }

  finishTimeline() {
    const ending = resolveEnding(this.state, this.content);
    if (!this.meta.endings.includes(ending.id)) this.meta.endings.push(ending.id);
    this.meta.lastEnding = ending.id;
    this.meta.timelinesCompleted = Number(this.meta.timelinesCompleted || 0) + 1;
    writeStorage(META_KEY, this.meta);
    this.audio.play("ending");
    this.ui.showEnding(ending, this.state);
    this.save(false);
  }

  keepWandering() {
    if (!this.state) return;
    this.state.endingShown = true;
    this.state.speed = 0;
    document.querySelector('[data-speed="0"]')?.click();
    this.ui.toast(this.state.mode === "observer"
      ? "时间停在结局前夜。你仍可查看五地与每位居民的最终状态。"
      : "时间停在结局前夜。你仍可与这里的人告别。", "info");
    this.save(false);
  }

  interact() {
    if (!this.state || this.state.mode === "observer") return;
    const interaction = this.refreshNearbyInteraction();
    if (!interaction) return;
    if (interaction.kind === "npc") this.openConversation(interaction.profile, interaction.state);
    else if (interaction.kind === "landmark") this.inspectLandmark(interaction.landmark);
    else if (interaction.portal) this.usePortal(interaction.portal);
  }

  openConversation(npc, npcState) {
    if (this.state?.mode === "observer") return;
    npcState.knownToPlayer = true;
    const session = ++this.conversationSession;
    this.activeConversation = { npc, npcState, session };
    const disclosure = revealNpcStoryKnowledge(this.state, this.content, npc.id);
    const storyTopics = getStoryConversationTopics(this.state, this.content, npc.id);
    const greetings = npc.dialogue?.greetings || npc.dialogue?.greeting || npc.greetings || [];
    const greetingList = Array.isArray(greetings) ? greetings : [greetings];
    const greeting = pick(greetingList, () => ((npcState.conversations * 37) % 100) / 100) || npc.intro || `我是${npc.name}。你似乎带着不属于这里的时间。`;
    this.ui.openConversation(npc, npcState, greeting, storyTopics);
    this.ui.setConversationBusy(false);
    if (disclosure) {
      this.ui.addSpeech(disclosure.text, "npc");
      remember(this.state, npc.id, disclosure.memory, "conversation", 3);
      this.save(false);
    }
    this.audio.play("talk");
    remember(this.state, npc.id, `旅行者在${this.currentScene().name || this.currentRegion().name}与我交谈。`, "chat", 1);
  }

  inspectNpc(npcId) {
    if (!this.state) return;
    const npc = this.content.npcs.find((item) => item.id === npcId);
    const npcState = this.state.npcs[npcId];
    if (this.state.mode === "observer") {
      if (!npc || !npcState) return;
      this.state.regionId = npcState.regionId;
      this.state.placeId = npcState.placeId || npcState.regionId;
      this.state.observer.focusedNpcId = npcId;
      this.state.observer.cameraX = npcState.x;
      this.state.observer.cameraY = npcState.y;
      this.ui.showLocation(this.currentRegion(), this.currentScene());
      this.ui.showNpcObservation(npc, npcState);
      this.ui.update(this.state, null);
      return;
    }
    if (!npc || !npcState?.knownToPlayer) {
      this.ui.toast("你还没有与这位居民见过面。");
      return;
    }
    if (npcState.regionId !== this.state.regionId || (npcState.placeId || npcState.regionId) !== (this.state.placeId || this.state.regionId)) {
      const location = this.ui.describeLocation(npcState.regionId, npcState.placeId);
      this.ui.toast(`${npc.name}目前在${location.title}，正在${npcState.activity}。`);
      return;
    }
    this.openConversation(npc, npcState);
  }

  async talk(message, intent = "custom") {
    if (this.state?.mode === "observer" || !this.activeConversation || !message) return;
    const { npc, npcState, session } = this.activeConversation;
    const keywordProposal = getNpcStoryProposal(this.state, this.content, npc.id, message, intent);
    const storyCandidates = intent === "custom" || intent === "story"
      ? getNpcStoryCandidates(this.state, this.content, npc.id)
      : [];
    const candidateByAction = new Map();
    const allowedStoryActions = storyCandidates.flatMap((candidate) => {
      const actionSuffix = `${candidate.event.id}:${candidate.choice.id}`;
      const context = [
        candidate.choice.label,
        candidate.social.topic,
        candidate.social.playerLine,
        ...(candidate.social.keywords || []),
      ].filter(Boolean).join("；");
      candidateByAction.set(`endorse:${actionSuffix}`, { ...candidate, accepted: true });
      candidateByAction.set(`refuse:${actionSuffix}`, { ...candidate, accepted: false });
      return [
        { id: `endorse:${actionSuffix}`, label: `接受这项主张：${context}` },
        { id: `refuse:${actionSuffix}`, label: `拒绝这项主张：${context}` },
      ];
    });
    const decisionNpc = storyCandidates.length ? {
      ...npc,
      allowedActions: [
        ...allowedStoryActions,
        { id: "continue_conversation", label: "玩家还没有提出足够明确的主张，继续追问" },
      ],
    } : npc;
    const decisionIntent = storyCandidates.length ? "story" : intent;
    this.ui.addSpeech(message, "player");
    this.ui.setConversationBusy(true);
    try {
      const result = await this.ai.talk(decisionNpc, npcState, this.publicWorldState(npc.id), message, decisionIntent);
      if (!this.activeConversation || this.activeConversation.session !== session) return;
      npcState.conversations = Number(npcState.conversations || 0) + 1;
      this.state.statistics.conversationTurns = Number(this.state.statistics.conversationTurns || 0) + 1;
      this.state.spokenNpcIds ||= [];
      if (!this.state.spokenNpcIds.includes(npc.id)) this.state.spokenNpcIds.push(npc.id);
      this.state.statistics.conversations = Math.max(
        Number(this.state.statistics.conversations || 0),
        this.state.spokenNpcIds.length,
      );
      this.ui.setConversationBusy(false);
      this.ui.addSpeech(result.reply, "npc");
      this.ui.setConversationProvider(result.provider, result.providerDetail || "");
      const classifiedProposal = candidateByAction.get(String(result.action || ""));
      const proposal = classifiedProposal || (keywordProposal && ["accept_argument", "refuse_argument"].includes(result.action)
        ? { ...keywordProposal, accepted: result.action === "accept_argument" }
        : null);
      const influence = proposal
        ? recordNpcStoryInfluenceByChoice(
          this.state,
          this.content,
          npc.id,
          proposal.event.id,
          proposal.choice.id,
          message,
          proposal.accepted,
        )
        : null;
      const acceptedInfluence = influence?.accepted === true;
      remember(
        this.state,
        npc.id,
        result.memory || `旅行者对我说：“${message.slice(0, 80)}”`,
        "chat",
        proposal ? 3 : intent === "secret" ? 2 : 1,
      );
      if (influence) {
        const hasAnotherApproach = getNpcStoryCandidates(this.state, this.content, npc.id)
          .some((candidate) => candidate.event.id === influence.event.id);
        const storyButton = [...this.ui.elements.conversation_actions.querySelectorAll("[data-story-topic]")]
          .find((button) => button.textContent.includes(influence.event.title));
        if (storyButton && !hasAnotherApproach) {
          storyButton.disabled = true;
          storyButton.textContent = `${storyButton.textContent} · 已谈过`;
        }
      }
      if (acceptedInfluence) {
        this.ui.addSpeech(influence.text, "npc");
        remember(
          this.state,
          npc.id,
          `关于「${influence.event.title}」，旅行者向我主张「${influence.choice.label}」。我答应把这项主张带进之后的商议。`,
          "promise",
          3,
        );
      } else if (influence) {
        remember(
          this.state,
          npc.id,
          `关于「${influence.event.title}」，旅行者向我主张「${influence.choice.label}」，但我拒绝替这项办法背书。`,
          "refusal",
          3,
        );
      }
      const relationshipDelta = this.relationshipDelta(proposal ? "story" : intent, result.action, npcState);
      npcState.relationship = clamp(npcState.relationship + relationshipDelta, -100, 100);
      npcState.mood = relationshipDelta > 1 ? "愿意继续听你说" : relationshipDelta < 0 ? "语气变得谨慎" : npcState.mood;
      addJournal(
        this.state,
        acceptedInfluence
          ? `你没有替任何人作决定；${npc.name}答应把你关于「${influence.choice.label}」的主张带进「${influence.event.title}」的商议。`
          : proposal && influence
            ? `${npc.name}听完了你对「${proposal.choice.label}」的主张，但没有作出承诺。`
            : proposal
              ? `谈话还没有结束，「${proposal.event.title}」却已经在别处形成了结果。`
            : `你与${npc.name}谈到${this.intentLabel(intent)}。`,
        "player",
        { npcId: npc.id, eventId: influence?.event.id, choiceId: influence?.choice.id },
      );
      if (this.meta.thoughts && result.reason) addJournal(this.state, `${npc.name}的思考：${result.reason}`, "thought", { npcId: npc.id });
      if (intent === "secret" && npcState.relationship >= Number(npc.secretTrust || 55)) this.state.flags[`secret:${npc.id}`] = true;
      this.advance(proposal ? 8 : 6);
      this.save(false);
    } catch (error) {
      console.error(error);
      if (this.activeConversation?.session === session) {
        this.ui.addSpeech("……星辉干扰了我的思绪。我们稍后再谈吧。", "npc");
        this.ui.setConversationProvider("local", "回复失败");
      }
    } finally {
      if (this.activeConversation?.session === session) this.ui.setConversationBusy(false);
    }
  }

  publicWorldState(npcId = null) {
    const observer = this.state.mode === "observer";
    const timeline = this.content.timelines.find((item) => item.id === this.state.timelineId);
    const publicFlagIds = new Set([
      "playerArrived",
      "observerWorld",
      ...Object.keys(timeline?.modifiers?.flags || {}),
    ]);
    const npcState = npcId ? this.state.npcs?.[npcId] : null;
    const npcRegion = npcState
      ? this.content.regions.find((item) => item.id === npcState.regionId)
      : this.currentRegion();
    const npcScene = npcState
      ? resolveScene(this.content, npcState.regionId, npcState.placeId || npcState.regionId)
      : this.currentScene();
    const personalMemories = [
      ...(npcState?.coreMemories || []),
      ...(npcState?.memories || []),
    ].filter((memory, index, list) => list.findIndex((item) => item.text === memory.text) === index).slice(0, 8);
    return {
      mode: this.state.mode,
      player_present: !observer,
      timeline: this.state.timelineName,
      day: this.state.day,
      minute: this.state.minute,
      region: npcRegion?.name || npcState?.regionId || "未知地区",
      place: npcScene?.name || npcRegion?.name || npcState?.placeId || "未知地点",
      weather: this.state.weather,
      metrics: deepClone(this.state.metrics),
      factions: deepClone(this.state.factions),
      flags: Object.fromEntries(Object.entries(this.state.flags).filter(([key]) => publicFlagIds.has(key))),
      story_context: npcId ? getNpcStoryContext(this.state, this.content, npcId) : [],
      recent_events: npcId ? personalMemories.map((memory) => memory.text) : [],
    };
  }

  relationshipDelta(intent, action, npcState = null) {
    const base = { greet: 1, help: 4, rumor: 1, secret: 0, challenge: -1, story: 1, custom: 1 }[intent] ?? 0;
    const actionDelta = {
      thank: 2,
      trust: 2,
      confide: 3,
      refuse: -1,
      warn: 0,
      remember: 1,
      accept_argument: 1,
      refuse_argument: -1,
    }[action] ?? 0;
    const raw = base + actionDelta;
    if (!npcState || raw <= 0) return raw;
    const gain = npcState.dailyRelationshipGain?.day === this.state.day
      ? npcState.dailyRelationshipGain
      : { day: this.state.day, value: 0 };
    const applied = Math.min(raw, Math.max(0, 8 - Number(gain.value || 0)));
    gain.value = Number(gain.value || 0) + applied;
    npcState.dailyRelationshipGain = gain;
    return applied;
  }

  intentLabel(intent) {
    return { greet: "近况", help: "如何提供帮助", rumor: "最近的传闻", secret: "未公开的秘密", challenge: "彼此的立场", story: "正在形成的公共议题", custom: "一些只属于此刻的话" }[intent] || "近况";
  }

  inspectLandmark(landmark) {
    if (this.state?.mode === "observer") return;
    const flag = `landmark:${this.state.regionId}:${this.state.placeId || this.state.regionId}:${landmark.id || landmark.name}`;
    const firstVisit = !this.state.flags[flag];
    this.state.flags[flag] = true;
    const text = landmark.description || `${landmark.name || "这处遗迹"}沉默地记录着世界的变化。`;
    this.ui.toast(text, firstVisit ? "success" : "info");
    if (firstVisit) {
      addJournal(this.state, `你调查了${landmark.name || "一处地标"}：${text}`, "player");
      if (landmark.flag) this.state.flags[landmark.flag] = true;
      if (landmark.storyEventId) {
        discoverStoryClue(this.state, this.content, landmark.storyEventId, landmark.storyClue, "landmark");
      }
      this.save(false);
    }
    this.audio.play("talk");
  }

  usePortal(portal) {
    if (!this.state || this.state.mode === "observer" || this.transitionLock || !portal?.target) return;
    if (portal.access) {
      const allRules = portal.access.all || [];
      const anyRules = portal.access.any || [];
      const allPass = allRules.every((rule) => requirementsMet({ requirements: [rule] }, this.state).ok);
      const anyPass = !anyRules.length || anyRules.some((rule) => requirementsMet({ requirements: [rule] }, this.state).ok);
      if (!allPass || !anyPass) {
        this.ui.toast(portal.access.denied || "守门人没有让开。你需要先得到这里某个人的信任。", "info");
        this.audio.play("talk");
        return;
      }
    }
    const sourceRegionId = this.state.regionId;
    const sourcePlaceId = this.state.placeId || sourceRegionId;
    const target = portal.target;
    const minutes = Math.max(0, Number(portal.minutes || 0));
    const crossRegion = target.regionId !== sourceRegionId;
    const isTransport = crossRegion || minutes > 0 || ["carriage", "caravan", "lift", "road", "trail", "boat"].includes(portal.kind);
    const targetRegion = this.content.regions.find((item) => item.id === target.regionId);
    const targetScene = resolveScene(this.content, target.regionId, target.placeId || target.regionId);
    if (!targetRegion || !targetScene) {
      this.ui.toast("这条道路暂时无法通行。", "error");
      return;
    }

    this.setTransitionLock(true);
    this.keys.clear();
    this.audio.play(isTransport ? "travel" : "step");
    this.ui.flashTravel(() => {
      try {
        if (!this.state || this.state.regionId !== sourceRegionId || (this.state.placeId || sourceRegionId) !== sourcePlaceId) return;
        const firstVisit = !(this.state.visitedPlaces || []).includes(targetScene.id);
        const journalText = isTransport
          ? `${portal.label || "沿路前行"}，抵达${targetRegion.name}${targetScene.id === targetRegion.id ? "" : `的${targetScene.name}`}。`
          : firstVisit ? `你第一次进入${targetScene.name || "这间屋子"}。` : "";
        const changed = transitionToPlace(this.state, this.content, target, {
          countJourney: isTransport,
          journalText,
        });
        if (!changed) return;
        this.state.statistics.doorUses = Number(this.state.statistics.doorUses || 0) + (isTransport ? 0 : 1);
        this.state.statistics.transportTrips = Number(this.state.statistics.transportTrips || 0) + (isTransport ? 1 : 0);
        this.nearby = null;
        this.nearbyLandmark = null;
        this.nearbyPortal = null;
        this.nearbyInteraction = null;
        this.ui.showLocation(this.currentRegion(), this.currentScene());
        if (minutes > 0) this.advance(minutes);
        this.ui.update(this.state, null);
        this.ui.setInteraction(null);
        this.save(false);
        this.canvas.focus();
        this.ui.toast(minutes > 0 ? `${portal.label}，用时 ${minutes} 分钟。` : `来到${targetScene.name || targetRegion.name}。`, "info");
      } finally {
        this.setTransitionLock(false);
      }
    });
  }

  travel(regionId) {
    if (!this.state || this.transitionLock) return;
    if (this.state.mode !== "observer") {
      this.ui.toast("地图只用于查看路线；请从场景中的城门或交通点出发。", "info");
      return;
    }
    const sourceRegionId = this.state.regionId;
    const sourcePlaceId = this.state.placeId || sourceRegionId;
    const returningToOutdoor = regionId === sourceRegionId && sourcePlaceId !== sourceRegionId;
    if (regionId === sourceRegionId && !returningToOutdoor) return;
    this.setTransitionLock(true);
    this.keys.clear();
    this.ui.closeModal("map-modal", true);
    this.audio.play("travel");
    this.ui.flashTravel(() => {
      try {
        if (!this.state
          || this.state.mode !== "observer"
          || this.state.regionId !== sourceRegionId
          || (this.state.placeId || sourceRegionId) !== sourcePlaceId) return;
        const changed = observeRegion(this.state, this.content, regionId);
        if (!changed) return;
        const region = this.currentRegion();
        this.ui.showLocation(region, this.currentScene());
        this.ui.update(this.state, null);
        this.save(false);
        this.canvas.focus();
      } finally {
        this.setTransitionLock(false);
      }
    });
  }

  setTransitionLock(locked) {
    this.transitionLock = Boolean(locked);
    this.ui?.setTransitionLocked(this.transitionLock);
  }

  waitOneHour() {
    if (!this.state || this.modalOpen || this.state.endingId) return;
    this.advance(60);
    this.ui.toast(this.state.mode === "observer"
      ? "世界向前运行了一小时，居民继续各自的生活。"
      : "你在附近停留了一小时。世界并没有停下来。", "info");
    this.save(false);
  }

  setSpeed(speed) {
    if (!this.state) return;
    this.state.speed = speed;
    this.ui.setSpeedIndicator(speed);
    this.ui.toast(speed === 0 ? "时间已暂停。" : `时间速度：${speed}×`);
  }

  onModalChange(open, id) {
    this.modalOpen = open;
    if (id === "conversation-modal" && !open) {
      this.conversationSession += 1;
      this.activeConversation = null;
      this.ui.setConversationBusy(false);
    }
    this.keys.clear();
  }

  toggleSound() {
    this.meta.sound = this.audio.setEnabled(!this.audio.enabled);
    this.ui.setSoundEnabled(this.meta.sound);
    if (this.meta.sound) this.audio.play("choice");
    writeStorage(META_KEY, this.meta);
  }

  toggleLlm(enabled) {
    this.meta.llm = Boolean(enabled);
    this.ai.setEnabled?.(this.meta.llm);
    writeStorage(META_KEY, this.meta);
    this.ui.toast(enabled ? "深度思考已开启：对话与每日计划会更细致。" : "已切回稳定的本地心智。", "info");
    if (enabled) this.maybeRefreshStrategicPlans();
  }

  maybeRefreshStrategicPlans() {
    if (!this.state || !this.meta.llm || !this.ai.backendEnabled || this.state.endingId || this.planningPromise) return;
    if (Number(this.state.statistics.lastLlmPlanDay || 0) >= this.state.day) return;
    const plannedState = this.state;
    const planDay = this.state.day;
    this.state.statistics.lastLlmPlanDay = planDay;
    const population = this.content.npcs;
    const offset = ((planDay - 1) * 3 + this.state.seed) % population.length;
    const planners = Array.from({ length: Math.min(3, population.length) }, (_, index) => population[(offset + index) % population.length]);
    const requests = planners.map((npc) => {
      const options = getNpcActionOptions(npc);
      const npcSnapshot = deepClone(this.state.npcs[npc.id]);
      const worldSnapshot = deepClone(this.publicWorldState(npc.id));
      delete worldSnapshot.mode;
      delete worldSnapshot.player_present;
      delete worldSnapshot.flags?.playerArrived;
      delete worldSnapshot.flags?.observerWorld;
      return this.ai.plan?.(npc, npcSnapshot, worldSnapshot, options)
        .then((result) => ({ npc, options, result }))
        .catch((error) => {
          console.info(`Daily plan for ${npc.id} fell back to local rules.`, error);
          return { npc, options, result: null };
        });
    });
    this.planningPromise = (async () => {
      const decisions = await Promise.all(requests);
      if (this.state !== plannedState || !this.meta.llm || this.state.endingId || this.state.day !== planDay) return;
      for (const { npc, options, result } of decisions) {
        const npcState = this.state.npcs[npc.id];
        if (!result || ["local", "local-rules", "rules"].includes(result.provider)) continue;
        const chosen = options.find((option) => option.id === String(result.action).trim())
          || options.find((option) => option.label === String(result.action).trim());
        if (!chosen) {
          if (this.meta.thoughts) addJournal(this.state, `${npc.name}的模型计划未通过行动校验，世界引擎保留原日程。`, "thought", { npcId: npc.id });
          continue;
        }
        npcState.strategicActionId = chosen.id;
        npcState.strategicPlanDay = planDay;
        npcState.reflection = result.reply;
        this.state.statistics.llmPlans = Number(this.state.statistics.llmPlans || 0) + 1;
        remember(this.state, npc.id, result.memory || `我决定优先${chosen.label}。`, "thought", 2);
        addJournal(this.state, `${npc.name}制定了新的战略计划：${chosen.label}。`, "npc", { npcId: npc.id, provider: result.provider });
        if (this.meta.thoughts && result.reason) addJournal(this.state, `${npc.name}的规划理由：${result.reason}`, "thought", { npcId: npc.id });
      }
      this.save(false);
    })().catch((error) => {
      console.info("Daily LLM planning fell back to local rules.", error);
    }).finally(() => {
      this.planningPromise = null;
    });
  }

  toggleThoughts(enabled) {
    this.meta.thoughts = Boolean(enabled);
    writeStorage(META_KEY, this.meta);
  }

  save(showToast = false) {
    if (!this.state) return;
    const success = writeStorage(SAVE_KEY, this.state);
    writeStorage(META_KEY, this.meta);
    if (showToast) {
      this.audio.play("save");
      this.ui.toast(success ? "世界线已保存到本机浏览器。" : "保存失败：浏览器拒绝了本地存储。", success ? "success" : "error");
    }
  }

  currentRegion() {
    return this.content.regions.find((item) => item.id === this.state?.regionId) || this.content.regions[0];
  }

  currentScene() {
    return resolveScene(this.content, this.state?.regionId, this.state?.placeId || this.state?.regionId) || this.currentRegion();
  }
}
