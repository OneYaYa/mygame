const SUPPORTED_INTENTS = new Set([
  "greet",
  "help",
  "rumor",
  "secret",
  "challenge",
  "story",
  "custom",
]);

const SECRET_FIELD = /(^|[_-])(secret|secrets|hidden|private)([_-]|$)|秘密|隐情|机密/i;
const CREDENTIAL_FIELD = /api.?key|access.?token|authorization|credential|password/i;

const METRIC_LABELS = {
  stability: "秩序",
  order: "秩序",
  prosperity: "繁荣",
  economy: "民生",
  wealth: "财富",
  food: "粮食",
  grain: "粮食",
  water: "水源",
  morale: "士气",
  hope: "希望",
  safety: "安全",
  security: "安全",
  health: "健康",
  ecology: "生态",
  environment: "生态",
  temperature: "温度",
  magic: "魔力",
  trust: "信任",
  reputation: "声望",
  王城秩序: "王城秩序",
  农田收成: "农田收成",
  雪山温度: "雪山温度",
  沙漠水源: "沙漠水源",
};

const FLAG_LABELS = {
  festival: "庆典已经开始",
  festival_started: "庆典已经开始",
  harvest_festival: "丰收祭正在筹备",
  drought: "旱情还没有缓解",
  famine: "粮荒正在蔓延",
  blizzard: "暴风雪正在逼近",
  snowstorm: "暴风雪正在逼近",
  sandstorm: "沙暴封住了商路",
  plague: "疫病正在扩散",
  coup: "王城里的权力斗争已经公开化",
  rebellion: "反叛的传闻正在各地流传",
  caravan: "远方商队刚刚抵达",
  war: "战争的阴影已经压到边境",
  eclipse: "异常的日蚀正在改变魔力流向",
};

function clamp(value, min = 0, max = 100) {
  return Math.min(max, Math.max(min, value));
}

function text(value, fallback = "", maxLength = 500) {
  if (value === null || value === undefined) return fallback;
  if (typeof value === "string") return value.trim().slice(0, maxLength) || fallback;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return fallback;
}

function hashString(value) {
  let hash = 2166136261;
  const source = String(value ?? "");
  for (let index = 0; index < source.length; index += 1) {
    hash ^= source.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function choose(values, seed) {
  if (!values.length) return "";
  return values[hashString(seed) % values.length];
}

function normalizeScore(value, fallback = 35) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  if (number >= 0 && number <= 1) return Math.round(number * 100);
  return Math.round(clamp(number));
}

function listOfText(value) {
  if (Array.isArray(value)) {
    return value
      .map((item) => {
        if (typeof item === "string") return item.trim();
        if (item && typeof item === "object") {
          return text(item.text ?? item.name ?? item.description ?? item.summary);
        }
        return text(item);
      })
      .filter(Boolean);
  }
  if (typeof value === "string") {
    return value.split(/[,，、;；|]/).map((item) => item.trim()).filter(Boolean);
  }
  return [];
}

function memoryText(memory) {
  if (typeof memory === "string") return memory.trim();
  if (!memory || typeof memory !== "object") return "";
  return text(
    memory.text
      ?? memory.description
      ?? memory.memory
      ?? memory.content
      ?? memory.summary
      ?? memory.reply,
    "",
    600,
  );
}

function recentMemories(npc, npcState, limit = 8) {
  const source = [
    ...(Array.isArray(npcState?.coreMemories) ? npcState.coreMemories : []),
    ...(Array.isArray(npcState?.memories)
      ? npcState.memories
      : Array.isArray(npc?.memories)
        ? npc.memories
        : []),
  ];
  // The game stores newest memories first. Keeping that convention here also
  // ensures a short browser payload contains the most relevant recent context.
  return [...new Set(source.map(memoryText).filter(Boolean))].slice(0, limit);
}

function relationshipScore(npc, npcState) {
  const playerRelationship = npcState?.relationships?.player
    ?? npcState?.relationships?.playerId
    ?? npcState?.relationship
    ?? npcState?.relation
    ?? npcState?.trust
    ?? npcState?.affinity
    ?? npc?.relationship
    ?? npc?.trust;

  if (playerRelationship && typeof playerRelationship === "object") {
    return normalizeScore(
      playerRelationship.trust
        ?? playerRelationship.score
        ?? playerRelationship.affinity
        ?? playerRelationship.friendship
        ?? playerRelationship.value,
    );
  }
  return normalizeScore(playerRelationship);
}

function metricLabel(key) {
  const normalized = String(key ?? "").toLowerCase();
  return METRIC_LABELS[key] ?? METRIC_LABELS[normalized] ?? String(key).replace(/[_-]+/g, " ");
}

function lowestWorldMetric(worldState) {
  const sources = [
    worldState?.metrics,
    worldState?.worldMetrics,
    worldState?.indicators,
    worldState?.stats,
    worldState?.resources,
  ];
  const candidates = [];

  const collect = (object, prefix = "") => {
    if (!object || typeof object !== "object" || Array.isArray(object)) return;
    Object.entries(object).forEach(([key, value]) => {
      if (typeof value === "number" && Number.isFinite(value)) {
        candidates.push({ key: prefix ? `${prefix}.${key}` : key, rawKey: key, value });
      } else if (value && typeof value === "object" && !Array.isArray(value)) {
        Object.entries(value).forEach(([nestedKey, nestedValue]) => {
          if (typeof nestedValue === "number" && Number.isFinite(nestedValue)) {
            candidates.push({
              key: `${key}.${nestedKey}`,
              rawKey: nestedKey,
              value: nestedValue,
            });
          }
        });
      }
    });
  };

  sources.forEach((source) => collect(source));
  if (!candidates.length) return null;
  candidates.sort((left, right) => left.value - right.value || left.key.localeCompare(right.key));
  const lowest = candidates[0];
  return { ...lowest, label: metricLabel(lowest.rawKey) };
}

function describeMetric(metric) {
  if (!metric) return "";
  const displayValue = metric.value >= 0 && metric.value <= 1
    ? `${Math.round(metric.value * 100)}%`
    : String(Math.round(metric.value));
  return `${metric.label}已经降到${displayValue}`;
}

function collectEventFlags(worldState) {
  const found = [];
  const add = (value) => {
    const cleaned = text(value, "", 100);
    if (cleaned && !found.includes(cleaned)) found.push(cleaned);
  };
  const visit = (value, depth = 0) => {
    if (depth > 2 || value === null || value === undefined) return;
    if (typeof value === "string") {
      add(value);
      return;
    }
    if (Array.isArray(value)) {
      value.forEach((item) => visit(item, depth + 1));
      return;
    }
    if (typeof value !== "object") return;
    if (value.active === false || value.resolved === true) return;
    const label = value.label ?? value.title ?? value.name ?? value.id ?? value.key;
    if (label) add(label);
    Object.entries(value).forEach(([key, item]) => {
      if (["label", "title", "name", "id", "key", "active", "resolved"].includes(key)) return;
      if (item === true || (typeof item === "number" && item > 0)) add(key);
      else if (Array.isArray(item) || (item && typeof item === "object")) visit(item, depth + 1);
    });
  };

  [
    worldState?.flags,
    worldState?.eventFlags,
    worldState?.storyFlags,
    worldState?.currentEvent,
    worldState?.activeEvent,
    worldState?.activeEvents,
  ].forEach((source) => visit(source));
  return found.slice(0, 8);
}

function describeFlag(flag) {
  if (!flag) return "";
  const normalized = String(flag).trim();
  const mapped = FLAG_LABELS[normalized] ?? FLAG_LABELS[normalized.toLowerCase()];
  if (mapped) return mapped;
  if (/[一-鿿]/.test(normalized)) return normalized.replace(/[。！!]+$/, "");
  return normalized.replace(/[_-]+/g, " ");
}

function collectFacts(value, options = {}, path = [], output = []) {
  if (output.length >= (options.limit ?? 24) || value === null || value === undefined) return output;
  const key = path[path.length - 1] ?? "";
  if (CREDENTIAL_FIELD.test(key)) return output;
  const pathIsSecret = path.some((part) => SECRET_FIELD.test(part));
  if (pathIsSecret && !options.includeSecrets) return output;

  if (typeof value === "string") {
    const cleaned = value.trim();
    if (cleaned) output.push(cleaned.slice(0, 500));
    return output;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    if (key && !/trust|threshold/i.test(key)) output.push(`${metricLabel(key)}：${value}`);
    return output;
  }
  if (Array.isArray(value)) {
    value.forEach((item) => collectFacts(item, options, path, output));
    return output;
  }
  if (typeof value !== "object") return output;
  if ((value.secret === true || value.private === true) && !options.includeSecrets) return output;
  Object.entries(value).forEach(([childKey, childValue]) => {
    collectFacts(childValue, options, [...path, childKey], output);
  });
  return output;
}

function collectSecrets(npc, npcState) {
  const secrets = [];
  const visit = (value, secretBranch = false, depth = 0) => {
    if (depth > 4 || value === null || value === undefined || secrets.length >= 12) return;
    if (typeof value === "string") {
      if (secretBranch && value.trim()) secrets.push(value.trim().slice(0, 500));
      return;
    }
    if (Array.isArray(value)) {
      value.forEach((item) => visit(item, secretBranch, depth + 1));
      return;
    }
    if (typeof value !== "object") return;
    const markedSecret = secretBranch || value.secret === true || value.private === true;
    Object.entries(value).forEach(([key, item]) => {
      if (/secretTrust|secret_threshold/i.test(key)) return;
      visit(item, markedSecret || SECRET_FIELD.test(key), depth + 1);
    });
  };
  visit({ secret: npc?.secret, secrets: npc?.secrets }, true);
  visit(npc?.knowledge, false);
  visit({ secret: npcState?.secret, secrets: npcState?.secrets }, true);
  return [...new Set(secrets)];
}

function messageTokens(message) {
  const normalized = String(message ?? "").toLowerCase();
  const tokens = normalized.match(/[a-z0-9]{2,}|[一-鿿]{2,}/g) ?? [];
  const chinese = normalized.replace(/[^一-鿿]/g, "");
  for (let index = 0; index < chinese.length - 1; index += 1) {
    tokens.push(chinese.slice(index, index + 2));
  }
  return [...new Set(tokens)].filter((token) => !["什么", "怎么", "可以", "你们", "我们", "这个", "那个"].includes(token));
}

function relevantFact(facts, message, seed) {
  if (!facts.length) return "";
  const tokens = messageTokens(message);
  const ranked = facts.map((fact, index) => ({
    fact,
    index,
    score: tokens.reduce((score, token) => score + (fact.toLowerCase().includes(token) ? token.length : 0), 0),
  }));
  ranked.sort((left, right) => right.score - left.score || left.index - right.index);
  if (ranked[0].score > 0) return ranked[0].fact;
  return choose(facts, seed);
}

function normalizeIntent(intent, playerMessage) {
  const explicit = String(intent ?? "").trim().toLowerCase();
  if (SUPPORTED_INTENTS.has(explicit)) return explicit;
  const message = String(playerMessage ?? "");
  if (/秘密|隐情|真相|不能说|瞒着|secret/i.test(message)) return "secret";
  if (/挑战|决斗|比试|打一场|敢不敢|challenge/i.test(message)) return "challenge";
  if (/传闻|听说|消息|八卦|rumou?r/i.test(message)) return "rumor";
  if (/帮忙|帮我|需要帮助|搭把手|救救|help/i.test(message)) return "help";
  if (/^(你好|您好|嗨|早安|早上好|晚上好|在吗|hello|hi|hey)[！!。,.， ]*$/i.test(message.trim())) return "greet";
  return "custom";
}

function deriveTone(traits) {
  const joined = traits.join(" ");
  if (/多疑|谨慎|冷淡|寡言|戒备|阴沉/.test(joined)) return "guarded";
  if (/热情|友善|温柔|开朗|好客|乐观/.test(joined)) return "warm";
  if (/骄傲|高傲|自信|强势|威严/.test(joined)) return "proud";
  if (/幽默|风趣|顽皮|狡黠/.test(joined)) return "playful";
  if (/冷静|理性|沉稳|耐心/.test(joined)) return "calm";
  return "plain";
}

function ensureSentence(value) {
  const cleaned = String(value ?? "").replace(/\s+/g, " ").trim();
  if (!cleaned) return "";
  return /[。！？!?]$/.test(cleaned) ? cleaned : `${cleaned}。`;
}

function compactReason(parts) {
  return [...new Set(parts.filter(Boolean))].join("；").slice(0, 500);
}

function safeTransport(value, options = {}, seen = new WeakSet(), depth = 0) {
  if (value === null || value === undefined) return null;
  if (["string", "number", "boolean"].includes(typeof value)) {
    return typeof value === "string" ? value.slice(0, 1000) : value;
  }
  if (typeof value !== "object" || depth > (options.maxDepth ?? 4)) return undefined;
  if (seen.has(value)) return undefined;
  seen.add(value);
  if (Array.isArray(value)) {
    return value
      .slice(0, options.maxArray ?? 30)
      .map((item) => safeTransport(item, options, seen, depth + 1))
      .filter((item) => item !== undefined);
  }
  const result = {};
  Object.entries(value).slice(0, options.maxKeys ?? 60).forEach(([key, item]) => {
    if (CREDENTIAL_FIELD.test(key)) return;
    if (!options.includeSecrets && SECRET_FIELD.test(key)) return;
    const cleaned = safeTransport(item, options, seen, depth + 1);
    if (cleaned !== undefined) result[key] = cleaned;
  });
  return result;
}

function publicNpcProfile(npc, npcState, context) {
  const includeSecrets = context.intent === "secret" && context.mayRevealSecret;
  const profile = {
    id: npc?.id,
    name: npc?.name,
    role: npc?.role ?? npc?.job ?? npc?.title,
    home: npc?.home ?? npc?.area ?? npc?.map,
    traits: npc?.traits ?? npc?.personality,
    goal: npc?.goal,
    knowledge: npc?.knowledge,
    allowed_actions: npc?.allowedActions,
    secretTrust: context.secretThreshold,
    relationship: context.relationship,
    conversation_intent: context.intent,
    may_reveal_secret: context.mayRevealSecret,
    current_state: {
      mood: npcState?.mood,
      status: npcState?.status,
      location: npcState?.location ?? npcState?.area,
      action: npcState?.action ?? npcState?.currentAction,
    },
  };
  if (includeSecrets) {
    profile.secret = npc?.secret ?? npc?.secrets ?? context.secret;
  }
  return safeTransport(profile, { includeSecrets });
}

function publicWorldState(worldState, context) {
  const snapshot = safeTransport(worldState ?? {}, { includeSecrets: false });
  return {
    ...(snapshot && typeof snapshot === "object" ? snapshot : {}),
    conversation_context: {
      intent: context.intent,
      relationship: context.relationship,
      lowest_metric: context.lowestMetric,
      active_flags: context.flags,
    },
  };
}

function timeoutSignal(timeoutMs) {
  if (typeof AbortController !== "function") return { signal: undefined, cancel: () => {} };
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  return { signal: controller.signal, cancel: () => clearTimeout(timer) };
}

/**
 * Browser-side NPC decision service.
 *
 * It never accepts or reads an API key. The browser only asks the same-origin
 * backend whether an LLM is configured and falls back to deterministic local
 * rules whenever that backend is disabled or unavailable.
 */
export class AIService {
  constructor(options = {}) {
    this.configUrl = options.configUrl ?? "/api/config";
    this.decisionUrl = options.decisionUrl ?? "/api/npc/decide";
    this.backendEnabled = options.backendEnabled ?? options.useBackend ?? true;
    this.timeoutMs = Math.max(500, Number(options.timeoutMs) || 8000);
    this.configCacheMs = Math.max(1000, Number(options.configCacheMs) || 30000);
    this.failureCooldownMs = Math.max(1000, Number(options.failureCooldownMs) || 15000);
    this.fetchImpl = options.fetchImpl
      ?? (typeof globalThis.fetch === "function" ? globalThis.fetch.bind(globalThis) : null);
    this._checkPromise = null;
    this._backendRetryAt = 0;
    this._status = {
      reachable: false,
      configured: false,
      provider: "local-rules",
      model: null,
      checkedAt: 0,
      error: this.backendEnabled ? null : "disabled",
    };
  }

  get backendStatus() {
    return { ...this._status };
  }

  setEnabled(enabled) {
    this.backendEnabled = Boolean(enabled);
    if (this.backendEnabled) this._status.checkedAt = 0;
    return this.backendEnabled;
  }

  async checkBackend(force = false) {
    if (!this.backendEnabled || !this.fetchImpl) {
      this._status = {
        reachable: false,
        configured: false,
        provider: "local-rules",
        model: null,
        checkedAt: Date.now(),
        error: this.backendEnabled ? "fetch_unavailable" : "disabled",
      };
      return this.backendStatus;
    }

    const now = Date.now();
    if (!force && this._status.checkedAt && now - this._status.checkedAt < this.configCacheMs) {
      return this.backendStatus;
    }
    if (this._checkPromise) return this._checkPromise;

    this._checkPromise = (async () => {
      const timeout = timeoutSignal(this.timeoutMs);
      try {
        const response = await this.fetchImpl(this.configUrl, {
          method: "GET",
          headers: { Accept: "application/json" },
          cache: "no-store",
          signal: timeout.signal,
        });
        if (!response.ok) throw new Error(`config_http_${response.status}`);
        const config = await response.json();
        const configured = Boolean(config?.llm?.configured);
        this._status = {
          reachable: true,
          configured,
          provider: text(config?.llm?.provider, configured ? "backend" : "local-rules", 80),
          model: text(config?.llm?.model, "", 120) || null,
          checkedAt: Date.now(),
          error: configured ? null : "llm_not_configured",
        };
      } catch (error) {
        this._status = {
          reachable: false,
          configured: false,
          provider: "local-rules",
          model: null,
          checkedAt: Date.now(),
          error: error?.name === "AbortError" ? "config_timeout" : "config_unavailable",
        };
      } finally {
        timeout.cancel();
        this._checkPromise = null;
      }
      return this.backendStatus;
    })();

    return this._checkPromise;
  }

  _buildContext(npc, npcState, worldState, playerMessage, intent) {
    const normalizedIntent = normalizeIntent(intent, playerMessage);
    const memories = recentMemories(npc, npcState);
    const relationship = relationshipScore(npc, npcState);
    const rawThreshold = npc?.secretTrust
      ?? npc?.knowledge?.secretTrust
      ?? npcState?.secretTrust
      ?? 65;
    const secretThreshold = normalizeScore(rawThreshold, 65);
    const secrets = collectSecrets(npc, npcState);
    return {
      intent: normalizedIntent,
      playerMessage: text(playerMessage, "", 2000),
      relationship,
      secretThreshold,
      mayRevealSecret: relationship >= secretThreshold,
      secret: secrets[0] ?? "",
      secrets,
      memories,
      lowestMetric: lowestWorldMetric(worldState),
      flags: collectEventFlags(worldState),
    };
  }

  _localBrain(npc, npcState, worldState, context) {
    const npcName = text(npc?.name, "这位旅人", 80);
    const traits = listOfText(npc?.traits ?? npc?.personality);
    const primaryTrait = traits[0] ?? "谨慎务实";
    const tone = deriveTone(traits);
    const goal = text(npc?.goal, "守住眼前的生活", 220);
    const facts = [
      ...collectFacts(worldState?.story_context, { includeSecrets: false }),
      ...collectFacts(npc?.knowledge, { includeSecrets: false }),
    ];
    const flag = context.flags[0] ?? "";
    const flagClause = describeFlag(flag);
    const metricClause = describeMetric(context.lowestMetric);
    const latestMemory = context.memories[0] ?? "";
    const seed = [
      npc?.id ?? npcName,
      context.intent,
      context.playerMessage,
      worldState?.day ?? worldState?.time ?? worldState?.minute ?? "",
      context.relationship,
      latestMemory,
    ].join("|");
    const fact = relevantFact(facts, context.playerMessage, seed);
    const anchor = flagClause || metricClause || fact || `我还在设法${goal}`;
    const playerRequestsHelp = /帮帮我|帮我|救我|请你|能不能帮|需要你|help me/i.test(context.playerMessage);

    let reply = "";
    let action = "continue_conversation";

    if (context.intent === "greet") {
      action = "greet_player";
      const variants = tone === "warm"
        ? [
          `你来得正好。${anchor}，我正想找个靠得住的人说说。`,
          `见到你总算有件让人安心的事。${anchor}，今天恐怕不会太平静。`,
          `先别急着赶路。${anchor}，坐下听我说两句吧。`,
        ]
        : tone === "guarded"
          ? [
            `脚步放轻些。${anchor}，这阵子多留一双眼睛总没坏处。`,
            `是你啊。${anchor}，有些话最好别在人多的地方谈。`,
            `先看看四周再说。${anchor}，我不想让旁人听见。`,
          ]
          : [
            `又见面了。${anchor}，你来得比我预想的早。`,
            `正好碰上你。${anchor}，我们得为下一步做打算。`,
            `今天的风向不太寻常。${anchor}，你也感觉到了吧。`,
          ];
      reply = choose(variants, seed);
    } else if (context.intent === "help") {
      if (playerRequestsHelp) {
        action = "offer_help";
        const direction = fact || flagClause || metricClause || goal;
        reply = choose([
          `可以，但我们得先把事情弄清楚。${direction}，从这里下手最稳妥。`,
          `我会帮你。眼下最有用的线索是：${direction}。别单独冒险。`,
          `跟紧我，先处理眼前这一件。${direction}，拖久了只会更麻烦。`,
        ], seed);
      } else {
        action = "request_player_help";
        const problem = flagClause || metricClause || `我的目标是${goal}`;
        reply = choose([
          `${problem}。你若愿意搭把手，我会把知道的都告诉你。`,
          `我确实需要帮忙：${problem}。这件事靠我一个人做不成。`,
          `先别急着答应。${problem}，一旦插手，你也会被卷进来。`,
        ], seed);
      }
    } else if (context.intent === "rumor") {
      action = "share_rumor";
      const rumor = fact || latestMemory || flagClause || metricClause || `有人正在阻挠我${goal}`;
      reply = choose([
        `我不敢说这一定是真的，不过最近有人反复提到：${rumor}。`,
        `酒馆里的人把声音压得很低，说的是同一件事——${rumor}。`,
        `传闻往往会添油加醋，但这一句值得记住：${rumor}。`,
        `你若只是想听热闹，我劝你算了；若想找线索，就留意这件事：${rumor}。`,
      ], seed);
    } else if (context.intent === "secret") {
      if (context.mayRevealSecret && context.secret) {
        action = "reveal_secret";
        reply = choose([
          `这话我只说一次：${context.secret}。出了这道门，别提是我告诉你的。`,
          `你已经证明自己值得信任。真正被藏起来的是——${context.secret}。`,
          `靠近些。${context.secret}。现在你明白我为什么一直犹豫了。`,
        ], seed);
      } else if (context.mayRevealSecret) {
        action = "admit_no_secret";
        reply = `我愿意相信你，可我手里没有能称作真相的东西。${fact ? `我能确定的只有：${fact}。` : "若有新消息，我会先找你。"}`;
      } else {
        action = "guard_secret";
        reply = choose([
          `有些话不是不能说，只是现在还不到时候。等我们彼此再多几分信任。`,
          `你问到了不该在大路上谈的事。我会记住这个问题，但今天不能回答。`,
          `我知道你想要真相，可信任不是一句保证就能换来的。先让我看看你的选择。`,
        ], seed);
      }
    } else if (context.intent === "story") {
      const allowed = Array.isArray(npc?.allowedActions) ? npc.allowedActions : [];
      const tokens = messageTokens(context.playerMessage);
      const ranked = allowed.filter((item) => String(item.id || "").startsWith("endorse:"))
        .map((item) => ({
          item,
          score: tokens.reduce((sum, token) => sum + (String(item.label || "").toLowerCase().includes(token) ? token.length : 0), 0),
        }))
        .sort((left, right) => right.score - left.score);
      const best = ranked[0];
      if (!best || best.score < 2) {
        action = allowed.find((item) => item.id === "continue_conversation")?.id || "continue_conversation";
        reply = choose([
          `我听得出你在意这件事，但还不明白你希望我们具体改变什么。再说清楚一点。`,
          `${fact || anchor}。你是在问发生了什么，还是已经有一项希望我支持的办法？`,
          `先别急着让我答应。告诉我谁该做什么、又由谁承担代价。`,
        ], seed);
      } else {
        const suffix = String(best.item.id).slice("endorse:".length);
        const refusal = allowed.find((item) => item.id === `refuse:${suffix}`);
        const guardedRefusal = tone === "guarded" && context.relationship < 38 && hashString(`${seed}:refuse`) % 3 === 0;
        action = guardedRefusal && refusal ? refusal.id : best.item.id;
        reply = action.startsWith("refuse:")
          ? choose([
            `我明白你的主张，但现在不能替它背书。${fact || anchor}，这份代价还没有说清。`,
            `你的理由我会记住，可我不会把它带进商议。至少今天不会。`,
          ], seed)
          : choose([
            `${fact || anchor}。你的话我会带进之后的商议，但最后会答应的不是我一个人。`,
            `我听见你的理由了。${fact || anchor}；我能承诺的是把它说给在场的人听。`,
            `这不是一句话就能定下的事。${fact || anchor}，不过你的主张值得被摆到桌面上。`,
          ], seed);
      }
    } else if (context.intent === "challenge") {
      const cautious = tone === "guarded" || /寡言|戒备|害怕失控/.test(traits.join(" "));
      const accepts = !cautious || context.relationship >= 55;
      action = accepts ? "debate_position" : "hold_position";
      reply = accepts
        ? choose([
          `好，那就把理由说清楚。你先告诉我：这项主张会让谁承担代价？`,
          `我接受你的质疑，但不接受一句漂亮话。拿事实来，我们逐条谈。`,
          `你可以反对我。只要你也愿意听完那些不会从结果里获益的人。`,
        ], seed)
        : choose([
          `我不会因为一句质疑就改口。等你带来能让当事人信服的证据，我们再谈。`,
          `你可以不赞成，但眼下我仍会守住自己的立场。`,
          `${flagClause || metricClause || "局势还不明朗"}，我不会在事实不足时作出承诺。`,
        ], seed);
    } else {
      if (/谢谢|多谢|感激|thank/i.test(context.playerMessage)) {
        action = "acknowledge_player";
        reply = choose([
          `不用把谢意挂在嘴边。等事情真正结束，再一起喝一杯。`,
          `我记下了。往后若我也需要你，希望你还会站在这里。`,
          `能帮上忙就好。这个世界已经有太多来不及说出口的话了。`,
        ], seed);
      } else if (/你是谁|叫什么|身份|做什么的/.test(context.playerMessage)) {
        action = "introduce_self";
        const role = text(npc?.role ?? npc?.job ?? npc?.title, "这里的居民", 100);
        reply = `我是${npcName}，${role}。我眼下最在意的是${goal}。`;
      } else if (fact) {
        action = "answer_from_knowledge";
        reply = choose([
          `这件事我知道一点：${fact}。${flagClause ? `${flagClause}，所以旧办法未必还管用。` : "你最好亲自去核实。"}`,
          `若你问的是这件事，答案就在这里——${fact}。别只听一个人的说法。`,
          `${fact}。我能确定的只有这些，其余部分恐怕有人故意遮掩。`,
        ], seed);
      } else {
        action = "consider_player_words";
        reply = choose([
          `${anchor}。你刚才的话我会认真想想，但现在还不能给你一个轻率的答案。`,
          `我明白你的意思。只是${anchor}，我们得先看清局势再行动。`,
          `这问题没有那么简单。${anchor}，任何选择都会让某些人付出代价。`,
        ], seed);
      }
    }

    reply = ensureSentence(reply).slice(0, 1200);
    const reason = compactReason([
      `${npcName}的性格偏向${primaryTrait}`,
      `当前目标是${goal}`,
      `与玩家的关系值为${context.relationship}`,
      metricClause ? `最低世界指标：${metricClause}` : "世界指标暂无明显短板",
      flagClause ? `当前事件：${flagClause}` : "当前没有已激活的重大事件标记",
      latestMemory ? `参考最近记忆：${latestMemory.slice(0, 100)}` : "尚无可用的近期交互记忆",
    ]);
    const intentNames = {
      greet: "问候",
      help: "求助",
      rumor: "传闻",
      secret: "秘密",
      challenge: "挑战",
      story: "公共议题",
      custom: "当前局势",
    };
    const memory = `${npcName}记得玩家曾就${intentNames[context.intent]}与自己交谈；自己的回应是“${reply.slice(0, 100)}”`;
    return { reply, action, reason, memory, provider: "local-rules" };
  }

  async _askBackend(npc, npcState, worldState, context, localDecision) {
    const payload = {
      npc_profile: publicNpcProfile(npc, npcState, context),
      world_state: publicWorldState(worldState, context),
      player_message: context.playerMessage,
      memories: context.memories.slice(0, 8),
    };
    const timeout = timeoutSignal(this.timeoutMs);
    try {
      const response = await this.fetchImpl(this.decisionUrl, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
        signal: timeout.signal,
      });
      const body = await response.json().catch(() => null);
      if (!response.ok) {
        if (response.status === 503 && body?.error?.code === "llm_not_configured") {
          this._status = {
            ...this._status,
            configured: false,
            error: "llm_not_configured",
            checkedAt: Date.now(),
          };
        }
        throw new Error(`decision_http_${response.status}`);
      }
      const decision = body?.decision && typeof body.decision === "object" ? body.decision : body;
      const reply = text(decision?.reply, "", 4000);
      if (!reply) throw new Error("decision_missing_reply");
      const action = text(decision?.action, localDecision.action, 1000);
      const allowedIds = (npc?.allowedActions || []).map((item) => String(item?.id || "")).filter(Boolean);
      if (allowedIds.length && !allowedIds.includes(action)) throw new Error("decision_action_not_allowed");
      this._backendRetryAt = 0;
      this._status = { ...this._status, reachable: true, error: null };
      return {
        reply,
        action,
        reason: text(decision?.reason, localDecision.reason, 2000),
        memory: text(decision?.memory, localDecision.memory, 4000),
        provider: text(decision?.provider, this._status.provider || "backend", 80),
      };
    } finally {
      timeout.cancel();
    }
  }

  async talk(npc, npcState, worldState, playerMessage = "", intent = "custom") {
    const safeNpc = npc && typeof npc === "object" ? npc : {};
    const safeNpcState = npcState && typeof npcState === "object" ? npcState : {};
    const safeWorldState = worldState && typeof worldState === "object" ? worldState : {};
    const context = this._buildContext(
      safeNpc,
      safeNpcState,
      safeWorldState,
      playerMessage,
      intent,
    );
    const localDecision = this._localBrain(safeNpc, safeNpcState, safeWorldState, context);

    if (!this.backendEnabled || !this.fetchImpl || Date.now() < this._backendRetryAt) {
      return localDecision;
    }

    const status = await this.checkBackend();
    if (!status.reachable || !status.configured) return localDecision;

    try {
      return await this._askBackend(
        safeNpc,
        safeNpcState,
        safeWorldState,
        context,
        localDecision,
      );
    } catch (error) {
      this._backendRetryAt = Date.now() + this.failureCooldownMs;
      this._status = {
        ...this._status,
        reachable: false,
        error: error?.name === "AbortError" ? "decision_timeout" : "decision_unavailable",
        checkedAt: Date.now(),
      };
      return localDecision;
    }
  }

  async plan(npc, npcState, worldState, allowedActions = []) {
    const actions = Array.isArray(allowedActions)
      ? allowedActions.slice(0, 12).map((action) => ({
          id: text(action?.id, "", 80),
          label: text(action?.label, "", 120),
          effects: safeTransport(action?.effects || {}, { includeSecrets: false }),
        })).filter((action) => action.id)
      : [];
    if (!actions.length) return null;
    const profile = { ...npc, allowedActions: actions };
    const instruction = [
      "这是新一天的自主战略规划，不是玩家对话。",
      `只能从以下行动 ID 中选择一个，并在 action 字段中原样返回 ID：${actions.map((action) => `${action.id}(${action.label})`).join("、")}`,
      "请结合你的目标、近期记忆和当前最薄弱的世界指标作决定；reply 用一句内心计划表达。",
    ].join("");
    return this.talk(profile, npcState, worldState, instruction, "custom");
  }
}

export default AIService;
