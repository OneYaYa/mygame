# Ember Echo

《Ember Echo》是一个无需构建步骤的像素风 2D 世界线游戏原型。开始时可以选择“进入世界”，也可以选择“旁观世界”。旅行者能在五地移动、与 15 位 NPC 交谈并干预关键事件；旁观模式中不会生成玩家，NPC 会按照日程生活、积累记忆、自主处理第 2–8 日事件，并在第 9 日写下完全没有玩家介入的结局。

游戏默认使用浏览器内的本地规则 Agent，不需要 API Key。也可以选择在 Python 服务端配置 OpenAI-compatible Chat Completions 接口来增强 NPC 对话与每日战略规划。

## 视觉方向

标题页使用英文标题与菜单，并呈现一幅固定低分辨率、由 Canvas 逐像素绘制的“余烬井边”微场景：远处五地各留一盏灯，旅行者坐在井火旁，夜空偶尔划过一颗坠星。页面只保留一句序言和朴素文字菜单；聚焦 `Observe the World` 时，旅行者会从画面中消失。场景不依赖生成式背景图，也没有复制其他商业游戏的 Logo、版式或素材。

游戏内部继续使用原创的温暖乡村像素 RPG 语言：田园绿背景、木质双层边框、奶油色纸张、陶土按钮与麦金色提示，避免深紫霓虹、玻璃面板和过多技术标签。地图由 Canvas 实时绘制，因此昼夜、天气、NPC 日程和观察模式都能继续动态变化。

五个室外区域都扩展为 `1536 × 960` 的连续大地图（相当于四个游戏视口），镜头跟随玩家平滑滚动，不再把整张地图塞在一个屏幕。王城有城墙、双层街区、集市、水渠、路牌与街井；农田由灌渠切分为田垄、果园和牧场，并散布稻草人、蜂架与种子箱；豪宅拥有对称庭院、花钟、镜池、雕像与私道；雪山使用高度带、裂谷、冰川、积雪松林与补给点；沙漠则由低频沙丘、岩台、绿洲、商帐和巨型遗迹构成。每个室外区域至少布置六件不触发交互的环境物件，让生活路径保持可走，又不会只剩大块空地。另有 15 个可以进入的室内空间。

玩家和 15 位居民现在都使用围绕脚底坐标绘制的高细节原创像素角色：四方向拥有不同的脸部、头发和服装轮廓，移动时使用四阶段步态，左右腿与手臂反向摆动并带轻微重心起伏。步态由每帧的真实位移驱动，因此撞墙、暂停和站立时不会原地踏步；NPC 也会保留最后朝向。碰撞脚盒、遮挡排序和交互距离没有随人物视觉尺寸放大。所有游戏内角色、建筑和地形都是项目自己的实现，没有引入或复制其他商业游戏的贴图、角色或 UI 素材。

## 快速启动

只需要 Python 3 和现代浏览器。服务端仅使用 Python 标准库，不需要 `pip install`，前端也不需要 npm 或打包工具。

```powershell
cd C:\Users\ethanypan\Desktop\generative_agents\mygame
python server.py
```

如果 Windows 上的 Python 命令是 `py`，也可以运行：

```powershell
py -3 server.py
```

看到类似以下输出后保持终端运行：

```text
Game server: http://127.0.0.1:8000
NPC LLM: not configured (frontend should use rules fallback)
```

然后访问：

- 游戏：<http://127.0.0.1:8000/>
- 服务状态：<http://127.0.0.1:8000/api/health>
- 前端安全配置：<http://127.0.0.1:8000/api/config>

终端中的 `NPC LLM: not configured` 不影响游玩，它表示 NPC 对话使用本地规则 Agent。

## 操作

| 操作 | 键位或按钮 |
| --- | --- |
| 移动 | `W` `A` `S` `D` 或方向键 |
| 交谈 / 调查 / 进门 / 使用交通 | `E` |
| 打开路线地图 | `M` |
| 打开完整纪事录 | `J` |
| 展开 / 收起手账 | `B` |
| 关闭当前可关闭窗口 | `Esc` |
| 暂停时间 | `1`，或顶部 `Ⅱ` |
| 1 倍时间 | `2`，或顶部 `1×` |
| 2 倍时间 | `3`，或顶部 `2×` |
| 4 倍时间 | `4`，或顶部 `4×` |
| 8 倍时间 | `5`，或顶部 `8×` |
| 等待 | 画面下方“等待 1 小时” |
| 手动保存 | 顶部 `▣` 按钮 |

旅行者进入时手账默认收起，让地图占据主要画面；旁观模式会默认展开手账以便查看世界变化。随时按 `B` 可以切换。旅行者靠近 NPC、地标、房门或交通点时，画面会显示对应的 `E` 提示。`M` 打开的地图在旅行者模式中只用于查看路线，不能直接传送：卡片会列出直达交通、耗时或需要经过的中转地区；玩家仍需实际走到南门、马车、缆车、商队或山道处出发。不同路线消耗 18–40 游戏分钟，普通房门不消耗游戏时间。

### 上帝视角

标题界面点击 `Observe the World`，再选择一条世界线即可开始观察。该模式与旅行者模式共用世界内容和结局规则，但有意移除了所有玩家因果变量：

- Canvas 中没有玩家角色，`E` 不会交谈、调查或改变世界；`WASD` / 方向键用于平移大地图观察镜头；
- 地图按钮只是切换观察镜头，不消耗游戏时间、不写纪事，也不会被 NPC 感知；观察室内时点击当前地区可返回该区室外大地图；
- “人物”页从一开始显示全部 15 位 NPC，点击可只读查看其目标、当前反思、近期记忆和知识；
- 第 2–8 日事件展示所有候选方案，但按钮不可点击；NPC 会在 5 秒权衡后自行选择；
- 地图、纪事和 NPC 档案打开时世界仍持续运行，可用 `1`–`5` 或顶部按钮暂停、加速到 8 倍；
- 存档会保留当前模式；标题页会相应显示 `Continue Watching`。

观察镜头所在地图不参与 NPC 决策，也不消耗模拟随机数。因此只切换观看区域不会改变世界指标、NPC 的后续行动或结局。

## 世界线与结局机制

### 三条时间线

新游戏首先要求从“余火”“律法”“回响”三条时间线中选择一条。选择卡片从左到右（窄屏时从上到下）依次为简单、普通、困难。三条线共享五地、NPC、九日流程中的七个大事件和同一组结局门槛，但分别设置不同的：

- 初始粮食、水源、秩序、希望和星辉；
- 王冠议会、众民同盟、守秘人和远途商队的初始倾向；
- NPC 初始关系与开局事件标记；
- 出生地图、随机种子及每日天气候选；
- 贯穿整局的每日生存消耗倍率与 NPC 生存指标恢复倍率。

“余火”的每日粮食、水源、秩序与希望消耗较缓，NPC 恢复这些指标的效率较高；“律法”使用标准压力；“回响”每日消耗更高，NPC 恢复更慢。星辉可能通向希望，也可能通向灾祸，因此不使用简单的难度倍率。随机种子使同一条时间线中的天气和规则 Agent 选择可重复，同时不同时间线的初始条件会让 NPC 更偏向不同的行动。

### 五张地图与 15 位 NPC

世界包含以下五个宏观地区，每个地区都有多屏室外地图和三处关键室内：

1. 王城 `capital`
2. 农田 `farm`
3. 白棘豪宅 `mansion`
4. 雪山 `snow`
5. 赤沙漠 `desert`

跨区不是统一的地图按钮传送。王城南门步行通向农田，白棘马车连接王城与豪宅，绞盘缆车连接王城与雪山，赤帆商队连接农田与沙漠，另外还有豪宅私道和雪山—沙漠古道。王宫、档馆、巡卫所、农舍、磨坊、蜂棚、主宅、画室、医舍、瞭望塔、驿站等房间都能双向进入。

15 位 NPC 都有静态身份、性格、价值观、目标、公开知识、秘密、关系阈值、日程和行动偏好。NPC 会按日程移动，并约每三个游戏小时根据所在地、个人目标和当前最薄弱的世界指标作出一次自主决定。行动会改变世界指标与势力倾向，并形成最多 12 条近期记忆；达到一定记忆量后还会生成阶段性反思。

玩家与 NPC 的问候、求助、传闻、秘密、立场或自由对话也会写入记忆并改变关系。关系达到 NPC 自己的 `secretTrust` 阈值后，询问秘密才可能解锁对应线索标记。

### 第 2–8 日固定事件

`data/world.json` 按日期和时刻安排七个固定事件：第 2 日断渠、第 3 日夜宴账簿、第 4 日雪崩、第 5 日沙暴遗迹、第 6 日五地议会、第 7 日面包骚乱、第 8 日余烬钥匙。时间到达事件时，事件会进入待处理队列并弹出选择窗口。旅行者有 30 秒作出一个满足条件的选择；若保持沉默，NPC 会自行决定。上帝视角没有可点击选项，NPC 会在 5 秒展示倒计时后根据当前最薄弱的世界指标、势力倾向和时间线种子作出决定。

事件选择可以同时改变：

- `metrics`：粮食、水源、秩序、希望、星辉；
- `factions`：四方势力倾向；
- `relationships`：指定 NPC 与玩家的关系；
- `flags`：后续事件或结局使用的事实标记；
- `memory`：写入所有涉事 NPC 的共同记忆。

部分选择可以通过 `requirements` 要求玩家先调查地标、取得秘密、达到某项指标或完成前置选择。条件不满足时，按钮会显示锁定原因。

### 第 9 日结局

当前内容在第 9 日 21:00 到达结局时刻。系统会先要求处理所有待决事件，再结算结局；具体日期与时刻由 `game.endingDay` 和 `game.endingHour` 控制。结局按 `priority` 从高到低检查：

1. `condition.all` 中的规则必须全部满足；
2. `condition.any` 为空或至少满足一项；
3. `condition.flags` 中的标记必须满足；
4. 若没有特殊结局命中，则使用 `fallback: true` 的兜底结局。

解锁的结局会写入独立的结局图鉴。结算后可以进入或观察另一条世界线，也可以停在结局前夜：旅行者能继续与 NPC 告别，上帝视角则能查看五地与所有 NPC 的最终档案。

## 本地规则 Agent

不创建 `.env` 就是默认且可运行的方式。浏览器会从以下信息生成确定性的本地回复：

- NPC 的身份、性格、目标、公开知识与秘密；
- 与玩家的当前关系和秘密阈值；
- 最近记忆；
- 当前世界指标、事件标记、日期、天气和地区；
- 玩家选择的对话意图与输入内容。

本地规则 Agent 会返回与服务端相同的 `reply`、`action`、`reason`、`memory` 四个字段。因此即使后端未配置、请求超时或模型服务暂时不可用，对话也会自动降级，不会中断世界模拟。

## 可选 OpenAI-compatible Agent

### 1. 创建本地配置

在 `mygame` 目录执行：

```powershell
Copy-Item .env.example .env
notepad .env
```

填写：

```dotenv
LLM_API_KEY=你的真实密钥
LLM_BASE_URL=https://api.openai.com/v1
LLM_MODEL=gpt-4o-mini
MAX_REQUEST_BYTES=65536
LLM_TIMEOUT_SECONDS=20
```

`LLM_BASE_URL` 应指向 OpenAI-compatible API 的版本根路径；服务端会自动追加 `/chat/completions`。如果填写的地址本身已经以 `/chat/completions` 结尾，服务端不会重复追加。

### 2. 重启服务

```powershell
python server.py
```

刷新游戏后，手账“偏好”页会用世界内语言显示居民心智的当前模式。启用“深度思考”后，每次玩家对话会向同源后端发送一次请求；此外，每个游戏日会轮换 3 位 NPC 请求一次战略计划，因此 5 个游戏日内所有 15 位 NPC 都至少获得一次模型规划机会。失败时自动回到本地规则 Agent。

模型只能从世界引擎给出的行动 ID 白名单中选择战略行动；前端会再次验证返回值。模型不能直接写指标、瞬移角色或触发结局，固定事件和结局始终由确定性的世界引擎裁决。这既控制调用成本，也防止提示词注入或异常输出破坏存档。

### 密钥安全

- 真实 Key 只能放在 `mygame/.env` 或服务进程环境变量 `LLM_API_KEY` 中。
- 不要把 Key 写进 `index.html`、任何 `js/` 文件、`data/world.json` 或浏览器控制台。
- `/api/config` 只返回是否配置、模型名和公开限制，不返回 Key 或上游地址。
- Python 静态服务器拒绝访问 `.env*`、`server.py` 和 `tests/`。
- `.env` 已被仓库的 `.gitignore` 忽略，但提交前仍应检查 Git 状态。

模型响应会在服务端规范化为：

```json
{
  "reply": "NPC 对玩家说的话",
  "action": "简短行动",
  "reason": "作出判断的原因",
  "memory": "值得保留的一条记忆"
}
```

## 存档与清档

存档保存在当前站点的浏览器 `localStorage` 中，不会写入 Python 服务端：

| 键 | 内容 |
| --- | --- |
| `ember_echoes.save.v1` | 当前模式、世界线状态、兼容玩家位置、观察镜头、时间、指标、NPC 状态、事件与纪事 |
| `ember_echoes.meta.v1` | 结局图鉴、上次结局、完成次数、声音、LLM 与思考显示偏好 |

游戏每约 25 秒自动保存一次，也会在旅行、等待、对话、事件选择和结局等关键节点保存。顶部 `▣` 可以手动保存。

清除当前世界线、保留结局图鉴和偏好：

```javascript
localStorage.removeItem("ember_echoes.save.v1");
location.reload();
```

完全清档，包括结局图鉴和偏好：

```javascript
localStorage.removeItem("ember_echoes.save.v1");
localStorage.removeItem("ember_echoes.meta.v1");
location.reload();
```

以上代码需要在游戏页面的浏览器开发者工具 Console 中执行。也可以在开发者工具的 Application / Storage / Local Storage 中删除对应键。存档按“协议 + 主机 + 端口”隔离；从 8000 端口切换到 8001 后，浏览器会把它视为另一个存储来源。

## 目录结构

```text
mygame/
├── index.html              # 页面结构与所有游戏窗口
├── styles.css              # 像素风布局、动画和响应式样式
├── server.py               # 零依赖静态服务器与 NPC LLM API
├── .env.example            # 可选服务端配置模板
├── data/
│   ├── world.json          # 时间线、NPC、日程、事件与结局内容
│   └── maps.json           # 五张大地图、15 个室内、门、交通与碰撞
├── assets/
│   ├── chronicle-keyart.png       # 未启用的早期标题视觉稿
│   └── chronicle-keyart-cozy.png  # 未启用的早期暖色视觉稿
├── js/
│   ├── main.js             # 合并并校验 world.json / maps.json，启动游戏
│   ├── title-scene.js      # 标题页低分辨率像素场景与菜单键盘交互
│   ├── game.js             # 主循环、输入、互动、存档和界面编排
│   ├── simulation.js       # 世界时间、NPC 自主行动、事件和结局
│   ├── renderer.js         # Canvas 像素地图与角色绘制、碰撞
│   ├── ai.js               # 本地规则 Agent 与可选后端降级
│   ├── ui.js               # 各面板、对话、事件和结局 UI
│   ├── audio.js            # Web Audio 提示音
│   └── utils.js            # 随机、坐标、转义等通用函数
└── tests/
    ├── test_content.py     # 世界数据、坐标、引用和静态资源校验
    └── test_server.py      # Python HTTP 服务与上游模型 mock 测试
```

## 扩展世界与地图数据

`world.json` 负责模拟与剧情，顶层的 `timelines`、`regions`、`npcs`、`events`、`endings` 必须都是非空数组。`maps.json` 负责空间布局，包含五个 `regions` 布局与 `places[]` 室内。启动时 `main.js` 会合并两份数据，并检查地区、房间、NPC 日程、门和目标地点的引用。版本 1 存档会迁移到版本 2，并把玩家安全放到当前地区的新出生点。

### 顶层字段

| 字段 | 主要用途 |
| --- | --- |
| `game` | 内容版本、起始时间、总天数、结局时间、初始指标与势力 |
| `timelines[]` | 三条世界线的显示信息、难度、种子、天气、初始修正与持续规则 |
| `regions[]` | 五个宏观地区的名称、说明、世界地图位置与基础色板 |
| `npcs[]` | 15 位 NPC 的静态知识、秘密、关系、日程和行动偏好 |
| `events[]` | 第 2–8 日固定事件、条件、选择、效果与共同记忆 |
| `endings[]` | 第 9 日结局文本、优先级、条件和兜底项 |

### `game`

常用字段如下：

```json
{
  "contentVersion": 2,
  "startRegion": "capital",
  "startMinute": 420,
  "totalDays": 9,
  "endingDay": 9,
  "endingHour": "21:00",
  "initialMetrics": {
    "food": 54,
    "water": 52,
    "order": 58,
    "hope": 48,
    "aether": 35
  },
  "initialFactions": {
    "crown": 50,
    "commons": 45,
    "keepers": 35,
    "caravan": 40
  }
}
```

`startMinute` 使用一天内的分钟数，例如 420 是 07:00。`endingHour` 既可写 `"21:00"`，也可用分钟数。五项指标和四项势力值会被限制在 0–100。

### `timelines[]`

```json
{
  "id": "timeline-id",
  "name": "世界线名称",
  "description": "开局说明",
  "glyph": "✦",
  "color": "#d9a85c",
  "hints": ["给玩家的提示"],
  "difficulty": { "rank": 1, "label": "简单", "dailyDrain": 0.8, "npcRecovery": 1.15 },
  "seed": 1001,
  "startRegion": "capital",
  "weather": ["晴", "薄云", "星尘"],
  "modifiers": {
    "metrics": { "hope": 8 },
    "factions": { "commons": 6 },
    "relationships": { "npc-id": 5 },
    "flags": { "opening_flag": true }
  }
}
```

`difficulty.rank` 必须按数组顺序使用 `1`、`2`、`3`。`dailyDrain` 只缩放每天清晨粮食、水源、秩序和希望的自然消耗；`npcRecovery` 只缩放 NPC 自主行动对这四项生存指标的正向恢复。事件选项、势力变化、星辉变化和结局门槛保持一致，因此难度来自持续生存压力，而不是隐藏地改写玩家的选择。

### `maps.json`：室外、室内与出口

Canvas 仍是 `768 × 480` 的视口，但地图对象使用独立的世界坐标。当前室外尺寸为 `1536 × 960`，室内为 `960 × 620` 或 `1152 × 720`。`maps.json.regions.<region-id>` 会覆盖 `world.json` 中同 ID 地区的空间字段；`places[]` 保存室内。

场景支持：

- `width` / `height`、`spawn: {x, y}` 与 `biome`；
- `palette`：`ground`、`groundAlt`、`path`、`edge`、`accent`、`water`、`wall`、`roof`；
- `paths[]`：道路矩形与可选 `style`；
- `zones[]`：`crop`、`orchard`、`canal`、`hedge`、`pond`、`cliff`、`ice`、`dune`、`oasis`、`rug` 等地貌；
- `obstacles[]`：矩形碰撞区域；
- `buildings[]`：建筑外观；`collisionRects[]` 可以分段留下真实门洞；
- `furniture[]`：室内家具，设置 `collision: false` 可关闭碰撞；
- `landmarks[]`：可调查地标，第一次调查会写纪事并设置 `flag`；
- `portals[]`：门、城门、马车、缆车、商队或山道。

一个出口的最小结构如下：

```json
{
  "id": "palace-door",
  "kind": "door",
  "label": "推开晨星宫大门",
  "x": 742,
  "y": 268,
  "w": 52,
  "h": 40,
  "minutes": 0,
  "target": {
    "regionId": "capital",
    "placeId": "capital-palace",
    "x": 576,
    "y": 646,
    "facing": "up"
  }
}
```

跨区交通设置 `minutes`；同地区房门通常为 `0`。目标坐标必须位于目标场景边界内，并避开家具、障碍和返回出口。

### `npcs[]`

```json
{
  "id": "npc-id",
  "name": "姓名",
  "role": "身份",
  "regionId": "capital",
  "x": 360,
  "y": 260,
  "color": "#9a6c78",
  "traits": ["谨慎", "重承诺"],
  "values": ["秩序", "家人"],
  "goal": "九日内想完成的目标",
  "knowledge": ["可用于回答玩家的公开事实"],
  "secret": "达到信任门槛后才会透露的信息",
  "secretTrust": 55,
  "initialRelationship": 10,
  "dialogue": { "greetings": ["初次见面。"] },
  "actionWeights": { "patrol": 1.2 },
  "schedule": [
    {
      "start": "07:00",
      "end": "12:00",
      "regionId": "capital",
      "placeId": "capital-archive",
      "x": 480,
      "y": 220,
      "activity": "在旧档馆整理坠星旧卷"
    }
  ]
}
```

`schedule` 可以让 NPC 在一天内改变地区、室外 / 室内地点和坐标。缺少 `placeId` 时默认位于该地区室外；切换房间时 NPC 会直接在目标日程点出现，同一场景内则会步行到新坐标。对话使用的 `knowledge` 可以是字符串、数组或嵌套对象；不要在其中放服务端秘密或 API Key，因为世界数据会完整发送到浏览器。NPC ID 应保持唯一，并同步更新事件、关系修正和结局条件中的引用。

### `events[]`

```json
{
  "id": "day-2-event",
  "day": 2,
  "hour": "12:00",
  "regionId": "farm",
  "title": "事件标题",
  "description": "事件描述",
  "context": "选择前的额外背景",
  "npcIds": ["npc-id"],
  "colors": ["#60465f", "#c08359"],
  "choices": [
    {
      "id": "choice-id",
      "label": "选择标题",
      "description": "选择说明",
      "requirements": [
        {
          "path": "metrics.hope",
          "op": ">=",
          "value": 50,
          "label": "希望至少达到 50"
        }
      ],
      "effects": {
        "metrics": { "hope": 8, "order": -3 },
        "factions": { "commons": 5 },
        "relationships": { "npc-id": 6 },
        "flags": ["helped_the_people"]
      },
      "outcome": "选择后显示和写入纪事的结果",
      "memory": "写入涉事 NPC 的共同记忆"
    }
  ]
}
```

`requirements` 也可以直接写标记字符串。对象条件支持 `>`、`>=`、`<`、`<=`、`==`、`!=` 和 `includes`。事件应至少保留一个始终可选的选择，避免所有按钮同时锁定而无法推进时间线。

### `endings[]`

```json
{
  "id": "ending-id",
  "title": "结局名称",
  "subtitle": "结局短句",
  "glyph": "✦",
  "hint": "未解锁时显示的提示",
  "priority": 100,
  "epilogue": ["第一段后记。", "第二段后记。"],
  "condition": {
    "all": [
      { "path": "metrics.hope", "op": ">=", "value": 70 }
    ],
    "any": [
      { "path": "factions.commons", "op": ">=", "value": 65 }
    ],
    "flags": ["helped_the_people"]
  }
}
```

至少保留一个 `{ "fallback": true }` 的低优先级结局。状态路径以存档状态为根，常用前缀包括 `metrics.*`、`factions.*`、`flags.*`、`statistics.*` 和 `npcs.<npc-id>.relationship`。

## 测试

后端测试使用 `unittest` 和 mock 上游响应，不会调用真实模型，也不需要第三方依赖：

```powershell
cd C:\Users\ethanypan\Desktop\generative_agents\mygame
python -B -m unittest discover -s tests -v
```

当前 33 项测试覆盖 3 条时间线、5 张多屏室外地图、15 个室内、42 个门或交通出口端点、15 位 NPC 的 60 段地点日程、Day 2–8 事件、9 个结局、效果字段、地图边界、可行走出生/转场落点、目标引用和本地静态资源；还会检查上帝视角入口与状态接线、旧存档迁移、无副作用切换观察地图、观察镜头不影响模拟随机数、事件不可干预且始终存在自主候选。后端部分覆盖配置解析、密钥不泄露、健康检查、无 Key 的 503 降级、请求 JSON 与大小校验、上游超时、敏感静态文件保护，以及 OpenAI-compatible 响应解析。`-B` 用于避免在工作目录生成 `__pycache__`。

## 常见问题

### 双击 `index.html` 后一直加载，或出现 `fetch` / CORS 错误

不要使用 `file://` 打开页面。游戏通过 ES Modules 加载脚本，并通过 `fetch` 合并 `data/world.json` 与 `data/maps.json`，必须由 HTTP 服务提供：

```powershell
python server.py
```

然后访问 <http://127.0.0.1:8000/>。

### 8000 端口已被占用

换一个端口启动：

```powershell
python server.py --port 8001
```

然后访问 <http://127.0.0.1:8001/>。注意不同端口使用不同的浏览器存档空间。

### `/api/npc/decide` 返回 503

当没有配置 `LLM_API_KEY` 时，这是预期的安全降级信号：

```json
{
  "error": { "code": "llm_not_configured" },
  "fallback": "rules"
}
```

前端会识别该响应并继续使用本地规则 Agent。只有希望启用大模型增强对话时，才需要复制 `.env.example` 并配置服务端 Key。

### 页面显示“世界线编织失败”

先确认当前地址是 HTTP 地址而不是 `file://`，再分别打开 <http://127.0.0.1:8000/data/world.json> 与 <http://127.0.0.1:8000/data/maps.json> 检查是否能够读取。若刚修改过内容，还应检查 JSON 语法、五个宏观地区是否齐全，以及 NPC 日程和出口的 `placeId` 是否存在。
