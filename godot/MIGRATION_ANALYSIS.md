# TIME ECHO 浏览器版 → Godot 4.6 迁移分析

## 1. 原项目盘点

迁移分析覆盖了仓库根目录中的 HTML、CSS、JavaScript、JSON、Python 服务、测试、图片生成工具、147 张美术图片、101 个旧导入旁车文件及剧情源文档。原文件保持只读；Godot 产物全部位于 `godot/`。

```text
mygame/
├── index.html                 浏览器入口、Canvas 与全部 DOM UI 容器
├── styles.css                 标题、HUD、日志、模态框、谜题、重置/结局演出的布局和视觉
├── js/
│   ├── main.js               fetch 数据、校验、装配服务和 Game、QA 查询参数
│   ├── game.js               输入、主循环、移动、旅行、交互、自由对话、存档、结局
│   ├── simulation.js         初始状态、时间循环、NPC 日程、知识/道具规则、剧情动作
│   ├── renderer.js           Canvas 世界、摄像机、碰撞、NPC 寻路、程序化地形和角色动画
│   ├── ui.js                 DOM UI、标题演出、对话、日志、五类谜题、重置和结局演出
│   ├── ai.js                 NPC 可见事实投影、离线人物规则、后端调用和动作白名单
│   ├── audio.js              Web Audio 程序化音效、环境声和轻量音乐
│   └── utils.js              数学、随机、路径读写、事件发射、格式化和 DOM 转义
├── data/
│   ├── world.json            游戏配置、公共事实、7 名 NPC、9 个物品、6 份证据
│   └── maps.json             1 个区域、17 个地点及地形/建筑/家具/交互/传送数据
├── art/
│   ├── runtime/              浏览器实际加载的透明 WebP、角色和远景图
│   ├── world/                1024×1024 PNG 源图及 Godot 导入旁车文件
│   ├── town_square/          广场源图与角色方向素材
│   └── _gen*/                美术生成阶段的源图
├── server.py                 静态服务器、同源 NPC API、OpenAI Responses 代理和校验
├── tools/
│   ├── build_runtime_art.py  从源图重建裁切透明运行时 WebP
│   └── npc_terminal.py       NPC 状态与剧情动作的终端实验台
├── tests/                    内容、NPC 行为和服务契约测试
├── my_script.doc             固定剧情源文档
└── README.md                 玩法、路线、AI 安全边界和启动说明
```

仓库没有独立音频文件、字体文件、IndexedDB、sessionStorage、WebSocket 或第三方前端包。音频全部由 Web Audio 合成；字体使用系统字体栈。

## 2. 启动、主循环与浏览器职责

- HTML 入口是 `index.html`，模块入口是末尾加载的 `js/main.js`。
- `main.js` 并行 fetch `world.json` 与 `maps.json`，校验 7 名居民和关键地点，然后创建 `AIService` 与 `Game`。
- `game.js` 通过 `requestAnimationFrame` 驱动循环：限制 delta、移动玩家、推进世界时间、更新 NPC、更新音频、渲染 Canvas，并以约 120 ms 节流更新 DOM HUD。
- `renderer.js` 的 Canvas 固定逻辑分辨率为 768×480；公共地图大于一屏，由平滑摄像机跟随玩家。DOM 侧栏与 Canvas 并列。
- CSS 负责标题屏、顶部 HUD、右侧现场日志、交互提示、纸张风格模态框、响应式断点、重置白光与结局排版。
- DOM 负责按钮、富文本、自由输入、焦点、标题键盘导航和模态层；Canvas 负责世界、人物、碰撞可视化、天气和昼夜。

## 3. 核心 JavaScript 文件职责

| 原文件 | 实际职责 | Godot 对应 |
|---|---|---|
| `js/main.js` | 数据加载/校验、服务装配、启动、浏览器 QA 参数 | `DataManager`、`main_controller.gd` |
| `js/game.js` | 输入、帧循环、移动、最近交互、传送、场景交互、自由对话、保存、结局 | `main_controller.gd`、`world_controller.gd`、`InteractionService`、`GameManager` |
| `js/simulation.js` | 状态初始化/归一化、时间、循环重置、NPC 日程、知识/物品/证据、剧情动作和结局条件 | `GameManager`、`TimeManager`、`DialogueManager`、`InventoryManager`、`KnowledgeManager` |
| `js/renderer.js` | 程序化地图、运行时贴图、摄像机、碰撞矩形、玩家/NPC 移动、角色和天气绘制 | `TimeEchoWorldView`、`TimeEchoWorldController`、`CharacterBody2D`、`Camera2D` |
| `js/ui.js` | 标题、序章、HUD、现场/完整日志、对话、五类谜题、重置、结局、通知 | `TimeEchoUI` 和 Godot `Control` 树 |
| `js/ai.js` | 人物可见事实裁剪、离线规则、HTTP 后端、响应动作白名单 | `TimeEchoAIService`、`AIProvider`、`LocalAIProvider`、`HttpAIProvider`、`WebAIProvider` |
| `js/audio.js` | 振荡器音色、脚步、钟、重置、环境声和音阶 | `AudioManager` + `AudioStreamGenerator` |
| `js/utils.js` | 数学/时间/对象路径/事件辅助 | Godot 内建数学、`EventBus`、局部工具函数 |

## 4. JSON schema

### `world.json`（`schemaVersion: 1`）

```text
root
├── schemaVersion: int
├── game: object
│   ├── id/title/subtitle: string
│   ├── loopRealSeconds/loopGameMinutes/startClockMinute/resetWarningMinute: number
│   └── saveKey: string
├── storyContext
│   └── publicFacts: string[]
├── npcs: NPC[7]
│   ├── id/name/displayName/role/initial/regionId/placeId: string
│   ├── x/y: number
│   ├── goal/voice/concern: string
│   ├── traits: string[]
│   ├── appearance: {skin,hair,body,trim,hairStyle,outfit,accessory?}
│   └── knowledge: {public:string[], suggestive:string[], forbidden:string[]}
├── items: Item[9]
│   └── {id:string, name:string, description:string}
└── evidence: Evidence[6]
    └── {id:string, name:string, source:string, text:string}
```

稳定 NPC ID：`arthur`、`beatrice`、`conrad`、`dorothea`、`elias`、`florence`、`ada`。

稳定物品 ID：`installation_wrench`、`silver_tuning_fork`、`room7_tag`、`unnumbered_key`、`spare_lens`、`flashlight`、`cave_negative`、`unfinished_portrait`、`fixed_portrait`。运行时代码另会产生普通维修件 `chapel_pin`；原 `world.json` 未给它静态条目，这是原 schema 的已知不一致，兼容层保留该 ID 而不丢弃。

证据 ID：`master_ar_record`、`chapel_ar_log`、`ledger_gap`、`brake_interface`、`inn_roof_reflector`、`return_exposure`。

### `maps.json`（`schemaVersion: 1`）

```text
root
├── schemaVersion: int
├── regions: Scene[]
└── places: Scene[]

Scene
├── id/name/subtitle/kind/biome?/regionId?: string
├── width/height/wallDepth?: number
├── spawn?: {x,y,facing?}
├── palette: color dictionary
├── shell?: object
├── zones[]: {type,x,y,w,h,collision?,...}
├── paths[]: {x,y,w,h,style?}
├── buildings[]: {id,label?,x,y,w,h,wallColor?,roofColor?,collision?,collisionRects?}
├── furniture[] / decorations[]: data-driven drawable rectangles
├── landmarks[]: {id,type,label?,description?,interactive?,x,y,w,h,layer?,collision?}
└── portals[]
    ├── id/label/type: string
    ├── x/y/w/h: number
    ├── targetRegionId/targetPlaceId: stable scene ID
    ├── spawn: {x,y,facing?}
    ├── travelSeconds?: number
    └── revealFlag?: state flag ID
```

引用校验包括所有 portal 目标、spawn、关键地点、NPC、物品和证据稳定 ID。秘密入口继续使用 `low_tide`、`basement_open`、`hidden_darkroom_open` 三个原标志。

## 5. 必须保持的行为

- 标题、Continue、Begin、Loop Archive 与独立序章。
- 玩家以 96 px/s 行走、164 px/s 奔跑；WASD、方向键、Shift、E/Space、J、I/B、Esc/P 和鼠标点击。
- 公共地图大于视口，摄像机平滑跟随；室内外共 18 个数据地点。
- 建筑、家具、实心 zone 与明确 collision landmark 使用原矩形语义碰撞。
- 三钟谜题答案不变：主钟中/大/小且红线全朝上；礼拜堂需第四擒纵销；潮汐低/中/高。
- 物品获取、证据检查、知识锁和 NPC 当面交付的边界不变；索引卡不会自动扫描背包。
- 七名 NPC 的工作地点和晚间旅店日程；Ada 只在暗房条件满足后出现。
- 固定选项与自由文本并存。自由文本只能触发本地规则已经开放且语义明确的动作；模型不能自行写状态。
- 一轮从星期六 06:00 到星期日 06:00，现实约 12 分钟；1 秒对应 2 游戏分钟。
- 自由对话时为 1/4 时间倍率；`low-tide-cave` 与 `hidden-darkroom` 完全停时。
- 05:55 白光重置；维修、承诺、普通实物和本轮证据复位；日志、知识、照片、NPC 笔记跨轮保留。
- 底片严格按“重影 → 反差 → 反射”显影。
- Ada 的姓名、住处、职责、面孔必须逐项在本轮暗房中由本人核验；不能互相替代。
- 表层红杆结局需要康拉德、阿瑟、贝娅特丽斯的三个亲自承诺；真结局需要定影肖像进入第七见证位。
- 存档语义从 localStorage 迁移至 `user://time-echo-save-v1.json`；结局档案独立保存最近 12 条。

## 6. HTML/JS → Godot 映射

| 浏览器概念 | Godot 4.6 实现 |
|---|---|
| `#game-canvas` | `Node2D` 自定义 `_draw()`、`Sprite2D`、`CharacterBody2D`、`Camera2D` |
| DOM 模态框/侧栏/HUD | `CanvasLayer` + `Control`/`PanelContainer`/Container/Label/Button/RichTextLabel/LineEdit |
| CSS Grid/Flex/absolute | Godot Anchor、Offset、Size Flags、HBox/VBox/Center/Margin Container、Theme/StyleBoxFlat |
| `requestAnimationFrame` | `_process(delta)`、`_physics_process(delta)` |
| keydown/keyup/pointer | InputMap、`_unhandled_input`、Control 信号 |
| `setTimeout` | `SceneTreeTimer` + `await` |
| JS module/class | `class_name` Node/RefCounted 与 Autoload |
| 全局 Game/AI 引用 | `GameManager`、`EventBus` 和场景内 `TimeEchoAIService` |
| Canvas 摄像机 | `Camera2D` 限位和平滑 |
| Canvas 碰撞矩形 | `StaticBody2D` + `CollisionShape2D`，玩家为 `CharacterBody2D` |
| DOM 场景状态 | 一个数据驱动 location scene，由 `SceneManager` 切换 JSON place ID |
| Web Audio | `AudioStreamGenerator` 实时合成 |
| fetch 静态 JSON | `FileAccess` + `JSON` |
| fetch NPC API | `HTTPRequest` / `JavaScriptBridge` / 本地规则 |
| localStorage | `user://` UTF-8 JSON |
| 自定义 Emitter | 类型化 `signal` 与 `EventBus` |

## 7. 风险与不确定项

1. 原 `renderer.js` 超过 3000 行，含大量逐像素程序绘制、天气细节与 NPC A* 网格路径。Godot 版复用全部运行时图片、原坐标、调色板和碰撞数据，但程序绘制细节不是逐像素复制；行为优先于像素级截图一致。
2. 原角色 WebP 是单张透明立像，不是明确帧表。Godot 版保留角色图、朝向镜像和移动，未伪造不存在的帧切片；原 Canvas 的六帧程序化步态由平滑节点移动替代。
3. 在线 AI 是否可用取决于部署者继续运行同源 `server.py` 或提供兼容端点。未配置时完整固定剧情仍可通关。
4. 原自由对话有较长的中文关键词与上下文推断表。Godot 兼容层保留关键不可逆动作的本地门槛与白名单；普通闲聊的离线措辞更精简。
5. 已使用本机 `Godot_v4.6.3-stable_win64_console.exe` 完成编辑器导入、GDScript 编译、资源导入、项目内测试场景和主场景启动检查。跨平台窗口布局、音频主观效果和 Web 导出仍需在对应目标平台做人工验收。
