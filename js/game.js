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
  identifyPossessedTools,
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
      if (!hasItem(this.state, "cave_negative") || this.state.photos.unfinished_portrait) done("三步显影台", this.state.photos.unfinished_portrait ? "那张底片已得到一张未完成肖像。面孔稳定了，身份仍不完整。" : "没有待显影的底片。伊莱亚斯只处理你真正带到工作台前的胶片。 ");
      else this.ui.openPuzzle("photo", this.state, () => { completePhotoDevelopment(this.state); this.audio.play("event"); this.ui.update(this.state); this.save(false); });
    } else if (id === "studio_counterweight" || id === "silver_salt_wall") {
      done(landmark.label, this.state.flags.hidden_darkroom_open ? "配重已经升起，灯塔备用光让银盐结晶显成门框；无编号钥匙可以转动暗锁。" : landmark.description);
    } else if (id === "cross_reference_desk") {
      done("交叉核验台", "弗洛伦斯坚持亲自在场核验。带齐本轮主钟 A.R. 记录、钟楼 A.R. 安装记录和已经显影的残缺肖像，再与她交谈。 ");
    } else if (id === "tool_identification_cards") {
      const identified = identifyPossessedTools(this.state);
      done("维护工具索引卡", identified.length ? identified.join(" ") : "没有新的实物可以鉴定。日志里记住一个工具，不等于本轮把工具带到了桌上。 ");
    } else if (id === "return_exposure_file") {
      done("“回返曝光”封存词条", this.state.knowledge.ada_identity ? "正文仍需档案员解封。把已经恢复的身份结论交给弗洛伦斯，她会调出关联光路图。" : "索引要求先恢复被删除记录的姓名与职责，否则正文不能从‘假设人物’目录移出。 ");
    } else if (id === "brake_interface") {
      addEvidence(this.state, "brake_interface", "主钟地下室的三角制动接口与安装扳手柄端吻合，但必须由维护负责人执行。");
      done("紧急制动接口", "机械接口与安装扳手完全吻合。旁边的程序牌要求“维护负责人现场确认并执行”，因此玩家不能自己绕过亚瑟。 ");
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
      else done("红色删除杆", "它仍被三枚外部信号锁住。康拉德、亚瑟和比阿特丽斯必须分别确认光路、停钟与第七声。 ");
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
      onSubmit: (message) => this.talkFree(npc, message),
      onClose: () => { this.state.conversationOpen = false; this.currentConversationNpc = null; this.save(false); },
    });
  }

  async talkFree(npc, message) {
    this.ui.setConversationPending(true);
    const npcState = this.state.npcs[npc.id];
    const visibleFacts = [...(npc.knowledge?.public || [])];
    if (this.state.repairs.master && npc.id === "arthur") visibleFacts.push("主钟在本轮已经修复。");
    if (this.state.repairs.chapel && npc.id === "beatrice") visibleFacts.push("礼拜堂六锤在本轮已经修复。");
    if (this.state.repairs.tide && npc.id === "conrad") visibleFacts.push("潮汐钟在本轮已经修复。");
    const safeNpc = {
      id: npc.id,
      name: npc.name,
      role: npc.role,
      goal: npc.goal,
      traits: npc.traits,
      voice: npc.voice,
      concern: npc.concern,
      knowledge: { public: visibleFacts },
      allowedActions: [{ id: "continue_conversation", label: "继续当前对话" }],
    };
    const safeWorld = {
      day: this.state.dayLabel,
      minute: this.state.minute,
      loop: this.state.loopCount + 1,
      story_context: { public: this.content.storyContext.publicFacts },
      repairs: { ...this.state.repairs },
      flags: {},
    };
    try {
      const result = await this.ai.talk(safeNpc, npcState, safeWorld, message, "custom");
      if (this.currentConversationNpc !== npc.id) return;
      this.ui.appendMessage(npc.name, result.reply, false);
      this.ui.setConversationProvider(result.provider === "local-rules" ? "本地人物规则 · 不写入证据状态" : `${result.provider} · 回复已通过动作白名单校验`);
      npcState.memories.unshift({ text: result.memory, importance: 1, loop: this.state.loopCount + 1 });
      npcState.memories = npcState.memories.slice(0, 8);
      this.state.npcNotes[npc.id] = this.state.npcNotes[npc.id] || [];
      this.state.npcNotes[npc.id].push({ loop: this.state.loopCount + 1, player: message, reply: result.reply });
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
