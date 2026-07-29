# TIME ECHO Godot 4.6 迁移报告

## 工程结论

已在 `godot/` 建立独立 Godot 4.6 工程。原 HTML/JS/JSON、Python、图片和剧情文档没有删除、覆盖或重命名。主场景为 `res://scenes/main/main.tscn`。

工程不是 JS 逐行翻译：数据和剧情状态继续以稳定 ID 驱动，运行时按 Godot 场景树、节点、信号、Autoload、CharacterBody2D 碰撞和显式流程状态机重建。

## 已迁移功能

- 有远景图、Begin、Continue、Loop Archive 的标题页。
- 序章、HUD、地点标题、时间、循环计数、现场日志、完整日志、背包、证据和居民页。
- 18 个 JSON 地点（1 region + 17 places）的数据驱动实例化、摄像机、昼夜色调、像素地表、建筑/家具/装饰/landmark 绘制。
- `art/` 下 147 张图片已按原目录完整镜像到 `assets/images/source_art/`；101 个旧 `.import` sidecar 未复制，由 Godot 4.6.3 重建导入缓存。
- 原 `art/runtime/` 的 46 个 PNG/WebP 透明运行资源继续保留稳定运行时路径；草地、水面、石路、木地板四张源纹理已实际接入世界渲染，建筑和道具增加统一透明落影；Godot 默认 nearest filter。
- 玩家行走、奔跑、方向、世界边界、建筑/家具/zone/landmark 碰撞。
- 原 portal 目标、spawn、travelSeconds 和三个 revealFlag；地点切换与旅行时间推进。
- 键盘 InputMap 和鼠标点击世界对象。
- 七名 NPC、工作/晚间日程、地点移动、交互距离、头像和名称。
- 固定对话选项、自由文本输入、对话历史、NPC 笔记、动作白名单与本地剧情校验。
- AIProvider 分层：JavaScriptBridge 浏览器钩子、HTTPRequest 服务端、完整本地固定规则回退。
- 三钟维修、工具鉴定、登记簿/七号房链、洞穴窗口、受潮底片、三步显影、隐藏暗房、Ada 四锚点、肖像定影和安装。
- 表层结局与真结局；最近 12 条结局进入 Loop Archive。
- 12 分钟时间循环、对话 1/4 倍率、洞穴/暗房停时、05:55 重置演出。
- 跨轮保留日志、知识、照片和 NPC 笔记；重置本轮实物、维修、NPC 承诺和证据。
- `user://` 版本化 UTF-8 JSON 存档/读档、旧版本兼容入口；Web 首次启动会把原 `time-echo-save-v1` localStorage 自动导入 `user://`。
- Web Audio 等价的 `AudioStreamGenerator` 程序化钟声、脚步、事件、重置、环境音阶。
- 暂停/帮助/声音设置、保存通知和结局重开。
- JSON schema、稳定 ID 和 portal 引用校验；缺失/错误字段输出明确错误。
- 独立静态验证脚本与无需第三方插件的 GDScript 测试运行器。

## 部分迁移/兼容层

- `renderer.js` 的逐像素装饰密度、天气粒子、逐帧角色肢体绘制和 NPC A* 网格寻路没有机械复刻。Godot 使用原贴图、原坐标、原碰撞矩形、摄像机和迁移后的无缝像素表面重建；NPC 以带目标的平滑节点移动。玩法和空间引用保留，截图级像素差异仍可能存在。
- 自由文本的不可逆剧情动作沿用严格本地门槛；在线模型只可生成 `continue_conversation` 的表达，不能直接改状态。离线普通闲聊比原 `ai.js` 的长规则库更精简，但固定选项保证完整通关。
- 原标题/白光 Canvas 动画在 Godot 中改为 Control、远景贴图、计时器和程序化音频演出，时序与功能等价但不是逐帧录像复刻。
- 原 `chapel_pin` 是运行时代码产生、但未列入 `world.json.items` 的 ID。Godot 保留兼容 ID并在数据分析中报告，没有静默丢弃。

## 未迁移为游戏运行时功能

- 浏览器专用 `?qa=scene|puzzle|dialogue|ending` URL 调试入口未放入发行 UI；Godot 可从编辑器直接运行相应 scene/test。
- `tools/npc_terminal.py` 是开发实验台，不属于浏览器游戏运行时，仍原样保留在仓库根目录。
- 原项目没有磁盘音频或字体资源，因此没有可复制文件；对应功能由程序合成和系统字体回退实现。

## JS → GDScript 对应

| JavaScript | Godot 文件 |
|---|---|
| `js/main.js` | `scripts/autoload/data_manager.gd`, `scripts/main/main_controller.gd` |
| `js/game.js` | `main_controller.gd`, `world_controller.gd`, `interaction_service.gd`, `game_manager.gd`, `save_manager.gd` |
| `js/simulation.js` | `time_manager.gd`, `dialogue_manager.gd`, `inventory_manager.gd`, `knowledge_manager.gd`, `game_manager.gd` |
| `js/renderer.js` | `world_view.gd`, `world_controller.gd`, `player_controller.gd`, `npc_actor.gd` |
| `js/ui.js` | `ui_controller.gd`, `game_ui.tscn` |
| `js/ai.js` | `ai_service.gd`, `ai_provider.gd`, `local_ai_provider.gd`, `http_ai_provider.gd`, `web_ai_provider.gd` |
| `js/audio.js` | `audio_manager.gd` |
| `js/utils.js` | Godot 内建 API、`state_rules.gd`, `event_bus.gd` |

## Autoload 职责

- `EventBus`：跨系统类型化信号。
- `DataManager`：读取、索引和校验 `world.json`/`maps.json`。
- `SaveManager`：`user://` 存档、读档、版本迁移和结局档案。
- `InventoryManager`：物品数量、查询和 UI 投影。
- `KnowledgeManager`：知识、证据与跨轮快照。
- `TimeManager`：时间倍率、时钟、低潮/入口标志、NPC 日程和循环事件。
- `DialogueManager`：选项开放、NPC 动作、本地自由文本动作、显影和身份定影。
- `AudioManager`：程序化音频合成和声音设置。
- `SceneManager`：portal 可见性、旅行时间、目标场景与 spawn。
- `GameManager`：全局状态、初始化/归一化、日志、维修、循环、结局和保存。

Autoload 之间用 `EventBus` 通知；没有场景脚本反向持有 UI 单例，避免场景/数据循环依赖。

## JSON 处理

原 `data/world.json` 和 `data/maps.json` 逐字节复制至 `godot/data/`，静态内容从 `res://data/` 读取。`DataManager` 对根类型、schemaVersion、核心字段、稳定 ID、重复 ID、关键 NPC/地点、portal 目标与 spawn 做检查，并建立 NPC/物品/证据/场景字典索引。运行时状态不写回 `res://`。

玩家状态保存到：

```text
user://time-echo-save-v1.json
user://time-echo-endings-v1.json
```

## 浏览器 API 替代

| 浏览器 API | 替代 |
|---|---|
| fetch 静态 JSON | `FileAccess` + `JSON` |
| requestAnimationFrame | `_process` / `_physics_process` |
| key/pointer listeners | InputMap + `_unhandled_input` + Control signals |
| setTimeout | `await get_tree().create_timer()` |
| localStorage | `user://` JSON |
| Canvas 2D | `_draw` + Sprite2D + CharacterBody2D + Camera2D |
| Web Audio | AudioStreamGenerator |
| fetch NPC API | HTTPRequest |
| 宿主页 JS 能力 | JavaScriptBridge 可选钩子 |

## AI NPC 配置

API Key 不在 Godot 工程中读取、保存或发送给客户端。推荐继续使用原 `server.py` 作为同源代理。

桌面版可在启动 Godot 前设置兼容决策端点：

```powershell
$env:TIME_ECHO_AI_ENDPOINT='http://127.0.0.1:8000/api/npc/decide'
godot --path godot
```

服务端仍通过根目录 `.env`/环境变量读取 `OPENAI_API_KEY`、`OPENAI_BASE_URL`、`OPENAI_MODEL` 和 `OPENAI_REASONING_EFFORT`。Godot 不包含这些值。

Web 导出有两种路径：

1. 与原 `server.py` 同源托管时，自动使用 `window.location.origin + /api/npc/decide`。
2. 宿主页可选提供同步函数 `window.TIME_ECHO_GODOT_AI(payload)`，返回 JSON 字符串；`WebAIProvider` 会通过 `JavaScriptBridge` 调用。

两者都不可用时自动回退 `LocalAIProvider`，固定对话、谜题和两个结局仍完整可玩。

## 启动方式

编辑器：

1. 使用 Godot 4.6 打开 `godot/project.godot`。
2. 等待约 193 张运行时/源图片首次导入；本机 Godot 4.6.3 首次增量导入 147 张源图约 13 秒。
3. 按 F6/F5；主场景已配置为 `res://scenes/main/main.tscn`。

命令行：

```powershell
godot --path godot
```

导入/解析检查：

```powershell
godot --headless --path godot --editor --quit
godot --headless --path godot --quit-after 10
godot --headless --path godot res://tests/test_runner.tscn
```

静态检查（不需要 Godot）：

```powershell
python godot/tests/validate_project.py
```

## Web 导出

1. 在 Godot 4.6 安装匹配的 Web 导出模板。
2. Project → Export → Add → Web。
3. 使用兼容性渲染器；工程已配置 `gl_compatibility`。
4. 导出到新的发布目录，不覆盖根目录浏览器版。
5. 通过 HTTP(S) 服务，不要双击导出 HTML。
6. 在线 NPC 需要与 `/api/npc/decide` 同源，或配置上述宿主页桥接；否则使用离线规则。

## 验证状态

已执行：

- `Godot_v4.6.3-stable_win64_console.exe --version`：`4.6.3.stable.official.7d41c59c4`。
- Godot 编辑器导入/解析：退出码 0；首次发现的 `knowledge_manager.gd` 缩进错误已修复，复测无 Parser Error。
- Godot 项目内测试场景：59/59 通过，覆盖原核心循环、四张表面纹理导入与主场景非空节点树。
- Godot 主场景 headless 启动：退出码 0，无 Invalid access、缺失节点或缺失资源错误。
- Godot Movie Writer 真实 OpenGL 视觉烟雾测试：NVIDIA Compatibility 渲染器以 1152×648 输出 7 帧，退出码 0；最终帧为 `tests/render/town_square_v300000006.png`。截图目录用 `.gdignore` 排除运行时导入。
- 全地图真实渲染：`map_gallery.tscn` 逐一加载 18 个 JSON 地点并等待 GPU `frame_post_draw`，输出 18 张 1152×648 PNG、3 张六宫格总览和 JSON 索引；`maps_v2` 最终批次 18/18、0 失败。
- 147/147 张 `art/` 图片镜像一致性计数；复制完成时旧 `.import` 数量为 0，随后 Godot 4.6.3 生成 147 个指向当前 `res://assets/images/source_art/` 的新旁车，四类表面纹理均成功导入。
- 原仓库 `python -m unittest discover -s tests`：45/45 通过，证明原内容/服务契约未被迁移操作破坏。
- 原 JSON 与复制 JSON 的内容一致性检查。
- UTF-8 读取检查。
- `.gd`、`.tscn`、`project.godot` 中静态 `res://` 引用存在性检查。
- JSON 解析、18 个 scene ID、7 个 NPC ID、全部 portal 目标与 spawn 检查。
- InputMap、主场景和关键图片存在性检查。
- Python 静态验证脚本。

静态验证覆盖 `39 source/scene files, 18 scenes, 7 NPCs`；`world.json` 与 `maps.json` 的源/副本 SHA-256 均一致。完整最终复测结果以本报告最后一次命令行为准。

## 已知差异/问题

- 图片首次导入会有等待时间；透明 WebP 均来自原 `art/runtime`，`source_art/` 额外保留生成源稿，导出包可按发行需求排除未引用概念图以减小体积。
- 字体依赖 Godot 的系统中文回退；不同平台字形和换行可能略有差异。
- 屏幕截图不会与原 3000 行 Canvas 渲染器逐像素一致，但原图片、地图坐标、调色板、碰撞和剧情可达性均保留。
- NPC 目标移动未复刻原 Canvas A* 网格绕障动画；其工作地点、时间表和交互点保持一致。
- 在线 AI 兼容原服务契约，但网络错误会无提示降级到本地规则，以保证可玩性。
- 当前视觉回归只覆盖 Windows/OpenGL Compatibility 的广场首帧；其他 17 个地点、窗口缩放和目标平台字体仍保留人工视觉验收项。
