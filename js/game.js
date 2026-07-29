import AIService from "./ai.js";
import { AudioManager } from "./audio.js";
import {
  WorldRenderer,
  movePlayer,
  nearestLandmark,
  nearestNpc,
  nearestPortal,
  resolveScene,
  updateNpcMovement,
} from "./renderer.js";
import {
  addEvidence,
  addItem,
  addJournal,
  advanceTravel,
  advanceWorld,
  applyNpcAction,
  completeIdentityFixing,
  completePhotoDevelopment,
  createInitialState,
  getNpcActions,
  hasItem,
  installAdaPortrait,
  learn,
  markRepair,
  normalizeLoadedState,
  resetLoop,
  surfaceProtocolReady,
  syncNpcSchedules,
  syncWorldFlags,
} from "./simulation.js";
import GameUI from "./ui.js";

const KEY_BINDINGS = {
  ArrowUp: "up", w: "up", W: "up",
  ArrowDown: "down", s: "down", S: "down",
  ArrowLeft: "left", a: "left", A: "left",
  ArrowRight: "right", d: "right", D: "right",
};

const FREE_DIALOGUE_PLOT_ACTIONS = new Set([
  "exchange_room7_key",
  "ask_master_record",
  "commit_stop_clock",
  "commit_seventh_bell",
  "receive_flashlight",
  "route_surface_light",
  "route_darkroom_light",
  "develop_cave_negative",
  "identify_wrench",
  "identify_fork",
  "identify_lens",
  "identify_flashlight",
  "compare_ar_records",
  "cross_reference_ada",
  "research_return_exposure",
  "anchor_ada_name",
  "anchor_ada_residence",
  "anchor_ada_duty",
  "anchor_ada_face",
]);

function conversationParts(message, recentDialogue = []) {
  const clean = (value) => String(value || "").toLowerCase().replace(/\s+/g, "");
  const historic = recentDialogue.map((entry) => clean(entry?.player));
  const current = clean(message);
  return {
    turns: [...historic, current],
    current,
    previous: historic.at(-1) || "",
    corpus: [...historic, current].join(""),
  };
}

function isAssertiveTurn(turn) {
  return !["吗", "是不是", "是否", "难道", "为什么", "怎么会"]
    .some((marker) => turn.includes(marker));
}

function wasPresented(parts, objectWords) {
  const presentationWords = [
    "给你看", "让你看", "给你", "递给", "交给", "拿去", "出示", "拿出",
    "放在你面前", "放在桌", "放柜台", "这是", "这把", "这枚", "这张",
    "这份", "这两份", "我把", "我带来", "我带了",
  ];
  if (parts.turns.some((turn) => (
    objectWords.some((word) => turn.includes(word))
    && presentationWords.some((word) => turn.includes(word))
  ))) return true;
  return presentationWords.some((word) => parts.current.includes(word))
    && objectWords.some((word) => parts.previous.includes(word));
}

function recordsPresented(parts) {
  const both = wasPresented(parts, ["两份a.r", "两份ar", "两份记录", "两份原件"]);
  const master = wasPresented(parts, ["主钟记录", "主钟a.r", "主钟ar", "终止记录"]);
  const chapel = wasPresented(parts, ["礼拜堂记录", "礼拜堂日志", "安装记录", "礼拜堂a.r", "礼拜堂ar"]);
  return both || (master && chapel);
}

function beatriceCommitStatus(message, recentDialogue = []) {
  const parts = conversationParts(message, recentDialogue);
  const recordPresented = wasPresented(parts, [
    "终止记录", "主钟记录", "a.r.记录", "a.r记录", "ar记录", "七次连续击发记录",
  ]);
  const forkPresented = wasPresented(parts, ["银音叉", "银色音叉", "音叉", "校准器"]);
  const protocolExplained = parts.turns.some((turn) => (
    isAssertiveTurn(turn)
    && ["连续七次", "七次机械钟声", "第七声"].some((word) => turn.includes(word))
    && turn.includes("终止")
    && ["确认", "信号", "机械", "协议", "程序"].some((word) => turn.includes(word))
  ));
  const requested = ["第七声", "第七锤", "七声"].some((word) => parts.current.includes(word))
    && ["能不能", "请你", "由你", "你来", "敲", "完成", "执行", "答应"]
      .some((word) => parts.current.includes(word));
  return {
    recordPresented,
    forkPresented,
    protocolExplained,
    requested,
    ready: recordPresented && forkPresented && protocolExplained,
  };
}

function beatriceRefusal(message, recentDialogue) {
  const status = beatriceCommitStatus(message, recentDialogue);
  if (!status.requested || status.ready) return null;
  if (status.recordPresented && status.forkPresented) {
    return "东西我看过了，但你还没说明最重要的一点：为什么连续七次机械钟声代表终止确认？在这之前，我不会碰第七锤。";
  }
  return "我不能答应。第七声不属于日常报时，也不在礼拜堂现行仪式中。先让我看过 A.R. 终止记录和鉴定过的银音叉，再说明为什么那一声是机械终止确认，而不是送终仪式。";
}

function authoredFreeDialogueReply(npcId, state, message, recentDialogue) {
  const { current } = conversationParts(message, recentDialogue);
  const hasAny = (words) => words.some((word) => current.includes(word));
  const requestWords = ["能不能", "请你", "帮我", "给我", "由你", "你来", "执行", "答应"];
  const statesPossession = hasAny(["我有", "我带着", "我带了", "我这里有", "在我背包", "我拿到了"]);

  if (statesPossession) {
    if (npcId === "dorothea" && hasAny(["七号房钥匙牌", "七号钥匙牌", "七号铜牌"])) {
      return "让我看看。把铜牌放到柜台上，我会拿它和无编号钥匙的磨损、登记簿缺行一起核对。";
    }
    if (npcId === "arthur" && current.includes("扳手")) {
      return "把扳手放到地下室制动接口旁。我会核对型号、接口和档案说明；若三者吻合，停钟由我执行。";
    }
    if (npcId === "beatrice" && hasAny(["终止记录", "音叉", "校准器"])) {
      return "把记录和音叉都放到钟锤底座旁。我会核对，但你还必须说明连续七次机械钟声为什么代表终止确认。";
    }
    if (npcId === "conrad" && hasAny(["透镜", "镜片", "安装日志", "光路图"])) {
      return "把镜片和对应路线记录摊开。我要看到接收点、最终落点，还要确认维修副光不会熄灭主航道。";
    }
    if (npcId === "elias" && hasAny(["底片", "胶片"])) {
      return "把底片放到工作台上。我先看乳剂是否受潮、有没有重影，再决定怎么显影。";
    }
    if (npcId === "florence" && hasAny(["工具", "扳手", "音叉", "透镜", "镜片", "手电"])) {
      return "把你要鉴定的那一件放到索引卡旁。我只记录实际看到的实物，不读取整个背包。";
    }
    if (npcId === "florence" && hasAny(["a.r", "ar", "主钟记录", "礼拜堂记录", "两份记录"])) {
      return "把两份原件放到桌上并指出各自来源；我会先核对签名，再告诉你还缺什么。";
    }
  }

  if (npcId === "dorothea" && !hasItem(state, "unnumbered_key")
    && hasAny(["无编号钥匙", "没有编号的钥匙", "柜台钥匙"])
    && hasAny(["给我", "拿走", "交给我", "借我", "能不能"])) {
    return "抱歉，我不能只凭一句请求把旅店钥匙交出去。如果你真找到了属于七号房的铜牌，把实物放到柜台上；我会和钥匙、登记簿一起核对。";
  }
  if (npcId === "arthur" && !state.flags.arthur_stops_clock
    && hasAny(["停钟", "停止母钟", "制动母钟"]) && hasAny(requestWords)) {
    return "不行。先把档案确认过的制动扳手放到地下室接口旁，让我核对实物与接口；安全操作由我负责。";
  }
  if (npcId === "beatrice" && !state.flags.beatrice_rings_seventh) {
    const refusal = beatriceRefusal(message, recentDialogue);
    if (refusal) return refusal;
  }
  if (npcId === "conrad") {
    const asksRoute = hasAny(["光路", "导向", "照到", "转向", "调整灯塔"])
      && hasAny(requestWords);
    if (asksRoute && hasAny(["照相馆", "西墙", "旅店", "备用光"])
      && !state.flags.light_route_inn_studio) {
      return "不行。把双路维修镜和旅店屋顶光路图拿给我，再把接收点、西墙落点以及主航道光如何保留说清楚。";
    }
    if (asksRoute && !state.flags.light_route_chapel_square) {
      return "不行。我要亲眼核对双路维修镜和礼拜堂安装日志，还要确认副光不会熄灭主航道，并能从礼拜堂返回广场。";
    }
  }
  if (npcId === "elias" && !state.photos.unfinished_portrait
    && hasAny(["显影", "冲洗", "处理底片"]) && hasAny(requestWords)) {
    return "可以处理，但我得先看到那张底片本身。把它放到工作台上；我会先查受潮和重影，再决定显影步骤。";
  }
  if (npcId === "florence") {
    const asksTool = hasAny(["工具", "扳手", "音叉", "镜片", "透镜", "手电"])
      && hasAny(["鉴定", "什么用途", "做什么用", "看看", "检查"]);
    if (asksTool) {
      return "描述不能代替实物。把要鉴定的那一件放到索引卡旁；我每次只对你实际出示的物品下结论。";
    }
    const asksRecords = hasAny(["a.r", "ar", "两份记录", "主钟记录", "礼拜堂记录"])
      && hasAny(["核验", "对照", "比对", "帮我查", "确认"]);
    if (asksRecords && !state.knowledge.ada_identity) {
      return "我可以核验，但持有记录不等于我已经看过原件。把主钟记录和礼拜堂记录都放到桌上；若要补全姓名，还要把未完成肖像一并出示。";
    }
  }
  if (npcId === "ada") {
    if (!state.flags.ada_name_anchored && hasAny(["你是谁", "你叫什么", "介绍自己"])) {
      return "我不知道。有人叫过我，可名字到这里就断了。不要替我补上；让我看能留下来的证据。";
    }
    if (!state.flags.ada_name_anchored && hasAny(["艾达", "ada", "罗文", "你的名字", "姓名"])) {
      return "这个名字听起来熟悉，但熟悉不是证据。把档案恢复的姓名和两份 A.R. 原件放在我面前，让我确认那是我的签名。";
    }
    if (!state.flags.ada_residence_anchored && hasAny(["七号房", "7号房", "你的住处", "你住"])) {
      return "房间不是靠数字存在的。给我看钥匙、登记簿缺失行，以及七号房确实存在的证据。";
    }
    if (!state.flags.ada_duty_anchored && hasAny(["中央校准员", "第七见证人", "你的职责", "你的工作"])) {
      return "第七只是一个空位，不是我的职责。把两份记录和档案里的第七席结论放在一起，再告诉我为什么那个位置属于我。";
    }
    if (!state.flags.ada_face_anchored && hasAny(["你的脸", "你的面孔", "肖像里是你", "照片里是你"])) {
      return "你说的是一个轮廓。把未完成肖像拿给我，让它和这里留下的潜影彼此核对。";
    }
  }
  return null;
}

function conversationActionTriggered(actionId, message, recentDialogue) {
  const parts = conversationParts(message, recentDialogue);
  const hasCurrent = (words) => words.some((word) => parts.current.includes(word));
  const asksCheck = hasCurrent([
    "帮我查", "帮我确认", "帮我核对", "核验", "对照", "比对", "看看",
    "检查", "鉴定", "认领",
  ]);
  const hasRecords = recordsPresented(parts);

  if (actionId === "exchange_room7_key") {
    return wasPresented(parts, ["七号房钥匙牌", "七号钥匙牌", "七号铜牌", "7号房钥匙牌", "7号铜牌"]);
  }
  if (actionId === "ask_master_record") {
    return hasCurrent(["控制台", "七信号", "主钟记录", "终止记录"])
      && hasCurrent(["查看", "检查", "解释", "读取", "是什么", "看看", "告诉我"]);
  }
  if (actionId === "commit_stop_clock") {
    const wrench = wasPresented(parts, ["安装扳手", "制动扳手", "紧急制动扳手", "扳手"]);
    const interfaceExplained = ["制动接口", "紧急制动接口", "地下室接口"].some((word) => parts.corpus.includes(word));
    const requested = hasCurrent(["停钟", "停止母钟", "制动母钟"])
      && hasCurrent(["请你", "由你", "你来", "执行", "答应", "能不能", "可以"]);
    return wrench && interfaceExplained && requested;
  }
  if (actionId === "commit_seventh_bell") {
    const status = beatriceCommitStatus(message, recentDialogue);
    return status.ready && status.requested;
  }
  if (actionId === "receive_flashlight") {
    return hasCurrent(["洞穴", "最低潮", "手电", "照明", "两点", "2点"])
      && hasCurrent(["怎么", "哪里", "什么时候", "进入", "进去", "给我", "借我", "需要", "带什么"]);
  }
  if (["route_surface_light", "route_darkroom_light"].includes(actionId)) {
    const lens = wasPresented(parts, ["备用透镜", "双路透镜", "双路维修透镜", "双槽镜", "双路径维修透镜", "镜片"]);
    const safeSplit = parts.turns.some((turn) => (
      isAssertiveTurn(turn)
      && ["副光", "双路", "维修光"].some((word) => turn.includes(word))
      && ["主光不动", "不关闭主光", "不影响主航道", "保留主航道", "不会熄灭主光", "不中断主光"]
        .some((word) => turn.includes(word))
    ));
    const requested = hasCurrent(["光路", "导向", "照到", "转向", "建立", "调整"])
      && hasCurrent(["请你", "帮我", "你来", "执行", "现在", "可以"]);
    if (actionId === "route_surface_light") {
      const log = wasPresented(parts, ["礼拜堂安装日志", "礼拜堂安装记录", "a.r.安装记录", "a.r安装记录"]);
      return lens && log && safeSplit
        && parts.corpus.includes("礼拜堂") && parts.corpus.includes("广场") && requested;
    }
    const routeEvidence = wasPresented(parts, ["屋顶光路图", "旅店屋顶记录", "屋顶反射器记录", "回返曝光档案"]);
    return lens && routeEvidence && safeSplit && parts.corpus.includes("旅店")
      && ["照相馆", "西墙"].some((word) => parts.corpus.includes(word)) && requested;
  }
  if (actionId === "develop_cave_negative") {
    return wasPresented(parts, ["洞穴底片", "受潮底片", "旧底片", "胶片", "底片"])
      && hasCurrent(["显影", "冲洗", "处理", "检查"]);
  }
  const tools = {
    identify_wrench: ["安装扳手", "制动扳手", "扳手"],
    identify_fork: ["银色音叉", "银音叉", "音叉"],
    identify_lens: ["备用透镜", "双槽镜", "镜片", "透镜"],
    identify_flashlight: ["防水手电", "手电筒", "手电"],
  };
  if (tools[actionId]) {
    return wasPresented(parts, tools[actionId])
      && (asksCheck || hasCurrent(["这是什么", "什么用途", "做什么用"]));
  }
  if (actionId === "compare_ar_records") {
    return hasRecords && (asksCheck || wasPresented(parts, ["两份a.r", "两份ar", "两份记录", "两份原件"]));
  }
  if (actionId === "cross_reference_ada") {
    return hasRecords
      && wasPresented(parts, ["未完成肖像", "残缺肖像", "肖像", "照片", "影像"])
      && asksCheck;
  }
  if (actionId === "research_return_exposure") {
    return hasCurrent(["回返曝光", "屋顶光路", "屋顶反射器"])
      && hasCurrent(["查", "找", "研究", "解封", "看看", "下一步"]);
  }
  if (["anchor_ada_name", "anchor_ada_duty"].includes(actionId)) {
    const archive = ["档案", "名册", "交叉核验"].some((word) => parts.corpus.includes(word));
    if (actionId === "anchor_ada_name") {
      return hasRecords && archive
        && hasCurrent(["艾达", "ada", "罗文", "姓名", "名字"])
        && hasCurrent(["你叫", "这是你的", "确认", "认领", "记起来"]);
    }
    return hasRecords && archive
      && hasCurrent(["中央校准员", "第七见证人", "职责", "工作"])
      && hasCurrent(["你是", "确认", "认领", "记起来", "负责"]);
  }
  if (actionId === "anchor_ada_residence") {
    const key = wasPresented(parts, ["无编号钥匙", "七号钥匙", "七号房钥匙"]);
    const chain = ["登记簿缺失", "登记簿第七行", "缺失行"].some((word) => parts.corpus.includes(word))
      && ["七号房", "7号房"].some((word) => parts.corpus.includes(word));
    return key && chain && hasCurrent(["七号房", "7号房", "住处", "住过"])
      && hasCurrent(["你住", "你的房间", "确认", "认领", "记起来"]);
  }
  if (actionId === "anchor_ada_face") {
    return wasPresented(parts, ["未完成肖像", "残缺肖像", "肖像", "照片", "面孔"])
      && hasCurrent(["肖像", "照片", "面孔", "脸"])
      && hasCurrent(["是你", "你的", "确认", "认领", "记起来"]);
  }
  return false;
}

function inferFreeDialogueAction(npcId, message, recentDialogue, offeredActions) {
  const orderedActions = [...offeredActions].sort((left, right) => (
    Number(right.id === "cross_reference_ada")
    - Number(left.id === "cross_reference_ada")
  ));
  return orderedActions.find((action) => (
    action.id !== "continue_conversation"
    && conversationActionTriggered(action.id, message, recentDialogue)
  ))?.id || null;
}

function isSupportedNpcHistory(npcId, entry) {
  const compact = JSON.stringify(entry ?? "").replace(/\s+/g, "");
  if (npcId === "dorothea" && compact.includes("旅店") && [
      "存在一扇一直没有编号的门",
      "确实有一扇一直没有编号的门",
      "旅店里那扇一直没有编号的门",
      "旅店内的无编号门",
    ].some((fragment) => compact.includes(fragment))) return false;
  if (npcId === "arthur" && [
      "然后告诉我档案确认的操作",
      "怎样避免锁死主轮",
      "它断开哪一段机构，怎样避免锁死主轮",
      "并说明它如何在卸压状态下断开主擒纵",
    ].some((fragment) => compact.includes(fragment))) return false;
  if (npcId === "beatrice" && [
      "宣告某个记录已经结束",
      "只在某项记录被宣告结束时落下",
    ].some((fragment) => compact.includes(fragment))) return false;
  if (npcId === "dorothea" && [
      "要不要先喝点热的",
      "要不要我给你倒杯热水",
      "顺便把前台那三份委托单",
      "要是你是来办入住或者看委托单",
    ].some((fragment) => compact.includes(fragment))) return false;
  if (npcId === "florence" && [
      "我知道你带着它们。可我还没看到原件",
      "我现在只能说“有这个可能”",
    ].some((fragment) => compact.includes(fragment))) return false;
  return true;
}

export class Game {
  constructor(content, ai = null) {
    this.content = content;
    this.ai = ai || new AIService({ timeoutMs: 12000 });
    this.ui = new GameUI(content);
    this.audio = new AudioManager();
    this.renderer = new WorldRenderer(document.getElementById("game-canvas"), content);
    this.state = null;
    this.started = false;
    this.keys = new Set();
    this.lastFrame = performance.now();
    this.lastUiUpdate = 0;
    this.currentConversationNpc = null;
    this.saveKey = content.game.saveKey || "time-echo-save-v1";
    this.frame = this.frame.bind(this);
    this.bindControls();
    this.ui.bindGameActions({
      newGame: () => this.newGame(),
      continueGame: () => this.continueGame(),
      openArchive: () => this.ui.renderArchive(this.loadRaw()),
      openJournal: () => this.state && this.ui.renderJournal(this.state),
      toggleSound: () => this.toggleSound(),
      save: () => this.save(true),
      restartAfterEnding: () => this.restartAfterEnding(),
    });
  }

  initialize() {
    this.ui.finishLoading(Boolean(this.loadRaw()));
    requestAnimationFrame(this.frame);
  }

  loadRaw() {
    try { return JSON.parse(localStorage.getItem(this.saveKey) || "null"); }
    catch { return null; }
  }

  newGame() {
    this.state = createInitialState(this.content);
    this.state.cinematic = "prologue";
    this.started = true;
    this.ui.showGame();
    this.ui.update(this.state);
    this.ui.openPrologue(() => {
      this.state.cinematic = null;
      this.ui.showBanner(this.scene);
      this.save(false);
    });
  }

  continueGame() {
    const raw = this.loadRaw();
    if (!raw) return this.newGame();
    this.state = normalizeLoadedState(raw, this.content);
    this.started = true;
    this.ui.showGame();
    this.ui.update(this.state);
    this.ui.showBanner(this.scene);
  }

  restartAfterEnding() {
    document.getElementById("ending-modal").classList.add("hidden");
    const persistent = {
      seed: this.state.seed,
      rngState: this.state.rngState,
      loopCount: this.state.loopCount + 1,
      knowledge: this.state.knowledge,
      photos: this.state.photos,
      journal: this.state.journal,
      npcNotes: this.state.npcNotes,
    };
    this.state = createInitialState(this.content, persistent);
    this.started = true;
    this.ui.showGame();
    this.ui.update(this.state);
    this.save(false);
  }

  get scene() {
    if (!this.state) return null;
    return resolveScene(this.content, this.state.regionId, this.state.placeId);
  }

  bindControls() {
    const unlockAudio = () => this.audio.unlock();
    document.addEventListener('pointerdown', unlockAudio, { once: true });
    document.addEventListener('keydown', unlockAudio, { once: true });
    document.addEventListener("keydown", (event) => {
      const tag = event.target?.tagName?.toLowerCase();
      const typing = tag === "input" || tag === "textarea";
      if (!typing && KEY_BINDINGS[event.key]) {
        this.keys.add(KEY_BINDINGS[event.key]);
        if (this.started) event.preventDefault();
      }
      if (!this.started || typing) return;
      if ((event.key === "e" || event.key === "E") && !event.repeat && !this.ui.hasBlockingModal()) {
        event.preventDefault();
        this.interact();
      }
      if ((event.key === "j" || event.key === "J") && !event.repeat && !this.ui.hasBlockingModal()) {
        event.preventDefault();
        this.ui.renderJournal(this.state);
      }
    });
    document.addEventListener("keyup", (event) => {
      if (KEY_BINDINGS[event.key]) this.keys.delete(KEY_BINDINGS[event.key]);
    });
    window.addEventListener("blur", () => this.keys.clear());
  }

  frame(now) {
    const delta = Math.min(.05, Math.max(0, (now - this.lastFrame) / 1000));
    this.lastFrame = now;
    if (this.started && this.state) {
      if (!this.ui.hasBlockingModal() && !this.state.cinematic && !this.state.endingId) this.updateMovement(delta);
      const events = advanceWorld(this.state, this.content, delta);
      updateNpcMovement(this.state, this.content, delta);
      const movementKeys = ['up', 'down', 'left', 'right'];
      this.audio.update(this.scene, this.state, delta, {
        moving: !this.ui.hasBlockingModal() && movementKeys.some((key) => this.keys.has(key)),
        running: window.__timeEchoShift === true,
      });
      this.handleWorldEvents(events);
      this.renderer.render(this.state, delta);
      if (now - this.lastUiUpdate > 120) {
        this.lastUiUpdate = now;
        this.ui.update(this.state);
        this.updateInteractionHint();
      }
    }
    requestAnimationFrame(this.frame);
  }

  updateMovement(delta) {
    let dx = (this.keys.has("right") ? 1 : 0) - (this.keys.has("left") ? 1 : 0);
    let dy = (this.keys.has("down") ? 1 : 0) - (this.keys.has("up") ? 1 : 0);
    const length = Math.hypot(dx, dy);
    const running = this.keys.has("run") || Boolean(window.event?.shiftKey);
    // Shift state is read directly because it may be pressed before a movement key.
    const shift = window.__timeEchoShift === true;
    const isRunning = running || shift;
    if (length) {
      dx /= length; dy /= length;
      const speed = isRunning ? 164 : 96;
      const moved = movePlayer(this.state, this.scene, dx * speed * delta, dy * speed * delta);
      if (moved) {
        if (Math.abs(dx) > Math.abs(dy)) this.state.player.facing = dx > 0 ? "right" : "left";
        else this.state.player.facing = dy > 0 ? "down" : "up";
      }
      this.renderer.setMoving(moved, isRunning);
    } else this.renderer.setMoving(false, false);
  }

  updateInteractionHint() {
    const target = this.getInteractionTarget();
    this.ui.setInteraction(target ? { label: target.label } : null);
  }

  getInteractionTarget() {
    if (!this.state || !this.scene) return null;
    const npc = nearestNpc(this.state, this.content, 62);
    const landmark = nearestLandmark(this.state, this.scene, 52, this.content);
    const portal = nearestPortal(this.state, this.scene, 58);
    const targets = [];
    if (npc) targets.push({ type: "npc", value: npc, distance: npc.distance, label: `与 ${npc.profile.name} 交谈` });
    if (landmark) targets.push({ type: "landmark", value: landmark, distance: landmark.distance, label: landmark.label || "检查" });
    if (portal) targets.push({ type: "portal", value: portal, distance: portal.distance, label: portal.label || "前往" });
    return targets.sort((left, right) => left.distance - right.distance)[0] || null;
  }

  interact() {
    const target = this.getInteractionTarget();
    if (!target) return;
    this.audio.play(target.type === "portal" ? "travel" : "talk");
    if (target.type === "npc") this.openConversation(target.value.profile);
    else if (target.type === "landmark") this.interactLandmark(target.value);
    else this.travel(target.value);
  }

  travel(portal) {
    if (portal.id === "enter_low_tide_cave" && !hasItem(this.state, "flashlight")) {
      this.ui.inspect("退潮洞口", "洞口已经露出，但里面没有自然光。康拉德也许有适合下水维护的照明工具。");
      return;
    }
    this.ui.fade(true);
    setTimeout(() => {
      const events = advanceTravel(this.state, this.content, Number(portal.travelSeconds || 0));
      this.state.regionId = portal.targetRegionId || this.state.regionId;
      this.state.placeId = portal.targetPlaceId || portal.targetRegionId || this.state.regionId;
      this.state.player.x = Number(portal.spawn?.x ?? 384);
      this.state.player.y = Number(portal.spawn?.y ?? 350);
      this.state.player.facing = portal.spawn?.facing || "down";
      syncNpcSchedules(this.state, this.content);
      this.ui.update(this.state);
      this.ui.showBanner(this.scene);
      this.ui.fade(false);
      this.handleWorldEvents(events);
      this.save(false);
    }, 230);
  }

  interactLandmark(landmark) {
    if (landmark.id === 'tool_identification_cards') {
      this.ui.inspect('维护工具索引卡', '卡片只能提供编号与形制的比对位置。弗洛伦斯必须亲自在场，才能把本轮实物登记成可供居民采用的证据。');
      this.ui.update(this.state);
      this.save(false);
      return;
    }
    const id = landmark.id;
    const done = (title, text, extra = "") => {
      this.ui.inspect(title || landmark.label || "现场记录", text || landmark.description || "", extra);
      this.ui.update(this.state);
      this.save(false);
    };
    if (id === "repair_orders") {
      this.state.flags.repair_orders_read = true;
      addJournal(this.state, "order", "接受三份维修委托：主钟、礼拜堂六声钟、港口潮汐钟。");
      done("三份维修委托", "三张纸使用不同部门的抬头，却都在 SATURDAY 06:00 同一刻签发。地图旁注标出广场、礼拜堂与港口。",
        '<p class="pencil-note">知识锁：修复不是结局；每座钟恢复后都会让一份现场记录重新可读。</p>');
    } else if (id === "player_journal") {
      this.ui.renderJournal(this.state);
    } else if (id === "inn_ledger") {
      addEvidence(this.state, "ledger_gap", "旅店登记簿在六号与八号之间缺失一整行；这道物理缺口会写进跨轮日志。");
      done("登记簿缺失行", "墨线没有涂改，整条纸纤维被精确挖去。六号房后的走笔原本还要继续，八号房却换了一次蘸墨。不是编号错误。 ");
    } else if (id === "installation_wrench_pickup") {
      if (!hasItem(this.state, "installation_wrench")) {
        addItem(this.state, "installation_wrench");
        addJournal(this.state, "item", "多萝西娅把市政安装扳手交给你。柄端有一个三角缺口。", false);
      }
      done("安装扳手", "多萝西娅说三份维修单都允许你使用它。工具本身很普通，但柄端的三角缺口不像握柄设计。档案馆也许能鉴定用途。");
    } else if (id === "unnumbered_key_rack") {
      done("无编号钥匙", hasItem(this.state, "unnumbered_key") ? "它已经由多萝西娅交给你，齿形并不匹配普通客房锁。" : "多萝西娅下意识挡住钥匙架。只说出“七号房”不足以让她交出钥匙；她需要看见一件属于那间房的东西。");
    } else if (["square_clock_face", "master_clock_mechanism"].includes(id)) {
      if (this.state.repairs.master) done("重新运转的主钟", "三枚红线每转一周都会同时经过十二点。第七拍仍会在机芯深处产生极轻的空响。");
      else this.ui.openPuzzle("master", this.state, () => { markRepair(this.state, "master"); this.audio.play("event"); this.ui.update(this.state); this.save(false); });
    } else if (id === "master_console") {
      if (!this.state.repairs.master) done("七信号控制台", "主钟没有动力，记录滚筒无法前进。先修复三齿轮机构。");
      else {
        addEvidence(this.state, "master_ar_record", "主钟控制台恢复后显示：A.R.，七次连续击发确认终止。");
        done("A.R. 终止记录", "记录滚筒写着：A.R. / SEVEN CONSECUTIVE STRIKES CONFIRM TERMINATION。第七个信号位的铭牌已被拆除。 ");
      }
    } else if (id === "silver_tuning_fork_pickup") {
      if (!hasItem(this.state, "silver_tuning_fork")) { addItem(this.state, "silver_tuning_fork"); addJournal(this.state, "item", "在主钟舱地面捡到刻着 VII 的银色音叉。", false); }
      done("银色音叉", "它不属于主钟的标准工具组。轻敲时，钟楼方向传来几乎同频的金属共振。档案馆可以鉴定它。 ");
    } else if (id === "chapel_clock_mechanism") {
      if (this.state.repairs.chapel) done("六锤擒纵机构", "六枚钟锤已经按同一节拍工作。独立的第七锤仍不在这条传动链上。 ");
      else this.ui.openPuzzle("chapel", this.state, () => { markRepair(this.state, "chapel"); this.audio.play("event"); this.ui.update(this.state); this.save(false); });
    } else if (id === "missing_pin") {
      if (!hasItem(this.state, "chapel_pin")) { addItem(this.state, "chapel_pin"); addJournal(this.state, "item", "在礼拜堂长椅下找到第四枚擒纵销。", false); }
      done("黄铜擒纵销", "这是一枚普通维修件，尺寸与六锤机构的第四个空槽完全吻合。 ");
    } else if (id === "chapel_rope") {
      done("试钟绳", this.state.repairs.chapel ? "你拉下绳索。六声铜音依次越过屋梁；第六声后，上方另有一枚钟锤轻轻晃动，却没有落下。" : "绳索带出五声完整钟响，第四拍只剩一记木制限位器的空响。 ");
    } else if (id === "chapel_install_log") {
      addEvidence(this.state, "chapel_ar_log", "礼拜堂钟楼安装记录：A.R. 将屋顶反射器的灯塔光路引向中央广场。");
      done("礼拜堂 A.R. 安装记录", "纸边的维护孔位与主钟记录相同，但它来自完全独立的钟楼档案。路线图把灯塔、礼拜堂屋顶和广场画在一条折线上。 ");
    } else if (id === "room7_tag_pickup") {
      if (!hasItem(this.state, "room7_tag")) { addItem(this.state, "room7_tag"); addJournal(this.state, "item", "在礼拜堂钟楼地板缝里找到旅店七号房钥匙牌。", false); }
      done("七号房钥匙牌", "铜牌边缘因长年使用变得圆滑。它足以证明七号并非你凭空猜出的房间。把它带给旅店主人。 ");
    } else if (id === "seventh_hammer") {
      done("独立第七锤", "底座没有钟绳，只有一枚音叉形校准槽。它不用于报时，而是等待另一个系统发来的“终止”信号。 ");
    } else if (id === "spare_lens_pickup") {
      if (!hasItem(this.state, "spare_lens")) { addItem(this.state, "spare_lens"); addJournal(this.state, "item", "从港口沙滩捡到带双导轨的厚镜片。", false); }
      done("双槽备用镜片", "镜片能同时容纳主光与备用光，但这只是你的技术判断。档案馆的维护索引才能确认它在灯塔系统里的正式用途。 ");
    } else if (["tide_clock", "tide_test_console"].includes(id)) {
      if (this.state.repairs.tide) done("恢复的潮汐钟", "三枚刻度环现在跟随港外低、中、高三条真实水线。盘面标出 SUNDAY 02:00–03:00 的最低潮窗口。 ");
      else this.ui.openPuzzle("tide", this.state, () => { markRepair(this.state, "tide"); this.audio.play("event"); this.ui.update(this.state); this.save(false); });
    } else if (id.startsWith("dock_post_")) {
      done(landmark.label, landmark.description);
    } else if (id === "lighthouse_router") {
      done("灯塔光路控制器", this.state.flags.light_route_inn_studio ? "双槽镜已锁定。主光路通向礼拜堂，备用光路经旅店屋顶落在照相馆西墙。" : "这项操作必须由灯塔看守完成。带着经过鉴定的镜片与一份可核验的安装路线和康拉德谈。 ");
    } else if (id === "cave_negative_pickup") {
      if (!hasItem(this.state, "flashlight")) done("岩缝里的暗影", "没有定向光，你无法判断那是胶片还是湿石片。 ");
      else {
        if (!hasItem(this.state, "cave_negative")) { addItem(this.state, "cave_negative"); addJournal(this.state, "item", "在退潮洞穴取得受潮底片；乳剂里似乎有一名站在主钟前的人。", false); }
        done("受潮的旧底片", "手电斜光下能看见明显重影。自己猜人脸没有意义；照相馆拥有能核查重影、反差和反射的显影台。 ");
      }
    } else if (id === "development_bench") {
      if (!hasItem(this.state, "cave_negative") || this.state.photos.unfinished_portrait) done("三步显影台", this.state.photos.unfinished_portrait ? "那张底片已得到一张未完成肖像。面孔稳定了，身份仍不完整。" : "没有待显影的底片。埃利亚斯只处理你真正带到工作台前的胶片。 ");
      else done("三步显影台", "底片仍在你手里。把实物交给埃利亚斯并明确请求显影；由他检查受潮与重影后，工作台才会开始三步处理。");
    } else if (id === "studio_counterweight" || id === "silver_salt_wall") {
      done(landmark.label, this.state.flags.hidden_darkroom_open ? "配重已经升起，灯塔备用光让银盐结晶显成门框；无编号钥匙可以转动暗锁。" : landmark.description);
    } else if (id === "cross_reference_desk") {
      done("交叉核验台", "弗洛伦斯坚持亲自在场核验。带齐本轮主钟 A.R. 记录、钟楼 A.R. 安装记录和已经显影的残缺肖像，再与她交谈。 ");
    } else if (id === "tool_identification_cards") {
      done("维护工具索引卡", "索引卡不能自己检查你的背包。和弗洛伦斯交谈，每次把一件实物放到卡旁，她才会记录那一件的型号与用途。");
    } else if (id === "return_exposure_file") {
      done("“回返曝光”档案词条", "索引注明这里同时收录旅店屋顶维护光路图。档案内容需要由弗洛伦斯当面查阅；向她询问“回返曝光”或屋顶反射器。 ");
    } else if (id === "brake_interface") {
      addEvidence(this.state, "brake_interface", "主钟地下室的三角制动接口与安装扳手柄端吻合，但必须由维护负责人执行。");
      done("紧急制动接口", "机械接口与安装扳手完全吻合。旁边的程序牌要求“维护负责人现场确认并执行”，因此玩家不能自己绕过阿瑟。 ");
    } else if (id === "three_signal_lights") {
      const lights = [this.state.flags.conrad_routes_light, this.state.flags.arthur_stops_clock, this.state.flags.beatrice_rings_seventh];
      done("三枚外部信号灯", `灯塔光路 ${lights[0] ? "已确认" : "未确认"}；主钟制动 ${lights[1] ? "已确认" : "未确认"}；第七终钟 ${lights[2] ? "已确认" : "未确认"}。机器要求对应居民亲自承诺，不接受玩家代按。`);
    } else if (id === "witness_slot_seven") {
      if (this.state.flags.slot_seven_filled) done("第七见证位", "艾达·罗文的定影肖像已经稳定在槽内。七枚信号不再需要删除一个人来达成一致。 ");
      else if (hasItem(this.state, "fixed_portrait")) {
        installAdaPortrait(this.state); this.audio.play("event");
        done("第七见证人归位", "照片滑入卡槽的一刻，第七盏灯由白转金。红色删除杆断电，右侧面板弹出一枚白色旋钮。 ");
      } else done("空白的第七见证位", "这里需要的不是任意照片。机器要确认一个拥有姓名、住处、职责和面孔的完整见证人。 ");
    } else if (id === "identity_fixing_table") {
      if (this.state.photos.fixed_portrait) done("身份定影台", "艾达的姓名、住处、职责和面孔已经在同一张相纸上完成定影。 ");
      else this.ui.openPuzzle("identity", this.state, () => { completeIdentityFixing(this.state); this.audio.play("event"); this.ui.update(this.state); this.save(false); });
    } else if (id === "ada_voice") {
      done("相纸背后的声音", this.state.photos.fixed_portrait ? "“别把我当成一个秘密结局。我只是本来就住在这里的人。”" : "红灯闪烁时，空白相纸背后传来一句不完整的话：“不要只带着我的……名字……”");
    } else if (id === "red_erase_lever") {
      if (this.state.flags.slot_seven_filled) done("失去电源的红色删除杆", "第七见证记录已经恢复，机器不再允许用缺席完成终止。 ");
      else if (surfaceProtocolReady(this.state)) this.finishEnding("surface");
      else done("红色删除杆", "它仍被三枚外部信号锁住。康拉德、阿瑟和贝娅特丽斯必须分别确认光路、停钟与第七声。 ");
    } else if (id === "white_continue_knob") {
      if (this.state.flags.slot_seven_filled) this.finishEnding("true");
      else done("面板下的圆形轮廓", "金属板没有接缝。只有补回第七见证记录，内部解锁机构才可能推出这枚旋钮。 ");
    } else {
      done(landmark.label || "现场记录", landmark.description || "没有发现可验证的新线索。 ");
    }
    syncWorldFlags(this.state);
  }

  openConversation(npc) {
    this.currentConversationNpc = npc.id;
    this.state.conversationOpen = true;
    const refreshActions = () => this.ui.renderConversationActions(getNpcActions(npc.id, this.state), (action) => {
      const result = applyNpcAction(npc.id, action.id, this.state);
      this.ui.appendMessage(npc.name, result.text || "他没有改变决定。", false);
      if (result.puzzle) this.ui.openPuzzle(result.puzzle, this.state, () => {
        if (result.puzzle === "photo") completePhotoDevelopment(this.state);
        this.audio.play("event"); this.ui.update(this.state); this.save(false);
      });
      refreshActions();
      syncWorldFlags(this.state);
      this.ui.update(this.state);
      this.save(false);
    });
    this.ui.openConversation(npc, this.state, getNpcActions(npc.id, this.state), {
      onAction: (action) => {
        const result = applyNpcAction(npc.id, action.id, this.state);
        this.ui.appendMessage(npc.name, result.text || "他没有改变决定。", false);
        if (result.puzzle) this.ui.openPuzzle(result.puzzle, this.state, () => {
          if (result.puzzle === "photo") completePhotoDevelopment(this.state);
          this.audio.play("event"); this.ui.update(this.state); this.save(false);
        });
        refreshActions();
        syncWorldFlags(this.state);
        this.ui.update(this.state);
        this.save(false);
      },
      onSubmit: (message) => this.talkFree(npc, message, refreshActions),
      onClose: () => { this.state.conversationOpen = false; this.currentConversationNpc = null; this.save(false); },
    });
  }

  async talkFree(npc, message, refreshActions = null) {
    this.ui.setConversationPending(true);
    const npcState = this.state.npcs[npc.id];
    const visibleFacts = [...(npc.knowledge?.public || [])];
    if (this.state.repairs.master && npc.id === "arthur") visibleFacts.push("主钟在本轮已经修复。");
    if (this.state.repairs.chapel && npc.id === "beatrice") visibleFacts.push("礼拜堂六锤在本轮已经修复。");
    if (this.state.repairs.tide && npc.id === "conrad") visibleFacts.push("潮汐钟在本轮已经修复。");
    if (npc.id === 'dorothea' && this.state.evidence.ledger_gap) visibleFacts.push('玩家本轮亲眼看过旅店登记簿缺失的第七行。');
    if (npc.id === 'dorothea' && hasItem(this.state, 'room7_tag')) visibleFacts.push('玩家本轮带着七号房铜钥匙牌。');
    if (npc.id === 'dorothea' && this.state.flags.room7_key_verified) visibleFacts.push('多萝西娅本轮已核验铜牌，并把无编号钥匙交给玩家。');
    if (npc.id === 'dorothea') {
      visibleFacts.push('旅店里没有无编号的门：二楼一号至六号之后，六号与八号之间只有一段没有门的空墙。');
      visibleFacts.push('多萝西娅不知道无编号钥匙如今能打开哪里；不得猜测旅店里另有一扇门，也不得命名任何尚未证实的钥匙用途、地点或门。');
    }
    if (npc.id === 'arthur' && this.state.evidence.master_ar_record) visibleFacts.push('修复后的主钟留下 A.R. 签署的七次连续击发记录。');
    if (npc.id === 'arthur' && this.state.evidence.brake_interface) visibleFacts.push('玩家本轮检查过地下室紧急制动接口。');
    if (npc.id === 'arthur' && this.state.flags.arthur_stops_clock) visibleFacts.push('阿瑟本轮已经核验接口与扳手，并承诺亲手停钟。');
    if (npc.id === 'beatrice' && this.state.evidence.chapel_ar_log) visibleFacts.push('礼拜堂安装记录由 A.R. 签署，并记录独立第七锤。');
    if (npc.id === 'beatrice' && this.state.flags.beatrice_rings_seventh) visibleFacts.push('贝娅特丽斯本轮已经核验证据，并承诺亲手完成第七声。');
    if (npc.id === 'conrad' && this.state.flags.low_tide) visibleFacts.push('现在正处于 SUNDAY 02:00–03:00 的最低潮窗口。');
    if (npc.id === 'conrad' && this.state.flags.lens_identified) visibleFacts.push('档案员已把玩家带来的双槽镜鉴定为灯塔备用镜。');
    if (npc.id === 'conrad' && hasItem(this.state, 'flashlight')) visibleFacts.push('康拉德本轮已经把防水手电交给玩家。');
    if (npc.id === 'conrad' && this.state.flags.light_route_inn_studio) visibleFacts.push('康拉德本轮已经建立通往照相馆西墙的备用光路。');
    if (npc.id === 'elias' && hasItem(this.state, 'cave_negative')) visibleFacts.push('玩家本轮带来了退潮洞穴中的受潮底片。');
    if (npc.id === 'elias' && this.state.photos.unfinished_portrait) visibleFacts.push('底片已按重影、反差、湖面反射三步显影成未完成肖像。');
    if (npc.id === 'florence') {
      if (this.state.evidence.master_ar_record) visibleFacts.push('玩家本轮带有主钟 A.R. 记录。');
      if (this.state.evidence.chapel_ar_log) visibleFacts.push('玩家本轮带有礼拜堂 A.R. 安装记录。');
      if (this.state.photos.unfinished_portrait) visibleFacts.push('玩家本轮带有已显影但身份未固定的肖像。');
      if (this.state.flags.ar_records_compared) visibleFacts.push('弗洛伦斯本轮已核验两份 A.R. 原件；它们仍缺影像证据才能补全姓名。');
      if (this.state.knowledge.ada_identity) visibleFacts.push('档案交叉核验已经恢复 Ada Rowan 的姓名与中央校准员职责。');
    }
    if (npc.id === 'ada') {
      const anchorNames = [
        ['ada_name_anchored', '姓名'],
        ['ada_residence_anchored', '住处'],
        ['ada_duty_anchored', '职责'],
        ['ada_face_anchored', '面孔'],
      ];
      visibleFacts.push(`当前已经共同核验的身份锚点：${anchorNames.filter(([flag]) => this.state.flags[flag]).map(([, label]) => label).join('、') || '无'}。`);
      if (this.state.flags.ada_name_anchored) {
        visibleFacts.push('两份独立 A.R. 记录与残缺肖像已经共同确认她的姓名是 Ada Rowan。');
      } else if (this.state.knowledge.ada_identity) {
        visibleFacts.push('玩家持有档案恢复的姓名结论和两份 A.R. 记录，但尚未当面与当前潜影共同核验；她不能据此自报姓名。');
      }
    }
    const safeDialogue = (this.state.npcNotes[npc.id] || [])
      .filter((entry) => isSupportedNpcHistory(npc.id, entry))
      .slice(-8);
    const candidatePlotActions = getNpcActions(npc.id, this.state)
      .filter((action) => FREE_DIALOGUE_PLOT_ACTIONS.has(action.id))
      .map((action) => ({
        ...action,
        instruction: "该动作的固定剧本条件与本轮对话触发均已满足；立即执行。",
      }));
    const triggeredPlotAction = inferFreeDialogueAction(
      npc.id,
      message,
      safeDialogue,
      candidatePlotActions,
    );
    const plotActions = candidatePlotActions
      .filter((action) => action.id === triggeredPlotAction);
    const adaNameUnknown = npc.id === 'ada' && !this.state.flags.ada_name_anchored;
    const adaDutyUnknown = npc.id === 'ada' && !this.state.flags.ada_duty_anchored;
    const safeNpc = {
      id: adaDutyUnknown ? 'hidden_figure' : npc.id,
      name: adaNameUnknown ? '暗房中的潜影' : npc.name,
      role: adaNameUnknown
        ? '身份尚未固定的人形潜影'
        : adaDutyUnknown
          ? '身份仍在恢复的暗房潜影'
          : npc.role,
      goal: adaDutyUnknown
        ? '弄清自己缺失的姓名、住处、职责和面孔，并让外部证据逐项固定这些记忆'
        : npc.goal,
      traits: npc.traits,
      voice: npc.voice,
      concern: adaDutyUnknown
        ? '害怕所有人最终接受一个从未有过她的世界，但无法说明自己为何被删除'
        : npc.concern,
      knowledge: {
        public: visibleFacts,
        residual: [...(npc.knowledge?.suggestive || [])],
      },
      allowedActions: [{
        id: "continue_conversation",
        label: "只继续对话，不改变世界状态",
        instruction: "仅在本轮没有执行交付、核验、承诺或机关操作时选择。",
      }, ...plotActions],
    };
    const safeNpcState = {
      ...npcState,
      activity: adaDutyUnknown ? '试图辨认残缺记忆' : npcState.activity,
      memories: (npcState.memories || [])
        .filter((entry) => isSupportedNpcHistory(npc.id, entry))
        .slice(0, 8),
    };
    const safeWorld = {
      day: this.state.dayLabel,
      minute: this.state.minute,
      loop: this.state.loopCount + 1,
      story_context: { public: this.content.storyContext.publicFacts },
      repairs: { ...this.state.repairs },
      flags: {},
      recent_dialogue: safeDialogue,
    };
    try {
      const result = await this.ai.talk(safeNpc, safeNpcState, safeWorld, message, "custom");
      if (this.currentConversationNpc !== npc.id) return;
      const inferredAction = triggeredPlotAction;
      const resolvedAction = inferredAction || "continue_conversation";
      let finalReply = result.reply;
      let appliedAction = null;
      if (resolvedAction !== "continue_conversation") {
        appliedAction = applyNpcAction(npc.id, resolvedAction, this.state);
        if (!appliedAction?.text) throw new Error("plot_action_rejected");
        finalReply = appliedAction.text;
        if (appliedAction.puzzle) this.ui.openPuzzle(appliedAction.puzzle, this.state, () => {
          if (appliedAction.puzzle === "photo") completePhotoDevelopment(this.state);
          this.audio.play("event");
          this.ui.update(this.state);
          this.save(false);
        });
        syncWorldFlags(this.state);
        refreshActions?.();
        this.ui.update(this.state);
      }
      if (!appliedAction) {
        finalReply = authoredFreeDialogueReply(
          npc.id,
          this.state,
          message,
          safeWorld.recent_dialogue,
        ) || finalReply;
      }
      this.ui.appendMessage(npc.name, finalReply, false);
      const providerText = appliedAction
        ? `${result.provider} · 剧情动作已由本地规则验证并执行`
        : result.provider === "local-rules"
          ? "本地人物规则 · 不写入证据状态"
          : `${result.provider} · 回复已通过动作白名单校验`;
      this.ui.setConversationProvider(providerText);
      npcState.memories.unshift({
        text: appliedAction ? `本轮已经执行 ${resolvedAction}：${finalReply}` : result.memory,
        importance: 1,
        loop: this.state.loopCount + 1,
      });
      npcState.memories = npcState.memories.slice(0, 8);
      this.state.npcNotes[npc.id] = this.state.npcNotes[npc.id] || [];
      this.state.npcNotes[npc.id].push({
        loop: this.state.loopCount + 1,
        player: message,
        reply: finalReply,
        action: resolvedAction,
      });
      this.state.npcNotes[npc.id] = this.state.npcNotes[npc.id].slice(-16);
    } catch {
      this.ui.appendMessage(npc.name, "我没听清。湖边的风会吞掉太长的话，你可以换一种更具体的问法。", false);
      this.ui.setConversationProvider("本地人物规则 · 服务暂时不可用");
    } finally {
      this.ui.setConversationPending(false);
      this.save(false);
    }
  }

  handleWorldEvents(events) {
    if (events?.some((event) => event.type === 'reset-warning')) this.audio.play('reset');
    if (!events?.length || !this.state) return;
    if (events.some((event) => event.type === "reset-warning") && !this.state.cinematic) {
      this.state.cinematic = "reset";
      addJournal(this.state, "loop", "05:55，湖面出现一条逆向升起的白线。镇民停住，影子全部转向湖心。");
      this.save(false);
      this.ui.playReset(this.state.loopCount, () => {
        this.state = resetLoop(this.state, this.content);
        this.state.cinematic = null;
        this.ui.update(this.state);
        this.ui.showBanner(this.scene);
        this.save(false);
      });
    }
  }

  finishEnding(id) {
    this.state.endingId = id;
    addJournal(this.state, "ending", id === "true" ? "七名见证人共同进入星期日，时间没有倒退，只是继续。" : "六人终止协议完成；星期日到来，艾达的共同记录被永久删除。");
    const endings = JSON.parse(localStorage.getItem("time-echo-endings") || "[]");
    endings.push({ id, stamp: new Date().toISOString(), loops: this.state.loopCount + 1 });
    localStorage.setItem("time-echo-endings", JSON.stringify(endings.slice(-12)));
    this.audio.play("ending");
    this.save(false);
    this.ui.showEnding(id);
  }

  save(notify = false) {
    if (!this.state) return;
    try {
      localStorage.setItem(this.saveKey, JSON.stringify(this.state));
      if (notify) { this.audio.play("save"); this.ui.notify("已保存当前循环。跨轮日志与已定影照片会保留；本轮实物仍会在白光后复位。 "); }
    } catch (error) {
      if (notify) this.ui.notify(`保存失败：${error.message}`);
    }
  }

  toggleSound() {
    const enabled = this.audio.setEnabled(!this.audio.enabled);
    document.getElementById("sound-button").textContent = enabled ? "♪" : "×";
    if (enabled) this.audio.play("choice");
  }
}

// Keep Shift independent of focus changes and modal openings.
window.__timeEchoShift = false;
document.addEventListener("keydown", (event) => { if (event.key === "Shift") window.__timeEchoShift = true; });
document.addEventListener("keyup", (event) => { if (event.key === "Shift") window.__timeEchoShift = false; });
window.addEventListener("blur", () => { window.__timeEchoShift = false; });

export default Game;
