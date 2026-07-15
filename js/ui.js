import { escapeHtml, formatStamp, formatTime } from "./utils.js";
import { FACTION_META, METRIC_META } from "./simulation.js";

const MAP_POSITIONS = {
  capital: { left: "41%", top: "35%" },
  farm: { left: "13%", top: "59%" },
  mansion: { left: "17%", top: "12%" },
  snow: { left: "62%", top: "6%" },
  desert: { left: "68%", top: "61%" },
};

const MAP_VIEWBOX = { width: 960, height: 540 };
const MAP_NODE_OFFSET = { x: 8.5, y: 11.5 };
const MAP_ROUTE_KINDS = new Set(["road", "carriage", "lift", "caravan", "trail"]);
const PORTRAIT_SKINS = {
  aveline: "#edbd91", rowan: "#d99a72", taren: "#b87558", mira: "#efc39a", bo: "#c98963",
  nia: "#a96850", celeste: "#e8b887", oswin: "#d8a179", lune: "#efc6a0", sora: "#c98563",
  garrick: "#b77759", ymir: "#e4b58d", zahra: "#9d5e49", kade: "#d09369", ruu: "#efc39b",
};

function numericPercent(value, fallback = 50) {
  const number = typeof value === "number" ? value : Number.parseFloat(String(value ?? ""));
  return Number.isFinite(number) ? number : fallback;
}

function clampMapPercent(value, margin) {
  return Math.max(margin, Math.min(100 - margin, value));
}

export class GameUI {
  constructor(content, callbacks = {}) {
    this.content = content;
    this.callbacks = callbacks;
    this.state = null;
    this.currentNpc = null;
    this.startMode = "player";
    this.lastLayoutMode = null;
    this.cachedJournalHead = null;
    this.transitionLocked = false;
    this.elements = this.collectElements();
    this.bindStaticEvents();
    this.renderTimelineOptions();
  }

  collectElements() {
    const ids = [
      "loading-screen", "title-screen", "game-shell", "new-game-button", "observe-game-button", "continue-button", "chronicles-button",
      "timeline-label", "mode-chip", "day-label", "time-label", "weather-label", "sound-button", "save-button", "help-button",
      "location-kicker", "location-label", "map-button", "journal-button", "sidebar-toggle-button", "wait-button", "metric-list", "faction-list", "nearby-heading", "nearby-card",
      "people-list", "journal-list", "journal-full", "timeline-modal", "timeline-options", "map-modal", "world-map",
      "timeline-title", "timeline-description", "map-note",
      "conversation-modal", "conversation-portrait", "conversation-role", "conversation-name", "conversation-mood",
      "conversation-history", "conversation-actions", "conversation-form", "conversation-input", "conversation-provider",
      "observer-modal", "observer-portrait", "observer-role", "observer-name", "observer-status", "observer-goal",
      "observer-reflection", "observer-memories", "observer-knowledge",
      "ending-modal", "ending-glyph", "ending-title", "ending-subtitle", "ending-epilogue", "ending-summary",
      "new-timeline-button", "keep-wandering-button", "chronicles-modal", "ending-gallery", "journal-modal", "help-modal",
      "interaction-hint", "interaction-text", "observer-badge", "region-banner", "region-name", "region-subtitle", "fade-layer",
      "ai-status-dot", "ai-status-label", "ai-status-detail", "llm-toggle", "thought-toggle", "toast-stack", "aria-status",
      "help-title", "help-description",
    ];
    return Object.fromEntries(ids.map((id) => [id.replaceAll("-", "_"), document.getElementById(id)]));
  }

  bindStaticEvents() {
    const el = this.elements;
    el.new_game_button.addEventListener("click", () => this.prepareTimelineSelection("player"));
    el.observe_game_button.addEventListener("click", () => this.prepareTimelineSelection("observer"));
    el.continue_button.addEventListener("click", () => this.callbacks.onContinue?.());
    el.chronicles_button.addEventListener("click", () => this.showEndingGallery());
    el.map_button.addEventListener("click", () => this.showMap());
    el.journal_button.addEventListener("click", () => this.showJournal());
    el.sidebar_toggle_button.addEventListener("click", () => this.toggleSidebar());
    el.wait_button.addEventListener("click", () => this.callbacks.onWait?.());
    el.save_button.addEventListener("click", () => this.callbacks.onSave?.());
    el.sound_button.addEventListener("click", () => this.callbacks.onToggleSound?.());
    el.help_button.addEventListener("click", () => this.openModal("help-modal"));
    el.new_timeline_button.addEventListener("click", () => {
      this.closeModal("ending-modal", true);
      this.prepareTimelineSelection(this.state?.mode || this.startMode);
    });
    el.keep_wandering_button.addEventListener("click", () => {
      this.closeModal("ending-modal", true);
      this.callbacks.onKeepWandering?.();
    });
    el.conversation_form.addEventListener("submit", (event) => {
      event.preventDefault();
      const message = el.conversation_input.value.trim();
      if (!message) return;
      el.conversation_input.value = "";
      this.callbacks.onTalk?.(message, "custom");
    });
    el.llm_toggle.addEventListener("change", () => this.callbacks.onToggleLlm?.(el.llm_toggle.checked));
    el.thought_toggle.addEventListener("change", () => {
      this.callbacks.onToggleThoughts?.(el.thought_toggle.checked);
      if (this.state) this.renderJournal(this.state);
    });
    document.querySelectorAll("[data-close]").forEach((button) => {
      button.addEventListener("click", () => this.closeModal(button.dataset.close));
    });
    document.querySelectorAll(".sidebar-tab").forEach((button) => {
      button.addEventListener("click", () => this.selectTab(button.dataset.tab));
    });
    document.querySelectorAll("[data-speed]").forEach((button) => {
      button.addEventListener("click", () => {
        document.querySelectorAll("[data-speed]").forEach((item) => item.classList.remove("active"));
        button.classList.add("active");
        this.callbacks.onSpeed?.(Number(button.dataset.speed));
      });
    });
  }

  finishLoading(hasSave, saveMode = "player") {
    this.elements.loading_screen.classList.add("hidden");
    this.elements.title_screen.classList.remove("hidden");
    this.elements.continue_button.classList.toggle("hidden", !hasSave);
    if (hasSave) this.elements.continue_button.textContent = saveMode === "observer" ? "Continue Watching" : "Continue Journey";
  }

  showTitle(hasSave = false) {
    this.closeAllModals(true);
    this.elements.game_shell.classList.add("hidden");
    this.elements.title_screen.classList.remove("hidden");
    this.elements.continue_button.classList.toggle("hidden", !hasSave);
  }

  showGame() {
    this.elements.title_screen.classList.add("hidden");
    this.elements.game_shell.classList.remove("hidden");
    this.closeModal("timeline-modal", true);
  }

  prepareTimelineSelection(mode = "player") {
    this.startMode = mode === "observer" ? "observer" : "player";
    const observer = this.startMode === "observer";
    this.elements.timeline_title.textContent = observer ? "选择要观察的世界线" : "选择要踏入的世界线";
    this.elements.timeline_description.textContent = observer
      ? "你不会出现在世界中。三条线从左到右由易到难，持续压力会影响居民如何走到第九日。"
      : "三条线从左到右由易到难；差异会持续影响每日消耗与居民恢复，不只改变开局。";
    this.openModal("timeline-modal");
  }

  renderTimelineOptions() {
    this.elements.timeline_options.innerHTML = "";
    (this.content.timelines || []).forEach((timeline, index) => {
      const button = document.createElement("button");
      button.className = "timeline-card";
      button.style.setProperty("--thread-color", timeline.color || ["#d9a85c", "#72b798", "#9d83bd"][index % 3]);
      const configuredDifficulty = timeline.difficulty || {};
      const difficultyRank = Math.min(3, Math.max(1, Math.round(Number(configuredDifficulty.rank) || index + 1)));
      const difficultyLabel = configuredDifficulty.label || ["简单", "普通", "困难"][difficultyRank - 1];
      button.dataset.difficulty = String(difficultyRank);
      button.setAttribute("aria-label", `${timeline.name}，难度 ${difficultyRank}/3，${difficultyLabel}`);
      const hints = timeline.hints || timeline.features || Object.entries(timeline.modifiers?.metrics || {}).map(([key, value]) => `${METRIC_META[key]?.label || key} ${value >= 0 ? "+" : ""}${value}`);
      button.innerHTML = `
        <span class="timeline-difficulty"><span>难度 ${difficultyRank}/3</span><strong>${escapeHtml(difficultyLabel)}</strong><i aria-hidden="true">${"◆".repeat(difficultyRank)}${"◇".repeat(3 - difficultyRank)}</i></span>
        <span class="thread-glyph">${escapeHtml(timeline.glyph || ["◇", "✦", "◈"][index % 3])}</span>
        <h3>${escapeHtml(timeline.name)}</h3>
        <p>${escapeHtml(timeline.description || timeline.subtitle || "一条尚未被见证的世界线。")}</p>
        <ul>${hints.slice(0, 3).map((hint) => `<li>${escapeHtml(hint)}</li>`).join("")}</ul>`;
      button.addEventListener("click", () => this.callbacks.onNewGame?.(timeline.id, this.startMode));
      this.elements.timeline_options.appendChild(button);
    });
  }

  update(state, nearby = null) {
    this.state = state;
    const timeline = this.content.timelines.find((item) => item.id === state.timelineId);
    const location = this.describeLocation(state.regionId, state.placeId);
    this.configureMode(state);
    this.elements.timeline_label.textContent = timeline?.name || state.timelineName;
    this.elements.day_label.textContent = `第 ${state.day} 日`;
    this.elements.time_label.textContent = formatTime(state.minute);
    this.elements.weather_label.textContent = state.weather;
    this.elements.location_label.textContent = location.title;
    this.renderMetrics(state);
    this.renderFactions(state);
    this.renderNearby(nearby, state);
    this.renderPeople(state);
    if (this.cachedJournalHead !== state.journal[0]?.id) this.renderJournal(state);
  }

  places() {
    if (Array.isArray(this.content.places)) return this.content.places;
    if (this.content.places && typeof this.content.places === "object") return Object.values(this.content.places);
    return [];
  }

  findPlace(placeId) {
    if (!placeId) return null;
    return this.places().find((item) => item.id === placeId) || null;
  }

  describeLocation(regionId, placeId) {
    const region = this.content.regions.find((item) => item.id === regionId) || null;
    const place = this.findPlace(placeId);
    const regionName = region?.name || regionId || "未知地区";
    const explicitPlaceName = place?.name || place?.label || "";
    const rawPlaceName = !place && placeId && placeId !== regionId ? String(placeId) : "";
    const placeName = explicitPlaceName || rawPlaceName;
    const normalizedRegion = regionName.replace(/\s+/g, "").toLowerCase();
    const normalizedPlace = placeName.replace(/\s+/g, "").toLowerCase();
    const isOutdoor = !place
      || placeId === regionId
      || place.kind === "outdoor"
      || place.outdoor === true
      || place.isDefault === true
      || (normalizedPlace && normalizedPlace === normalizedRegion);
    return {
      region,
      place,
      regionName,
      placeName: isOutdoor ? "" : placeName,
      title: !isOutdoor && placeName ? `${regionName} · ${placeName}` : regionName,
      key: `${regionId || ""}::${placeId || regionId || ""}`,
    };
  }

  sameLocation(left, right) {
    if (!left || !right || left.regionId !== right.regionId) return false;
    const leftPlace = left.placeId || left.regionId;
    const rightPlace = right.placeId || right.regionId;
    return leftPlace === rightPlace;
  }

  configureMode(state) {
    const observer = state.mode === "observer";
    if (this.lastLayoutMode !== state.mode) {
      this.setSidebarCollapsed(!observer);
      this.lastLayoutMode = state.mode;
    }
    document.body.classList.toggle("observer-mode", observer);
    this.elements.mode_chip.textContent = observer ? "上帝观察" : "旅行者";
    this.elements.mode_chip.classList.toggle("observer", observer);
    this.elements.observer_badge.classList.toggle("hidden", !observer);
    this.elements.location_kicker.textContent = observer ? "当前观察地点" : "当前位置";
    this.elements.nearby_heading.textContent = observer ? "观察方式" : "眼前的人";
    this.elements.wait_button.textContent = observer ? "推进 1 小时" : "等待 1 小时";
    this.elements.help_title.textContent = observer ? "上帝观察手册" : "旅行者手册";
    this.elements.help_description.textContent = observer
      ? "世界中没有玩家。用 WASD 或方向键平移镜头，按 M 切换五地；公告、封路和灾后痕迹会随社会进程改变，人物志可查看居民如何形成自己的结果。"
      : "用 WASD 或方向键移动，按住 Shift 疾跑；靠近人物、告示、门或交通点后按 E。公共事件不会弹出选择题：留意地图变化，与知情者建立信任，再把主张交给真正参与商议的人。错过消息时，世界仍会继续。";
    this.elements.new_timeline_button.textContent = observer ? "观察另一条世界线" : "踏入另一条世界线";
    this.elements.keep_wandering_button.textContent = observer ? "停在结局前夜继续观察" : "留在结局前夜";
    if (observer) this.elements.interaction_hint.classList.add("hidden");
  }

  setSidebarCollapsed(collapsed) {
    document.body.classList.toggle("sidebar-collapsed", collapsed);
    this.elements.sidebar_toggle_button.setAttribute("aria-expanded", String(!collapsed));
    this.elements.sidebar_toggle_button.textContent = collapsed ? "B 打开手账" : "B 收起手账";
  }

  toggleSidebar() {
    if (this.transitionLocked) return;
    this.setSidebarCollapsed(!document.body.classList.contains("sidebar-collapsed"));
  }

  setTransitionLocked(locked) {
    this.transitionLocked = Boolean(locked);
    this.elements.map_button.disabled = this.transitionLocked;
    this.elements.journal_button.disabled = this.transitionLocked;
    this.elements.sidebar_toggle_button.disabled = this.transitionLocked;
  }

  setSpeedIndicator(speed) {
    document.querySelectorAll("[data-speed]").forEach((button) => button.classList.toggle("active", Number(button.dataset.speed) === Number(speed)));
  }

  renderMetrics(state) {
    this.elements.metric_list.innerHTML = Object.entries(METRIC_META).map(([key, meta]) => {
      const value = Math.round(state.metrics[key] ?? 0);
      return `<div class="metric-row" title="${escapeHtml(meta.label)} ${value}/100">
        <label>${escapeHtml(meta.label)}</label>
        <div class="metric-track"><span class="metric-fill" style="width:${value}%;--metric-color:${meta.color}"></span></div>
        <output>${value}</output>
      </div>`;
    }).join("");
  }

  renderFactions(state) {
    this.elements.faction_list.innerHTML = Object.entries(FACTION_META).map(([key, meta]) => `
      <div class="faction-card" style="border-top:3px solid ${meta.color}"><span>${escapeHtml(meta.label)}</span><strong>${Math.round(state.factions[key] ?? 0)}</strong></div>
    `).join("");
  }

  portraitAttributes(npc, known = true) {
    const npcColor = known ? npc.color || "#8b708e" : "#756c62";
    const hairColor = known ? npc.hairColor || "#4d3632" : "#574f49";
    const skinColor = known ? npc.skinColor || PORTRAIT_SKINS[npc.id] || "#efbf87" : "#a99a86";
    return `data-portrait="${escapeHtml(known ? npc.id : "unknown")}" style="--npc-color:${escapeHtml(npcColor)};--hair-color:${escapeHtml(hairColor)};--skin-color:${escapeHtml(skinColor)}"`;
  }

  renderNearby(nearby, state = this.state) {
    const card = this.elements.nearby_card;
    if (state?.mode === "observer") {
      const npcId = state.observer?.focusedNpcId;
      const npc = this.content.npcs.find((item) => item.id === npcId);
      const npcState = npc ? state.npcs[npc.id] : null;
      if (!npc || !npcState) {
        card.className = "nearby-card empty";
        card.textContent = "世界中没有玩家。打开“人物”页，可以翻阅每位居民的目标、反思和近期记忆。";
        return;
      }
      const location = this.describeLocation(npcState.regionId, npcState.placeId);
      const current = this.sameLocation(npcState, state);
      card.className = "nearby-card";
      card.innerHTML = `<div class="nearby-person">
        <div class="mini-portrait" ${this.portraitAttributes(npc)}></div>
        <div><strong>正在观察：${escapeHtml(npc.name)}</strong><small>${escapeHtml(location.title)} · ${escapeHtml(npcState.activity)}</small>
        <div class="nearby-meta"><span class="tag">${current ? "◉ 当前镜头" : "◎ 其他地点"}</span><span class="tag">${escapeHtml(npcState.mood)}</span><span class="tag">记忆 ${npcState.memories.length}</span></div></div>
      </div>`;
      return;
    }
    if (!nearby) {
      card.className = "nearby-card empty";
      card.textContent = "靠近居民后，可以看看他正在做什么。";
      return;
    }
    const { profile: npc, state: npcState } = nearby;
    card.className = "nearby-card";
    card.innerHTML = `<div class="nearby-person">
      <div class="mini-portrait" ${this.portraitAttributes(npc)}></div>
      <div><strong>${escapeHtml(npc.name)} · ${escapeHtml(npc.role)}</strong><small>${escapeHtml(npcState.activity)} · ${escapeHtml(npcState.mood)}</small>
      <div class="nearby-meta"><span class="tag">关系 ${Math.round(npcState.relationship)}</span><span class="tag">记忆 ${npcState.memories.length}</span></div></div>
    </div>`;
  }

  renderPeople(state) {
    const observer = state.mode === "observer";
    const sorted = [...this.content.npcs].sort((a, b) => {
      const aState = state.npcs[a.id];
      const bState = state.npcs[b.id];
      if (observer) {
        return Number(this.sameLocation(bState, state)) - Number(this.sameLocation(aState, state))
          || Number(bState?.regionId === state.regionId) - Number(aState?.regionId === state.regionId)
          || a.name.localeCompare(b.name, "zh-CN");
      }
      return Number(Boolean(bState?.knownToPlayer)) - Number(Boolean(aState?.knownToPlayer)) || (bState?.relationship || 0) - (aState?.relationship || 0);
    });
    this.elements.people_list.innerHTML = sorted.map((npc) => {
      const npcState = state.npcs[npc.id];
      const known = observer || npcState?.knownToPlayer;
      const location = this.describeLocation(npcState?.regionId, npcState?.placeId);
      const current = this.sameLocation(npcState, state);
      return `<button class="person-entry" data-npc-id="${escapeHtml(npc.id)}">
        <div class="mini-portrait" ${this.portraitAttributes(npc, known)}></div>
        <span><strong>${known ? escapeHtml(npc.name) : "尚未结识"}</strong><small>${known ? `${escapeHtml(npc.role)} · ${escapeHtml(location.title)}` : escapeHtml(location.title)}</small></span>
        <span class="relation-value">${observer ? (current ? "◉" : "◎") : known ? Math.round(npcState.relationship) : "?"}</span>
      </button>`;
    }).join("");
    this.elements.people_list.querySelectorAll("[data-npc-id]").forEach((button) => {
      button.addEventListener("click", () => this.callbacks.onInspectNpc?.(button.dataset.npcId));
    });
  }

  renderJournal(state) {
    const showThoughts = this.elements.thought_toggle.checked;
    const entries = state.journal.filter((entry) => showThoughts || entry.type !== "thought");
    const render = (entry) => `<article class="journal-entry ${escapeHtml(entry.type || "world")}"><time>${escapeHtml(formatStamp(entry.day, entry.minute))}</time><p>${escapeHtml(entry.text)}</p></article>`;
    this.elements.journal_list.innerHTML = entries.slice(0, 18).map(render).join("") || '<div class="nearby-card empty">故事还没有开始。</div>';
    this.elements.journal_full.innerHTML = entries.map(render).join("");
    this.cachedJournalHead = state.journal[0]?.id;
  }

  selectTab(name) {
    document.querySelectorAll(".sidebar-tab").forEach((button) => button.classList.toggle("active", button.dataset.tab === name));
    document.querySelectorAll(".tab-pane").forEach((pane) => pane.classList.toggle("active", pane.id === `tab-${name}`));
  }

  regionConnections(regionId) {
    const regionIds = new Set(this.content.regions.map((region) => region.id));
    const region = this.content.regions.find((item) => item.id === regionId);
    return (region?.portals || [])
      .filter((portal) => !portal.disabled
        && portal.target?.regionId
        && portal.target.regionId !== regionId
        && regionIds.has(portal.target.regionId))
      .map((portal) => ({ regionId: portal.target.regionId, portal }));
  }

  findRegionRoute(fromRegionId, targetRegionId) {
    if (!fromRegionId || !targetRegionId || fromRegionId === targetRegionId) return [];
    const queue = [{ regionId: fromRegionId, legs: [] }];
    const visited = new Set([fromRegionId]);
    while (queue.length) {
      const current = queue.shift();
      for (const connection of this.regionConnections(current.regionId)) {
        if (visited.has(connection.regionId)) continue;
        const legs = [...current.legs, { fromRegionId: current.regionId, ...connection }];
        if (connection.regionId === targetRegionId) return legs;
        visited.add(connection.regionId);
        queue.push({ regionId: connection.regionId, legs });
      }
    }
    return null;
  }

  describeMapRoute(fromRegionId, targetRegionId) {
    const direct = this.regionConnections(fromRegionId).filter((connection) => connection.regionId === targetRegionId);
    if (direct.length) {
      return direct.map(({ portal }) => {
        const minutes = Math.max(0, Number(portal.minutes || 0));
        return `${portal.label || "实际交通点"}${minutes > 0 ? ` · ${minutes} 分钟` : ""}`;
      }).join(" / ");
    }
    const route = this.findRegionRoute(fromRegionId, targetRegionId);
    if (!route?.length) return "无直达交通，当前路线未连通";
    const intermediateIds = route.slice(0, -1).map((leg) => leg.regionId);
    const intermediateNames = intermediateIds.map((regionId) => this.content.regions.find((region) => region.id === regionId)?.name || regionId);
    const totalMinutes = route.reduce((sum, leg) => sum + Math.max(0, Number(leg.portal.minutes || 0)), 0);
    return `无直达交通，需经${intermediateNames.join("、")}中转${totalMinutes > 0 ? ` · 约 ${totalMinutes} 分钟` : ""}`;
  }

  mapPoint(region, index) {
    const fallback = { left: `${8 + (index % 3) * 31}%`, top: `${10 + Math.floor(index / 3) * 48}%` };
    const position = region.mapPosition || MAP_POSITIONS[region.id] || fallback;
    // Existing mapPosition values described the top-left corner of the old cards.
    // Keep those authored coordinates useful by shifting them to the illustrated icon centre.
    const centered = position.anchor === "center";
    const rawX = numericPercent(position.x ?? position.left, numericPercent(fallback.left));
    const rawY = numericPercent(position.y ?? position.top, numericPercent(fallback.top));
    const x = clampMapPercent(rawX + (centered ? 0 : MAP_NODE_OFFSET.x), 8);
    const y = clampMapPercent(rawY + (centered ? 0 : MAP_NODE_OFFSET.y), 12);
    return {
      x,
      y,
      svgX: x / 100 * MAP_VIEWBOX.width,
      svgY: y / 100 * MAP_VIEWBOX.height,
    };
  }

  mapRouteEdges() {
    const edges = new Map();
    this.content.regions.forEach((region) => {
      this.regionConnections(region.id).forEach(({ regionId, portal }) => {
        const ends = [region.id, regionId].sort();
        const key = ends.join("--");
        if (edges.has(key)) return;
        const rawKind = String(portal.kind || "road").toLowerCase();
        edges.set(key, {
          key,
          from: region.id,
          to: regionId,
          kind: MAP_ROUTE_KINDS.has(rawKind) ? rawKind : "road",
          label: portal.label || "地区道路",
        });
      });
    });
    return [...edges.values()].sort((left, right) => left.key.localeCompare(right.key));
  }

  renderWorldMapArtwork(points) {
    const routeMarkup = this.mapRouteEdges().map((edge, index) => {
      const from = points.get(edge.from);
      const to = points.get(edge.to);
      if (!from || !to) return "";
      const dx = to.svgX - from.svgX;
      const dy = to.svgY - from.svgY;
      const length = Math.max(1, Math.hypot(dx, dy));
      const bend = (index % 2 === 0 ? 1 : -1) * Math.min(18, length * .055);
      const controlX = (from.svgX + to.svgX) / 2 - dy / length * bend;
      const controlY = (from.svgY + to.svgY) / 2 + dx / length * bend;
      const path = `M ${from.svgX.toFixed(1)} ${from.svgY.toFixed(1)} Q ${controlX.toFixed(1)} ${controlY.toFixed(1)} ${to.svgX.toFixed(1)} ${to.svgY.toFixed(1)}`;
      return `<path class="world-route__shadow" d="${path}"></path><path class="world-route world-route--${edge.kind}" d="${path}" data-route="${escapeHtml(edge.key)}"><title>${escapeHtml(edge.label)}</title></path>`;
    }).join("");

    return `<svg class="world-map-art" viewBox="0 0 ${MAP_VIEWBOX.width} ${MAP_VIEWBOX.height}" preserveAspectRatio="none" aria-hidden="true" focusable="false">
      <defs>
        <pattern id="map-water-ripples" width="48" height="28" patternUnits="userSpaceOnUse">
          <path d="M4 14h18m8 7h12" class="map-art__ripple"></path>
        </pattern>
        <pattern id="map-land-speckles" width="32" height="32" patternUnits="userSpaceOnUse">
          <rect x="7" y="8" width="3" height="3" class="map-art__speck"></rect>
          <rect x="24" y="23" width="2" height="2" class="map-art__speck"></rect>
        </pattern>
      </defs>
      <rect width="960" height="540" class="map-art__water"></rect>
      <rect width="960" height="540" fill="url(#map-water-ripples)" opacity=".55"></rect>
      <path class="map-art__land-shadow" d="M66 124L92 90l88-30 130 9 75 35 96-13 75-56 118-9 104 35 52 73 79 42 30 84-17 82-79 55-69 65-131 27-121-17-99 25-116-4-99-42-93-22-46-71 13-77-29-75z"></path>
      <path class="map-art__land" d="M58 112L91 78l88-27 129 10 78 34 94-12 72-53 119-8 103 34 49 70 82 42 27 82-17 78-81 52-64 63-130 25-120-17-100 24-112-5-98-39-94-22-42-67 13-76-31-72z"></path>
      <path class="map-art__coast" d="M58 112L91 78l88-27 129 10 78 34 94-12 72-53 119-8 103 34 49 70 82 42 27 82-17 78-81 52-64 63-130 25-120-17-100 24-112-5-98-39-94-22-42-67 13-76-31-72z"></path>
      <path class="map-art__river-shadow" d="M695 42c-22 65-91 88-96 145-5 54 48 74 8 119-45 51-150 18-205 67-32 28-52 61-85 96"></path>
      <path class="map-art__river" d="M695 42c-22 65-91 88-96 145-5 54 48 74 8 119-45 51-150 18-205 67-32 28-52 61-85 96"></path>

      <g class="map-art__mansion" transform="translate(132 55)">
        <path d="M4 45h222v91H4z" class="map-art__garden"></path>
        <path d="M10 54h60v12H10zm148 0h60v12h-60zM10 112h72v12H10zm136 0h72v12h-72z" class="map-art__hedge"></path>
        <ellipse cx="38" cy="91" rx="25" ry="12" class="map-art__pond"></ellipse>
        <path d="M90 40h49v80H90zM72 78h86v12H72z" class="map-art__garden-path"></path>
      </g>
      <g class="map-art__snow" transform="translate(555 17)">
        <path d="M0 142L69 23l31 50 47-70 91 139z" class="map-art__mountain-back"></path>
        <path d="M45 142L112 40l32 47 29-48 65 103z" class="map-art__mountain"></path>
        <path d="M69 23l31 50-22-8-13 18-10-21zm78-20l35 55-21-12-16 18-14-21z" class="map-art__snowcap"></path>
        <path d="M18 134h203" class="map-art__ice-line"></path>
      </g>
      <g class="map-art__capital" transform="translate(355 171)">
        <path d="M12 31h221v142H12z" class="map-art__capital-ground"></path>
        <path d="M12 82h221M112 31v142" class="map-art__capital-road"></path>
        <path d="M2 44h242v9H2zm0 110h242v9H2z" class="map-art__capital-wall"></path>
        <path d="M10 121h225" class="map-art__capital-canal"></path>
      </g>
      <g class="map-art__farm" transform="translate(68 298)">
        <path d="M3 10h275v159H3z" class="map-art__farm-ground"></path>
        <path d="M16 23h103v54H16z" class="map-art__field map-art__field--wheat"></path>
        <path d="M151 23h108v54H151z" class="map-art__field map-art__field--green"></path>
        <path d="M16 101h103v50H16z" class="map-art__field map-art__field--earth"></path>
        <path d="M151 101h108v50H151z" class="map-art__field map-art__field--gold"></path>
        <path d="M134 8v153M4 88h273" class="map-art__farm-road"></path>
      </g>
      <g class="map-art__desert" transform="translate(606 310)">
        <path d="M0 51q54-68 110-3 55-71 142 6v111H0z" class="map-art__sand"></path>
        <path d="M14 93q38-28 81 0m71 24q34-29 73 0" class="map-art__dune"></path>
        <ellipse cx="79" cy="132" rx="47" ry="19" class="map-art__oasis"></ellipse>
        <path d="M180 57h37v67h-37zm-12 13h61" class="map-art__ruin"></path>
      </g>

      <g class="world-route-layer">${routeMarkup}</g>
      <rect width="960" height="540" fill="url(#map-land-speckles)" opacity=".3"></rect>
      <g class="map-art__compass" transform="translate(876 68)">
        <path d="M0-31L8-8 31 0 8 8 0 31-8 8-31 0-8-8z"></path>
        <path d="M0-23L5-5 0 0-5-5z" class="map-art__compass-north"></path>
        <text x="0" y="-38">N</text>
      </g>
    </svg>
    <div class="map-route-key" aria-label="地图线路图例">
      <span><i class="route-swatch route-swatch--road"></i>步行</span>
      <span><i class="route-swatch route-swatch--carriage"></i>马车</span>
      <span><i class="route-swatch route-swatch--lift"></i>缆车</span>
      <span><i class="route-swatch route-swatch--caravan"></i>商队</span>
      <span><i class="route-swatch route-swatch--trail"></i>古道</span>
    </div>`;
  }

  mapRegionIcon(regionId) {
    if (regionId === "capital") return `<svg viewBox="0 0 96 76" aria-hidden="true">
      <path class="map-icon__shadow" d="M7 62h82v8H7z"></path><path class="map-icon__wall" d="M10 31h76v34H10z"></path>
      <path class="map-icon__roof" d="M7 31L20 14l13 17zm56 0l13-17 13 17zM29 28L48 7l19 21z"></path>
      <path class="map-icon__tower" d="M12 29h17v34H12zm55 0h17v34H67zM33 25h30v38H33z"></path>
      <path class="map-icon__door" d="M42 48h12v15H42z"></path><path class="map-icon__water" d="M4 67h88v5H4z"></path>
    </svg>`;
    if (regionId === "farm") return `<svg viewBox="0 0 96 76" aria-hidden="true">
      <path class="map-icon__shadow" d="M4 64h88v7H4z"></path><path class="map-icon__field" d="M4 41h88v25H4z"></path>
      <path class="map-icon__furrow" d="M7 48h84M7 56h84M7 64h84"></path><path class="map-icon__barn" d="M13 31h31v31H13z"></path>
      <path class="map-icon__roof" d="M8 32l20-17 21 17z"></path><path class="map-icon__door" d="M22 46h13v16H22z"></path>
      <path class="map-icon__mill" d="M67 25v39M53 38h29M58 18l18 39M78 18L57 57"></path><circle class="map-icon__hub" cx="67" cy="38" r="4"></circle>
    </svg>`;
    if (regionId === "mansion") return `<svg viewBox="0 0 96 76" aria-hidden="true">
      <path class="map-icon__shadow" d="M5 64h86v7H5z"></path><path class="map-icon__hedge" d="M3 52h21v14H3zm69 0h21v14H72z"></path>
      <path class="map-icon__wall" d="M20 28h57v37H20z"></path><path class="map-icon__roof" d="M14 30L48 8l35 22z"></path>
      <path class="map-icon__window" d="M28 36h10v11H28zm30 0h10v11H58z"></path><path class="map-icon__door" d="M43 46h12v19H43z"></path>
      <ellipse class="map-icon__water" cx="13" cy="66" rx="11" ry="4"></ellipse>
    </svg>`;
    if (regionId === "snow") return `<svg viewBox="0 0 96 76" aria-hidden="true">
      <path class="map-icon__shadow" d="M4 65h88v6H4z"></path><path class="map-icon__mountain-back" d="M3 62L31 17l20 45z"></path>
      <path class="map-icon__mountain" d="M26 64L59 7l34 57z"></path><path class="map-icon__snow" d="M31 17l8 13-9-3-7 7zm28-10l13 23-12-6-9 10-6-4z"></path>
      <path class="map-icon__cable" d="M6 22l82 20"></path><path class="map-icon__lift" d="M21 25h14v10H21zm43 11h14v10H64z"></path>
    </svg>`;
    if (regionId === "desert") return `<svg viewBox="0 0 96 76" aria-hidden="true">
      <path class="map-icon__shadow" d="M3 65h90v7H3z"></path><path class="map-icon__sand" d="M3 49q19-23 42 0 25-25 48 0v18H3z"></path>
      <ellipse class="map-icon__water" cx="31" cy="59" rx="20" ry="7"></ellipse><path class="map-icon__palm" d="M27 55l7-32m0 2l-15-5m15 5l13-9m-13 9L23 12m11 13l17 4"></path>
      <path class="map-icon__ruin" d="M61 24h23v40H61zM57 24h31v7H57zM66 31v33m13-33v33"></path>
    </svg>`;
    return `<svg viewBox="0 0 96 76" aria-hidden="true"><path class="map-icon__wall" d="M15 20h66v45H15z"></path></svg>`;
  }

  showMap() {
    if (!this.state || this.transitionLocked) return;
    const observer = this.state.mode === "observer";
    const map = this.elements.world_map;
    const points = new Map(this.content.regions.map((region, index) => [region.id, this.mapPoint(region, index)]));
    map.innerHTML = this.renderWorldMapArtwork(points);
    this.content.regions.forEach((region, index) => {
      const point = points.get(region.id) || this.mapPoint(region, index);
      const current = region.id === this.state.regionId;
      const currentPlaceId = this.state.placeId || this.state.regionId;
      const currentInterior = current && currentPlaceId !== this.state.regionId;
      const entry = document.createElement(observer ? "button" : "article");
      entry.className = `map-region map-region--${region.id}${current ? " current" : ""}${observer ? "" : " read-only"}${point.y > 58 ? " map-region--south" : ""}`;
      entry.style.left = `${point.x}%`;
      entry.style.top = `${point.y}%`;
      entry.style.setProperty("--region-color", region.mapColor || region.palette?.accent || "#66596a");
      if (current) entry.setAttribute("aria-current", "location");
      if (observer) {
        entry.type = "button";
        entry.disabled = current && !currentInterior;
      } else {
        entry.tabIndex = 0;
        entry.setAttribute("role", "group");
      }
      const population = Object.values(this.state.npcs || {}).filter((npcState) => npcState?.regionId === region.id).length;
      const currentLocation = current ? this.describeLocation(this.state.regionId, this.state.placeId) : null;
      const routeHint = this.describeMapRoute(this.state.regionId, region.id);
      const stateLabel = observer
        ? current
          ? currentInterior
            ? `正在观察${currentLocation?.placeName || "室内"}；点击返回地区室外`
            : "当前观察镜头"
          : "点击切换观察镜头"
        : current
          ? `当前所在${currentLocation?.placeName ? `：${currentLocation.placeName}` : ""}`
          : routeHint;
      const subtitle = region.subtitle || region.description || "";
      entry.setAttribute("aria-label", `${region.name}，${subtitle}，${population} 位居民，${stateLabel}`);
      entry.innerHTML = `<span class="map-region__icon">${this.mapRegionIcon(region.id)}</span>
        <span class="map-region__label"><strong>${escapeHtml(region.name)}</strong><span>${escapeHtml(subtitle)}</span></span>
        <span class="map-region__population" aria-hidden="true">${population}</span>
        <small class="map-region__detail">${population} 位居民<br>${escapeHtml(stateLabel)}</small>`;
      if (observer && (!current || currentInterior)) entry.addEventListener("click", () => this.callbacks.onTravel?.(region.id));
      map.appendChild(entry);
    });
    this.elements.map_note.textContent = observer
      ? "点击地图地标可切换观察镜头；在室内时点击当前地区可返回室外。切换不消耗游戏时间，也不会被居民察觉。"
      : "M 只用于查看路线，不能直接传送。将指针移到地点上或用 Tab 聚焦，即可查看从当前位置出发的交通方式与时间。";
    this.openModal("map-modal");
  }

  showJournal() {
    if (this.transitionLocked) return;
    if (this.state) this.renderJournal(this.state);
    this.openModal("journal-modal");
  }

  showLocation(region, place = null) {
    if (!region) return;
    const resolvedPlace = typeof place === "string" ? this.findPlace(place) : place;
    const location = this.describeLocation(region.id, resolvedPlace?.id);
    this.elements.region_name.textContent = location.title;
    this.elements.region_subtitle.textContent = resolvedPlace?.subtitle || resolvedPlace?.description || region.subtitle || region.description || "";
    const banner = this.elements.region_banner;
    banner.classList.remove("hidden");
    banner.style.animation = "none";
    requestAnimationFrame(() => { banner.style.animation = ""; });
    window.setTimeout(() => banner.classList.add("hidden"), 2900);
  }

  showRegion(region) {
    this.showLocation(region, null);
  }

  setInteraction(interaction = null) {
    if (this.state?.mode === "observer") {
      this.elements.interaction_hint.classList.add("hidden");
      return;
    }
    const visible = Boolean(interaction);
    this.elements.interaction_hint.classList.toggle("hidden", !visible);
    if (!interaction) {
      this.elements.interaction_hint.removeAttribute("data-kind");
      return;
    }
    const target = interaction.name || interaction.label || interaction.profile?.name || "这里";
    const fallback = {
      npc: `与 ${target} 交谈`,
      landmark: `调查 ${target}`,
      door: `进入 ${target}`,
      portal: `前往 ${target}`,
      transport: `乘坐 ${target}`,
    }[interaction.kind] || `查看 ${target}`;
    this.elements.interaction_text.textContent = interaction.prompt || fallback;
    this.elements.interaction_hint.dataset.kind = interaction.kind || "interaction";
  }

  openConversation(npc, npcState, greeting, storyTopics = []) {
    this.currentNpc = { profile: npc, state: npcState };
    this.elements.conversation_portrait.style.setProperty("--npc-color", npc.color || "#8b708e");
    this.elements.conversation_portrait.style.setProperty("--hair-color", npc.hairColor || "#4d3632");
    this.elements.conversation_portrait.style.setProperty("--skin-color", npc.skinColor || PORTRAIT_SKINS[npc.id] || "#efbf87");
    this.elements.conversation_portrait.dataset.portrait = npc.id;
    this.elements.conversation_role.textContent = `${npc.role} · ${npc.traits?.slice(0, 2).join(" / ") || "旅人"}`;
    this.elements.conversation_name.textContent = npc.name;
    this.elements.conversation_mood.textContent = `${npcState.mood} · 关系 ${Math.round(npcState.relationship)}`;
    this.elements.conversation_history.innerHTML = "";
    this.addSpeech(greeting || npc.intro || `“你是刚来的旅行者吧？我是${npc.name}。”`, "npc");
    const intents = [
      ["greet", "聊聊近况"], ["help", "我能帮什么？"], ["rumor", "询问传闻"], ["secret", "追问秘密"], ["challenge", "追问他的理由"],
    ];
    const topics = Array.isArray(storyTopics)
      ? storyTopics.filter((topic) => topic?.label && topic?.message)
      : [];
    this.elements.conversation_actions.innerHTML = [
      ...intents.map(([id, label]) => `<button type="button" data-intent="${id}">${label}</button>`),
      ...topics.map((topic, index) => `<button type="button" data-story-topic="${index}">${escapeHtml(topic.label)}</button>`),
    ].join("");
    this.elements.conversation_actions.querySelectorAll("[data-intent]").forEach((button) => {
      button.addEventListener("click", () => this.callbacks.onTalk?.(button.textContent, button.dataset.intent));
    });
    this.elements.conversation_actions.querySelectorAll("[data-story-topic]").forEach((button) => {
      button.addEventListener("click", () => {
        const topic = topics[Number(button.dataset.storyTopic)];
        if (topic) this.callbacks.onTalk?.(topic.message, topic.intent || "custom");
      });
    });
    this.elements.conversation_provider.textContent = "他会根据性格与最近发生的事回应。";
    this.openModal("conversation-modal");
    window.setTimeout(() => this.elements.conversation_input.focus(), 80);
  }

  showNpcObservation(npc, npcState) {
    const location = this.describeLocation(npcState.regionId, npcState.placeId);
    const current = this.sameLocation(npcState, this.state);
    this.elements.observer_portrait.style.setProperty("--npc-color", npc.color || "#8b708e");
    this.elements.observer_portrait.style.setProperty("--hair-color", npc.hairColor || "#4d3632");
    this.elements.observer_portrait.style.setProperty("--skin-color", npc.skinColor || PORTRAIT_SKINS[npc.id] || "#efbf87");
    this.elements.observer_portrait.dataset.portrait = npc.id;
    this.elements.observer_role.textContent = `${npc.role} · ${npc.traits?.slice(0, 3).join(" / ") || "居民"}`;
    this.elements.observer_name.textContent = npc.name;
    this.elements.observer_status.textContent = `${current ? "◉ 当前镜头 · " : "◎ 其他地点 · "}${location.title} · ${npcState.activity} · ${npcState.mood}`;
    this.elements.observer_goal.textContent = npc.goal || "平安度过坠星之前的日子。";
    this.elements.observer_reflection.textContent = npcState.reflection || "尚未形成明确反思。";
    const memories = [...(npcState.coreMemories || []), ...(npcState.memories || [])]
      .filter((memory, index, list) => list.findIndex((item) => (item.text || item) === (memory.text || memory)) === index)
      .slice(0, 16);
    this.elements.observer_memories.innerHTML = memories.length
      ? memories.map((memory) => `<article class="observer-memory"><time>${escapeHtml(formatStamp(memory.day || this.state.day, memory.minute || 0))} · ${escapeHtml(memory.type || "记忆")}</time><p>${escapeHtml(memory.text || memory)}</p></article>`).join("")
      : '<div class="nearby-card empty">还没有形成近期记忆。</div>';
    const knowledge = Array.isArray(npc.knowledge) ? npc.knowledge : Object.values(npc.knowledge || {});
    this.elements.observer_knowledge.innerHTML = knowledge.map((fact) => `<span>${escapeHtml(typeof fact === "string" ? fact : fact?.text || JSON.stringify(fact))}</span>`).join("") || "<span>没有公开知识</span>";
    this.openModal("observer-modal");
  }

  addSpeech(text, speaker = "npc") {
    const bubble = document.createElement("div");
    bubble.className = `speech ${speaker}`;
    bubble.textContent = text;
    this.elements.conversation_history.appendChild(bubble);
    this.elements.conversation_history.scrollTop = this.elements.conversation_history.scrollHeight;
    return bubble;
  }

  setConversationBusy(busy) {
    this.elements.conversation_input.disabled = busy;
    this.elements.conversation_form.querySelector("button").disabled = busy;
    this.elements.conversation_actions.querySelectorAll("button").forEach((button) => { button.disabled = busy; });
    const existing = this.elements.conversation_history.querySelector("[data-thinking]");
    if (busy && !existing) {
      const bubble = this.addSpeech("正在从记忆中组织想法……", "system");
      bubble.dataset.thinking = "true";
    } else if (!busy) existing?.remove();
  }

  setConversationProvider(provider, detail = "") {
    const remote = provider && !["local", "local-rules", "rules"].includes(provider);
    this.elements.conversation_provider.textContent = remote ? `深度思考已启用${detail ? ` · ${detail}` : ""}` : `本地心智${detail ? ` · ${detail}` : ""}`;
  }

  showEnding(ending, state) {
    this.elements.ending_glyph.textContent = ending.glyph || "✦";
    this.elements.ending_title.textContent = ending.title;
    this.elements.ending_subtitle.textContent = ending.subtitle || "一条世界线就此被记住。";
    const epilogue = Array.isArray(ending.epilogue) ? ending.epilogue.join("\n\n") : ending.epilogue;
    this.elements.ending_epilogue.innerHTML = escapeHtml(epilogue || "").replaceAll("\n", "<br>");
    const topMetrics = Object.entries(state.metrics).sort((a, b) => b[1] - a[1]).slice(0, 3);
    const observerSummary = [
      `<span>社会进程结算 ${state.statistics.observedChoices || 0} 次</span>`,
      `<span>居民日常行动 ${state.statistics.npcActions || 0} 次</span>`,
      `<span>观察切换 ${state.statistics.observerSwitches || 0} 次</span>`,
    ];
    const playerSummary = [
      `<span>交谈 ${state.statistics.conversations} 次</span>`,
      `<span>影响 ${state.statistics.influences || 0} 次</span>`,
    ];
    this.elements.ending_summary.innerHTML = [
      ...topMetrics.map(([key, value]) => `<span>${METRIC_META[key]?.label || key} ${Math.round(value)}</span>`),
      ...(state.mode === "observer" ? observerSummary : playerSummary),
    ].join("");
    this.openModal("ending-modal");
  }

  showEndingGallery() {
    const unlocked = this.callbacks.getUnlockedEndings?.() || [];
    this.elements.ending_gallery.innerHTML = (this.content.endings || []).map((ending) => {
      const found = unlocked.includes(ending.id);
      return `<article class="ending-card ${found ? "" : "locked"}"><span class="gallery-glyph">${found ? escapeHtml(ending.glyph || "✦") : "?"}</span><h3>${found ? escapeHtml(ending.title) : "尚未见证"}</h3><p>${found ? escapeHtml(ending.subtitle || ending.hint || "这条世界线已被记录。") : escapeHtml(ending.hint || "尝试让世界走向不同的平衡。")}</p></article>`;
    }).join("");
    this.openModal("chronicles-modal");
  }

  updateAiStatus(status) {
    const configured = Boolean(status?.configured);
    this.elements.ai_status_dot.className = `status-dot ${configured ? "online" : "offline"}`;
    this.elements.ai_status_label.textContent = configured ? "深度思考可以使用" : "本地心智正在运行";
    this.elements.ai_status_detail.textContent = configured ? "对话与每日计划会更加细致" : "居民会按照性格、记忆与局势生活";
    this.elements.llm_toggle.disabled = !configured;
    if (!configured) this.elements.llm_toggle.checked = false;
  }

  setLlmEnabled(enabled) { this.elements.llm_toggle.checked = Boolean(enabled) && !this.elements.llm_toggle.disabled; }

  setSoundEnabled(enabled) {
    this.elements.sound_button.textContent = enabled ? "♪" : "×";
    this.elements.sound_button.title = enabled ? "关闭声音" : "开启声音";
  }

  flashTravel(callback) {
    this.elements.fade_layer.classList.add("active");
    window.setTimeout(() => {
      callback?.();
      window.setTimeout(() => this.elements.fade_layer.classList.remove("active"), 80);
    }, 260);
  }

  toast(message, type = "info") {
    const toast = document.createElement("div");
    toast.className = "toast";
    toast.style.setProperty("--toast-color", type === "error" ? "#d66d6d" : type === "success" ? "#7fc79a" : "#e0ae60");
    toast.textContent = message;
    this.elements.toast_stack.appendChild(toast);
    this.elements.aria_status.textContent = message;
    window.setTimeout(() => toast.remove(), 4300);
  }

  openModal(id) {
    document.getElementById(id)?.classList.remove("hidden");
    this.callbacks.onModalChange?.(true, id);
  }

  closeModal(id, force = false) {
    document.getElementById(id)?.classList.add("hidden");
    const anyOpen = [...document.querySelectorAll(".modal-layer")].some((modal) => !modal.classList.contains("hidden"));
    this.callbacks.onModalChange?.(anyOpen, id);
  }

  closeAllModals(force = false) {
    document.querySelectorAll(".modal-layer").forEach((modal) => {
      modal.classList.add("hidden");
    });
    this.callbacks.onModalChange?.(false, "all");
  }

  closeTopModal() {
    const open = [...document.querySelectorAll(".modal-layer:not(.hidden)")].pop();
    if (open) this.closeModal(open.id);
  }
}
