import { escapeHtml, formatTime } from "./utils.js";
import { describeMissingIdentityAnchors, repairCount, scenePausesTime } from "./simulation.js";

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];

function itemName(content, id) {
  return content.items.find((item) => item.id === id)?.name || id;
}

function evidenceName(content, id) {
  return content.evidence.find((item) => item.id === id)?.name || id;
}

export class GameUI {
  constructor(content) {
    this.content = content;
    this.modalCloseCallbacks = new Map();
    this.titleAnimation = null;
    this.puzzleKeyHandler = null;
    this.lastBannerPlace = null;
    this.bannerTimer = null;
    this.onPrologueDone = null;
    this.bindStaticUi();
  }

  bindStaticUi() {
    $$('[data-close]').forEach((button) => button.addEventListener("click", () => this.closeModal(button.dataset.close)));
    $$(".journal-tab").forEach((button) => button.addEventListener("click", () => {
      $$(".journal-tab").forEach((item) => item.classList.toggle("active", item === button));
      $$(".journal-pane").forEach((pane) => pane.classList.toggle("active", pane.id === `tab-${button.dataset.tab}`));
    }));
  }

  bindGameActions(actions) {
    $("#new-game-button").addEventListener("click", actions.newGame);
    $("#continue-button").addEventListener("click", actions.continueGame);
    $("#archive-button").addEventListener("click", actions.openArchive);
    $("#journal-button").addEventListener("click", actions.openJournal);
    $("#sound-button").addEventListener("click", actions.toggleSound);
    $("#save-button").addEventListener("click", actions.save);
    $("#help-button").addEventListener("click", () => this.openModal("help-modal"));
    $("#ending-restart").addEventListener("click", actions.restartAfterEnding);
    this.bindTitleKeyboard();
  }

  bindTitleKeyboard() {
    const menu = () => $$(".title-actions .menu-button:not(.hidden)");
    let index = 0;
    const refresh = () => menu().forEach((button, buttonIndex) => button.classList.toggle("selected", buttonIndex === index));
    document.addEventListener("keydown", (event) => {
      if ($("#title-screen").classList.contains("hidden")) return;
      const buttons = menu();
      if (!buttons.length) return;
      if (["ArrowDown", "s", "S"].includes(event.key)) {
        event.preventDefault();
        index = (index + 1) % buttons.length;
        refresh();
      } else if (["ArrowUp", "w", "W"].includes(event.key)) {
        event.preventDefault();
        index = (index - 1 + buttons.length) % buttons.length;
        refresh();
      } else if (event.key === "Enter") {
        event.preventDefault();
        buttons[index]?.click();
      }
    });
    refresh();
  }

  finishLoading(hasSave) {
    $("#loading-screen").classList.add("hidden");
    $("#title-screen").classList.remove("hidden");
    $("#continue-button").classList.toggle("hidden", !hasSave);
    this.startTitleScene();
  }

  showTitle(hasSave = false) {
    $("#game-shell").classList.add("hidden");
    $("#title-screen").classList.remove("hidden");
    $("#continue-button").classList.toggle("hidden", !hasSave);
    this.startTitleScene();
  }

  showGame() {
    $("#title-screen").classList.add("hidden");
    $("#game-shell").classList.remove("hidden");
    if (this.titleAnimation) cancelAnimationFrame(this.titleAnimation);
    this.titleAnimation = null;
    $("#game-canvas").focus();
  }

  startTitleScene() {
    if (this.titleAnimation) return;
    const canvas = $("#title-canvas");
    const ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    const draw = (now) => {
      const t = now / 1000;
      ctx.fillStyle = "#081315";
      ctx.fillRect(0, 0, 480, 270);
      // Tall sky with a faint wrong dawn far below the horizon.
      for (let y = 0; y < 174; y += 6) {
        const amount = y / 174;
        ctx.fillStyle = `rgb(${9 + amount * 13},${20 + amount * 19},${22 + amount * 21})`;
        ctx.fillRect(0, y, 480, 6);
      }
      for (let star = 0; star < 42; star += 1) {
        const x = (star * 89 + 31) % 480;
        const y = (star * 47 + 17) % 148;
        const blink = Math.sin(t * 1.2 + star * 2.3) > .72;
        ctx.fillStyle = blink ? "#b9c8b8" : "#586e6b";
        ctx.fillRect(x, y, blink ? 2 : 1, blink ? 2 : 1);
      }
      // Dark hills and an original lakeside silhouette.
      ctx.fillStyle = "#122529";
      ctx.beginPath(); ctx.moveTo(0, 168); ctx.lineTo(58, 128); ctx.lineTo(108, 159); ctx.lineTo(174, 112); ctx.lineTo(230, 164); ctx.lineTo(292, 132); ctx.lineTo(350, 166); ctx.lineTo(422, 118); ctx.lineTo(480, 151); ctx.lineTo(480, 205); ctx.lineTo(0, 205); ctx.fill();
      ctx.fillStyle = "#0d1d20";
      ctx.fillRect(0, 184, 480, 33);
      // Clock tower, inn, chapel and lighthouse read as handmade landmarks rather than generic blocks.
      const building = (x, y, w, h, roof) => {
        ctx.fillStyle = "#162427"; ctx.fillRect(x, y, w, h);
        ctx.fillStyle = roof; ctx.beginPath(); ctx.moveTo(x - 3, y); ctx.lineTo(x + w / 2, y - 15); ctx.lineTo(x + w + 3, y); ctx.fill();
        ctx.fillStyle = "#c69a52"; ctx.fillRect(x + 6, y + h - 15, 3, 4); ctx.fillRect(x + w - 9, y + h - 15, 3, 4);
      };
      building(318, 148, 64, 37, "#263237");
      building(392, 158, 41, 27, "#432f30");
      building(248, 158, 47, 27, "#30323c");
      ctx.fillStyle = "#172629"; ctx.fillRect(344, 102, 13, 63); ctx.fillRect(337, 122, 27, 45);
      ctx.fillStyle = "#82533b"; ctx.beginPath(); ctx.moveTo(334, 122); ctx.lineTo(350, 91); ctx.lineTo(367, 122); ctx.fill();
      ctx.fillStyle = "#d2ae64"; ctx.fillRect(347, 113, 7, 7); ctx.fillStyle = "#303536"; ctx.fillRect(349, 114, 2, 5);
      ctx.fillStyle = "#a9aa90"; ctx.fillRect(448, 116, 10, 70); ctx.fillStyle = "#783f36"; ctx.fillRect(445, 110, 16, 9);
      const beam = 18 + Math.sin(t * .32) * 10;
      ctx.fillStyle = "rgba(208,205,150,.08)"; ctx.beginPath(); ctx.moveTo(450, 119); ctx.lineTo(300 - beam, 155); ctx.lineTo(300 + beam, 166); ctx.fill();
      // Lake reflections and the thin white line that does not belong to the lighthouse.
      ctx.fillStyle = "#17383e"; ctx.fillRect(0, 200, 480, 70);
      for (let y = 204; y < 270; y += 6) {
        for (let x = (y % 12); x < 480; x += 31) {
          const wave = Math.sin(t * 1.3 + x * .06 + y) * 6;
          ctx.fillStyle = y < 224 ? "#285057" : "#1b4147";
          ctx.fillRect(x + wave, y, 14 + (x % 13), 2);
        }
      }
      const white = 0.18 + (Math.sin(t * .7) + 1) * .08;
      ctx.fillStyle = `rgba(217,230,215,${white})`;
      ctx.fillRect(278, 216, 160, 1);
      ctx.fillRect(320, 219, 95, 1);
      // A small ferry tied up but not moving.
      ctx.fillStyle = "#101c1e"; ctx.fillRect(410, 226, 38, 7); ctx.fillRect(419, 218, 18, 8); ctx.fillStyle = "#8d5a3e"; ctx.fillRect(414, 225, 31, 2);
      this.titleAnimation = requestAnimationFrame(draw);
    };
    this.titleAnimation = requestAnimationFrame(draw);
  }

  openPrologue(onDone) {
    this.onPrologueDone = onDone;
    this.openModal("prologue-modal");
    const text = $("#prologue-text");
    const actions = $("#prologue-actions");
    const renderStep = (step) => {
      actions.innerHTML = "";
      if (step === 0) {
        text.innerHTML = "湖镇同时坏了三座钟：广场主钟、礼拜堂钟、港口潮汐钟。你今晚住湖畔旅店，明早六点开始。<br><br>当地人知道的比委托单多。别只找零件，先让他们把顾虑说完整。";
        this.addChoice(actions, "为什么不派一个维修队？", () => renderStep(1));
        this.addChoice(actions, "先告诉我与居民交谈的规则。", () => renderStep(1));
      } else if (step === 1) {
        text.innerHTML = "你可以自由输入问题，他们会用自己的性格和当前所知回答；下面的固定选项则代表可核验的行动。<br><br><strong>重要：</strong>提前说出一个正确名字，不等于那个人本轮也知道你从哪里得知。证据必须在你们之间真实发生。";
        this.addChoice(actions, "所以对话提供可能性，证据决定行动。", () => renderStep(2));
        this.addChoice(actions, "我会把知识和本轮证据分开。", () => renderStep(2));
      } else {
        text.innerHTML = "很好。第一班返程渡船是星期日早上六点。维修完就回来——十二分钟足够你先看清一轮发生了什么。";
        this.addChoice(actions, "带上工具，前往湖镇", () => {
          this.closeModal("prologue-modal", false);
          this.onPrologueDone?.();
        });
      }
    };
    renderStep(0);
  }

  addChoice(container, label, callback) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = label;
    button.addEventListener("click", callback);
    container.append(button);
  }

  openModal(id, onClose = null) {
    const modal = document.getElementById(id);
    if (!modal) return;
    modal.classList.remove("hidden");
    if (onClose) this.modalCloseCallbacks.set(id, onClose);
  }

  closeModal(id, notify = true) {
    const modal = document.getElementById(id);
    if (!modal) return;
    modal.classList.add("hidden");
    if (id === "puzzle-modal" && this.puzzleKeyHandler) {
      document.removeEventListener("keydown", this.puzzleKeyHandler);
      this.puzzleKeyHandler = null;
    }
    const callback = this.modalCloseCallbacks.get(id);
    this.modalCloseCallbacks.delete(id);
    if (notify) callback?.();
    $("#game-canvas")?.focus();
  }

  hasBlockingModal() {
    return $$(".modal-layer:not(.hidden), .ending-layer:not(.hidden), .reset-cinematic:not(.hidden)").length > 0;
  }

  update(state) {
    $("#day-label").textContent = state.dayLabel;
    $("#time-label").textContent = formatTime(state.minute);
    $("#loop-label").textContent = `LOOP ${String(state.loopCount + 1).padStart(2, "0")}`;
    const scene = this.content.regions.concat(this.content.places).find((item) => item.id === state.placeId) || this.content.regions[0];
    $("#location-label").textContent = scene?.name || "湖镇";
    $("#location-kicker").textContent = scene?.kind === "interior" ? "INTERIOR" : "LAKESIDE TOWN";
    $("#pause-ribbon").classList.toggle("hidden", !scenePausesTime(state));
    this.renderRepairs(state);
    this.renderEvidence(state);
    this.renderPeople(state);
    this.renderNextClue(state);
    const progress = Math.max(0, Math.min(100, state.loopElapsed / 1440 * 100));
    $("#time-thread-fill").style.width = `${progress}%`;
  }

  renderRepairs(state) {
    const repairs = [
      ["master", "主钟", "广场维修舱 · 三枚齿轮"],
      ["chapel", "六声礼钟", "礼拜堂 · 缺失擒纵销"],
      ["tide", "潮汐钟", "港口 · 三根系船柱"],
    ];
    $("#repair-list").innerHTML = repairs.map(([id, name, note]) => `<div class="repair-card ${state.repairs[id] ? "done" : ""}"><i></i><div><strong>${name}</strong><span>${state.repairs[id] ? "维修完成" : note}</span></div></div>`).join("");
  }

  renderEvidence(state) {
    const knownEvidence = this.content.evidence.filter((entry) => state.knowledge[entry.id]);
    const inventory = Object.keys(state.inventory).filter((id) => state.inventory[id] > 0);
    const evidenceHtml = knownEvidence.map((entry) => `<div class="evidence-card ${state.evidence[entry.id] ? "" : "faint"}"><strong>${escapeHtml(entry.name)}</strong><span>${state.evidence[entry.id] ? "本轮持有共同证据" : "只存在于你的跨轮日志中"}<br>${escapeHtml(entry.text)}</span></div>`);
    const itemHtml = inventory.map((id) => `<div class="evidence-card"><strong>${escapeHtml(itemName(this.content, id))}</strong><span>当前随身物品</span></div>`);
    $("#evidence-list").innerHTML = [...evidenceHtml, ...itemHtml].join("") || '<div class="evidence-card faint"><strong>空白页</strong><span>检查登记簿、钟表机构和现场实物。</span></div>';
  }

  renderPeople(state) {
    $("#people-list").innerHTML = this.content.npcs.filter((npc) => npc.id !== "ada" || state.knowledge.ada_identity).map((npc) => {
      const place = this.content.places.concat(this.content.regions).find((item) => item.id === npc.placeId)?.name || "湖镇";
      return `<div class="person-card"><strong>${escapeHtml(npc.name)}</strong><span>${escapeHtml(npc.role)}<br>通常工作地点：${escapeHtml(place)}</span></div>`;
    }).join("");
  }

  renderNextClue(state) {
    let clue = "先读床边的三份维修委托，再去楼下见旅店主人。";
    if (state.flags.repair_orders_read && repairCount(state) < 3) clue = `已有 ${repairCount(state)}/3 座钟恢复。每次修复都会让一份被封住的现场记录重新可读。`;
    if (repairCount(state) === 3 && !state.evidence.brake_interface) clue = "三座钟同时运转后，主钟舱通往地下的门已经解锁。先看清机器要求谁做什么。";
    if (state.evidence.brake_interface && !state.photos.unfinished_portrait) clue = "地下协议解释了表层终止法。真正缺少的是第七张肖像；最低潮在 SUNDAY 02:00–03:00。";
    if (state.photos.unfinished_portrait && !state.knowledge.ada_identity) clue = "一张脸还不是身份。把残缺肖像与两个独立地点的 A.R. 记录交给档案员。";
    if (state.knowledge.ada_identity && !state.flags.hidden_darkroom_open) clue = "暗房需要三把“锁”：升起西侧配重、照亮银盐门、拿到属于七号房的钥匙。";
    if (state.flags.hidden_darkroom_open && !state.photos.fixed_portrait) clue = "第二暗房的时间不会前进。把姓名、住处、职责和面孔四个锚点一起固定。";
    if (state.photos.fixed_portrait && !state.flags.slot_seven_filled) clue = "定影肖像的尺寸与主钟地下室第七见证位完全一致。";
    if (state.flags.slot_seven_filled) clue = "红色删除杆已经失去作用。白色旋钮允许七名见证人一起进入星期日。";
    $("#next-clue").textContent = clue;
  }

  showBanner(scene) {
    if (!scene || scene.id === this.lastBannerPlace) return;
    this.lastBannerPlace = scene.id;
    clearTimeout(this.bannerTimer);
    $("#region-name").textContent = scene.name;
    $("#region-subtitle").textContent = scene.subtitle || "";
    $("#region-banner").classList.remove("hidden");
    this.bannerTimer = setTimeout(() => $("#region-banner").classList.add("hidden"), 2600);
  }

  setInteraction(target) {
    const hint = $("#interaction-hint");
    if (!target) {
      hint.classList.add("hidden");
      return;
    }
    $("#interaction-text").textContent = target.label;
    hint.classList.remove("hidden");
  }

  fade(active) { $("#fade-layer").classList.toggle("active", active); }

  inspect(title, text, extra = "") {
    $("#inspect-title").textContent = title;
    $("#inspect-text").textContent = text;
    $("#inspect-extra").innerHTML = extra;
    this.openModal("inspect-modal");
  }

  openConversation(npc, state, actions, handlers) {
    $("#conversation-name").textContent = npc.name;
    $("#conversation-role").textContent = npc.role;
    $("#conversation-state").textContent = npc.concern;
    this.drawNpcPortrait($("#conversation-portrait"), npc);
    $("#conversation-history").innerHTML = `<div class="message"><small>${escapeHtml(npc.displayName)}</small>${escapeHtml(this.greetingFor(npc.id, state))}</div>`;
    this.renderConversationActions(actions, handlers.onAction);
    $("#conversation-provider").textContent = "固定选项改变可验证状态；自由对话不会绕过证据锁。";
    const form = $("#conversation-form");
    const input = $("#conversation-input");
    form.onsubmit = (event) => {
      event.preventDefault();
      const message = input.value.trim();
      if (!message) return;
      input.value = "";
      this.appendMessage("你", message, true);
      handlers.onSubmit(message);
    };
    this.openModal("conversation-modal", handlers.onClose);
    setTimeout(() => input.focus(), 50);
  }

  drawNpcPortrait(canvas, npc) {
    const ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    const appearance = npc.appearance || {};
    const skin = appearance.skin || "#dfaa7f";
    const hair = appearance.hair || "#4d3834";
    const body = appearance.body || "#526a69";
    const trim = appearance.trim || "#d5ad63";
    const rect = (x, y, w, h, color) => { ctx.fillStyle = color; ctx.fillRect(x, y, w, h); };
    ctx.clearRect(0, 0, 58, 66);
    rect(0, 0, 58, 66, "#31494b");
    rect(3, 3, 52, 60, "#496164");
    // Back hair, shoulders and a high-contrast collar give every portrait a
    // readable silhouette at 58×66 without importing character-sheet assets.
    if (["long", "bob", "braid"].includes(appearance.hairStyle)) rect(14, 18, 30, 36, hair);
    rect(8, 48, 42, 15, "#302d31");
    rect(11, 45, 36, 18, body);
    rect(13, 47, 32, 4, trim);
    rect(25, 40, 8, 11, skin);
    rect(15, 13, 28, 28, "#382f31");
    rect(17, 15, 24, 27, skin);
    rect(14, 22, 5, 13, skin);
    rect(40, 22, 5, 13, skin);
    // Each hairstyle is drawn as a small deliberate shape, not a recolored cap.
    if (appearance.hairStyle === "bun") {
      rect(14, 10, 30, 11, hair); rect(11, 14, 8, 19, hair); rect(39, 14, 7, 15, hair); rect(35, 5, 11, 11, hair); rect(38, 7, 5, 4, trim);
    } else if (appearance.hairStyle === "long") {
      rect(13, 9, 32, 13, hair); rect(12, 15, 8, 34, hair); rect(39, 15, 8, 34, hair); rect(18, 12, 12, 4, trim);
    } else if (appearance.hairStyle === "braid") {
      rect(13, 10, 32, 12, hair); rect(12, 16, 8, 19, hair); rect(39, 16, 7, 14, hair); rect(42, 29, 6, 8, hair); rect(43, 37, 5, 8, hair); rect(44, 45, 4, 5, trim);
    } else if (appearance.hairStyle === "bob") {
      rect(13, 10, 32, 12, hair); rect(12, 15, 8, 26, hair); rect(39, 15, 8, 26, hair); rect(19, 12, 11, 4, trim);
    } else {
      rect(13, 10, 32, 12, hair); rect(12, 16, 8, 18, hair); rect(38, 13, 8, 16, hair); rect(18, 12, 10, 4, trim);
    }
    rect(21, 26, 4, 4, "#3b3436"); rect(34, 26, 4, 4, "#3b3436");
    rect(23, 27, 2, 2, "#d8e1cd"); rect(34, 27, 2, 2, "#d8e1cd");
    rect(28, 31, 3, 3, "#b77e61"); rect(25, 36, 9, 2, "#8a574f");
    if (appearance.accessory === "glasses") {
      rect(18, 24, 10, 8, "#403e3e"); rect(31, 24, 10, 8, "#403e3e"); rect(28, 27, 3, 2, "#403e3e");
      rect(20, 26, 6, 4, "#78979a"); rect(33, 26, 6, 4, "#78979a");
    }
    if (appearance.accessory === "kerchief" || appearance.accessory === "headband") rect(14, 15, 30, 4, trim);
    rect(4, 4, 16, 2, "rgba(235,223,183,.28)");
  }

  greetingFor(id, state) {
    const repeat = state.loopCount > 0;
    const lines = {
      arthur: repeat ? "你看我的眼神像是我们已经谈过。可对我而言，这是今天第一次见面。请从本轮证据开始。" : "维修工？主机构在里面。先让钟重新转起来，我们再谈那些不该出现在图纸上的部分。",
      beatrice: "进来时别碰最右边那根绳。它不属于六声报时。",
      conrad: "湖今天在说两套时间。修好潮汐盘之前，我哪套都不信。",
      dorothea: "八号房睡得还好吗？早餐在炉边，工具和登记簿都在柜台上。",
      elias: "如果你带来的是传闻，我只能请你喝茶；如果是底片，我有显影液。",
      florence: "先告诉我你带来了原件、抄本，还是仅仅记得一个结论。三者不能混写。",
      ada: "这一次，你终于让我的脸、名字、房间和工作属于同一个人。",
    };
    return lines[id] || "他停下手里的工作，等你先开口。";
  }

  renderConversationActions(actions, onAction) {
    const container = $("#conversation-actions");
    container.innerHTML = "";
    actions.forEach((action) => this.addChoice(container, action.label, () => onAction(action)));
  }

  appendMessage(speaker, text, player = false) {
    const history = $("#conversation-history");
    const element = document.createElement("div");
    element.className = `message${player ? " player" : ""}`;
    element.innerHTML = `<small>${escapeHtml(speaker)}</small>${escapeHtml(text)}`;
    history.append(element);
    history.scrollTop = history.scrollHeight;
  }

  setConversationPending(pending) {
    const input = $("#conversation-input");
    const button = $("#conversation-form button");
    input.disabled = pending;
    button.disabled = pending;
    button.textContent = pending ? "思考…" : "交谈";
  }

  setConversationProvider(text) { $("#conversation-provider").textContent = text; }

  openPuzzle(type, state, onComplete) {
    const title = $("#puzzle-title");
    const instruction = $("#puzzle-instruction");
    const board = $("#puzzle-board");
    const feedback = $("#puzzle-feedback");
    board.innerHTML = "";
    feedback.textContent = "";
    const complete = () => {
      feedback.textContent = "机构发出一声干净的咬合声。";
      onComplete?.();
      setTimeout(() => this.closeModal("puzzle-modal"), 650);
    };
    if (type === "master") {
      $("#puzzle-kicker").textContent = "MASTER CLOCK / GEAR TRAIN";
      title.textContent = "让三道红线一起朝上";
      instruction.textContent = "拖动齿轮交换槽位；点击一个槽选中它，再按 Q / E 旋转。齿轮尺寸和校准线必须同时正确。";
      const gears = ["small", "large", "medium"];
      const rotations = [1, 2, 3];
      let selected = 0;
      let dragging = null;
      const labels = { small: "小", medium: "中", large: "大" };
      const render = () => {
        board.innerHTML = `<div class="gear-grid">${gears.map((gear, index) => `<div class="gear-slot ${selected === index ? "selected" : ""}" data-index="${index}"><div class="gear" draggable="true" style="transform:rotate(${rotations[index] * 90}deg)" data-index="${index}">↑</div><small>${index + 1} 号槽 · ${labels[gear]}齿轮</small></div>`).join("")}</div><button class="puzzle-submit" id="test-master">试运行</button>`;
        $$(".gear-slot").forEach((slot) => {
          slot.addEventListener("click", () => { selected = Number(slot.dataset.index); render(); });
          slot.addEventListener("dragover", (event) => event.preventDefault());
          slot.addEventListener("drop", () => {
            const target = Number(slot.dataset.index);
            if (dragging === null || target === dragging) return;
            [gears[dragging], gears[target]] = [gears[target], gears[dragging]];
            [rotations[dragging], rotations[target]] = [rotations[target], rotations[dragging]];
            selected = target; dragging = null; render();
          });
        });
        $$(".gear").forEach((gear) => gear.addEventListener("dragstart", () => { dragging = Number(gear.dataset.index); }));
        $("#test-master").addEventListener("click", () => {
          if (gears.join(",") === "medium,large,small" && rotations.every((value) => value % 4 === 0)) complete();
          else feedback.textContent = "齿轮能转，但红线没有同时经过上方的基准刻痕。";
        });
      };
      this.puzzleKeyHandler = (event) => {
        if ($("#puzzle-modal").classList.contains("hidden") || !["q", "Q", "e", "E"].includes(event.key)) return;
        event.preventDefault();
        rotations[selected] = (rotations[selected] + (event.key.toLowerCase() === "q" ? 3 : 1)) % 4;
        render();
      };
      document.addEventListener("keydown", this.puzzleKeyHandler);
      render();
    } else if (type === "chapel") {
      $("#puzzle-kicker").textContent = "CHAPEL / SIX-HAMMER ESCAPEMENT";
      title.textContent = "找回缺失的第四拍";
      instruction.textContent = "六锤机构少了一枚普通擒纵销。安装实物后拉绳测试；第七锤不属于这次维修。";
      const hasPin = Boolean(state.inventory.chapel_pin);
      board.innerHTML = `<div class="sequence-grid">${[1,2,3,4,5,6].map((n) => `<button disabled>${n === 4 ? "空槽" : `第 ${n} 锤`}</button>`).join("")}</div><button class="puzzle-submit" id="install-pin">${hasPin ? "安装擒纵销并拉绳" : "缺少擒纵销"}</button>`;
      $("#install-pin").disabled = !hasPin;
      $("#install-pin").addEventListener("click", complete);
      if (!hasPin) feedback.textContent = "长椅下面似乎有一件黄铜小零件。";
    } else if (type === "tide") {
      $("#puzzle-kicker").textContent = "HARBOR / TIDE CLOCK";
      title.textContent = "让刻度记住真实的水线";
      instruction.textContent = "港外三根系船柱的新水线依次是低、中、高。点击三枚刻度环切换读数。";
      const values = [2, 0, 1];
      const labels = ["低", "中", "高"];
      const render = () => {
        board.innerHTML = `<div class="tide-grid">${values.map((value, index) => `<button class="dial-button" data-index="${index}">第 ${index + 1} 环<strong>${labels[value]}</strong></button>`).join("")}</div><button class="puzzle-submit" id="test-tide">对照三根系船柱</button>`;
        $$(".dial-button").forEach((button) => button.addEventListener("click", () => { const i = Number(button.dataset.index); values[i] = (values[i] + 1) % 3; render(); }));
        $("#test-tide").addEventListener("click", () => {
          if (values.join(",") === "0,1,2") complete();
          else feedback.textContent = "测试浮标撞上了错误的水位限位。回到港外重新读三条水线。";
        });
      };
      render();
    } else if (type === "photo") {
      $("#puzzle-kicker").textContent = "SILVER-SALT DEVELOPMENT";
      title.textContent = "不要让想象替乳剂作证";
      instruction.textContent = "按伊莱亚斯给出的检查顺序处理底片：先排除重影，再建立反差，最后校正湖面反射。";
      const correct = ["重影检查", "反差拉伸", "反射校正"];
      const available = ["反射校正", "重影检查", "反差拉伸"];
      const chosen = [];
      const render = () => {
        board.innerHTML = `<div class="sequence-grid">${available.map((label) => `<button data-label="${label}" class="${chosen.includes(label) ? "done" : ""}">${label}</button>`).join("")}</div><p>当前顺序：${chosen.join(" → ") || "尚未开始"}</p>`;
        $$(".sequence-grid button").forEach((button) => button.addEventListener("click", () => {
          const label = button.dataset.label;
          if (chosen.includes(label)) return;
          if (label !== correct[chosen.length]) {
            chosen.splice(0);
            feedback.textContent = "乳剂开始朝主观轮廓聚集。伊莱亚斯立刻冲掉试片：顺序错了，重新来。";
          } else {
            chosen.push(label);
            feedback.textContent = chosen.length < 3 ? "这一层影像稳定了。" : "脸部与 A.R. 缩写从湖面重影下显现。";
            if (chosen.length === 3) { render(); setTimeout(complete, 350); return; }
          }
          render();
        }));
      };
      render();
    } else if (type === "identity") {
      $("#puzzle-kicker").textContent = "RETURN EXPOSURE / IDENTITY FIXING";
      title.textContent = "让四个锚点属于同一个人";
      instruction.textContent = "暗房不会替你补全身份。每个锚点都必须来自本轮可核验的实物或记录。";
      const missing = describeMissingIdentityAnchors(state);
      const all = ["姓名与职责", "住处", "面孔"];
      board.innerHTML = `<div class="sequence-grid">${all.map((label) => `<button disabled class="${missing.some((item) => item.startsWith(label)) ? "" : "done"}">${label}<br>${missing.some((item) => item.startsWith(label)) ? "未固定" : "已固定"}</button>`).join("")}</div><button class="puzzle-submit" id="fix-identity">完成定影</button>`;
      $("#fix-identity").disabled = missing.length > 0;
      $("#fix-identity").addEventListener("click", complete);
      feedback.textContent = missing.length ? `仍缺：${missing.join("；")}` : "四种来源互不替代，但现在它们指向同一个人。";
    }
    this.openModal("puzzle-modal");
  }

  renderJournal(state) {
    $("#journal-full").innerHTML = [...state.journal].reverse().map((entry) => `<article class="journal-entry"><time>${escapeHtml(entry.stamp)}<br>LOOP ${String(entry.loop).padStart(2, "0")}</time><p>${escapeHtml(entry.text)}</p></article>`).join("") || "还没有留下记录。";
    this.openModal("journal-modal");
  }

  renderArchive(savedState) {
    const endings = JSON.parse(localStorage.getItem("time-echo-endings") || "[]");
    const loops = Number(savedState?.loopCount || 0) + (savedState ? 1 : 0);
    $("#archive-content").innerHTML = `<article class="journal-entry"><time>LOOPS</time><p>已经进入 ${loops} 个星期六清晨。</p></article>${endings.length ? endings.map((ending) => `<article class="journal-entry"><time>${escapeHtml(ending.stamp)}</time><p>${ending.id === "true" ? "七人继续：正确的星期日" : "六人终止：失去第七人的星期日"}</p></article>`).join("") : '<article class="journal-entry"><time>ENDING</time><p>还没有任何星期日被完整见证。</p></article>'}`;
    this.openModal("archive-modal");
  }

  playReset(loopCount, onDone) {
    const layer = $("#reset-cinematic");
    const canvas = $("#reset-canvas");
    const ctx = canvas.getContext("2d");
    layer.classList.remove("hidden");
    layer.classList.add("flash");
    $("#reset-line-a").textContent = "THE BELL ATTEMPTS A SEVENTH STRIKE";
    $("#reset-line-b").textContent = "SATURDAY · 06:00";
    const start = performance.now();
    let raf = 0;
    const draw = (now) => {
      const t = (now - start) / 1000;
      ctx.fillStyle = "#071315"; ctx.fillRect(0, 0, 768, 480);
      ctx.fillStyle = "#10272b"; ctx.fillRect(0, 250, 768, 230);
      ctx.fillStyle = "#142326"; ctx.beginPath(); ctx.moveTo(0,250); ctx.lineTo(130,120); ctx.lineTo(260,246); ctx.lineTo(390,145); ctx.lineTo(530,248); ctx.lineTo(650,112); ctx.lineTo(768,240); ctx.fill();
      const lineWidth = Math.min(768, Math.max(0, (t - .5) * 260));
      ctx.fillStyle = `rgba(226,237,221,${Math.min(.9, Math.max(0, t - .4) * .32)})`;
      ctx.fillRect((768 - lineWidth) / 2, 286, lineWidth, Math.max(2, (t - 1.4) * 120));
      if (t < 4) raf = requestAnimationFrame(draw);
    };
    raf = requestAnimationFrame(draw);
    let finished = false;
    const finish = () => {
      if (finished) return;
      finished = true;
      cancelAnimationFrame(raf);
      layer.classList.add("hidden");
      layer.classList.remove("flash");
      document.removeEventListener("keydown", skip);
      onDone?.();
    };
    const skip = (event) => { if (event.key === "Enter" && loopCount > 0) finish(); };
    document.addEventListener("keydown", skip);
    setTimeout(finish, loopCount > 0 ? 4200 : 5600);
  }

  showEnding(id) {
    const trueEnding = id === "true";
    $("#ending-modal").classList.toggle("true", trueEnding);
    $("#ending-kicker").textContent = "SUNDAY · 06:01";
    $("#ending-title").textContent = trueEnding ? "七声之后，仍有七个人" : "一个少了名字的星期日";
    $("#ending-text").innerHTML = trueEnding
      ? "金色晨光从正确的方向越过山脊，房屋的影子第一次背向湖面。<br>礼拜堂传来七声完整钟响。渡船抵岸时，艾达站在六位居民之间；没有人需要被删除，时间也没有倒退。它只是继续。"
      : "渡船真的抵达了。六位居民在码头向你告别，没有人记得还应有第七个人。<br>你的日志仍写着 Ada Rowan，但定影照片已经变成空白。地下室第七格熄灭，用一个人的缺席换来了星期日。";
    $("#ending-modal").classList.remove("hidden");
  }

  notify(text) {
    this.inspect("维修日志更新", text);
  }
}

export default GameUI;
