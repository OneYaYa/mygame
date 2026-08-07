# Blindspot Relay

 Blindspot是一个单人对话解密游戏。玩家是远程调度员，掌握 K-17 设施的全局遥测；受困技术员只知道当前房间里能亲眼确认的事。玩家需要通过文字中继交叉核对两边的信息，向他下达单步指令并授权执行，最终恢复电网与冷却回路并撤离。

这个版本专门按独立开发范围收敛：仅使用一张男性肩部以上的透明像素角色底图；五个房间背景、角色动画、视频信号效果和状态反馈都由 Godot 绘制代码实时生成，因此增加房间或状态时不需要重画完整动画帧。

## 已实现

- 1 名 NPC、5 个房间、8 类动作、氧气与电力两项资源
- 单格携带槽、模块化电网匹配与冷却压力谜题、危险操作单次明确确认
- 相位保险芯完整修复、应急电芯代价旁路、便携氧气罐三种资源路线选择
- 正常成功、代价成功、失败三类结局和一键重开
- 完整本地规则回复；不启动网络服务也能通关
- 可选 OpenAI `gpt-5.6-luna` 对话与候选动作
- 谜题线索拆分为调度员独占遥测与 NPC 当前房间的局部观察
- 不显示完整动作清单；明确自然语言指令只生成一个待授权候选
- 左侧 `NEXT` 按权威任务状态给出当前目标和输入示例，跳过关键步骤或抵达中央舱时会提供纠偏与双路线说明
- 输入框上方提供随阶段更新的关键词名片；点击只插入术语，玩家仍可编辑完整指令并自主发送
- 右侧快捷交流只显示宽泛意图，点击后再发送对应的自然问句
- 远程画面随 NPC 所在房间切换，并带像素化转场
- 首次启动包含约 4 秒的中继抢接动画：冷启动、信号丢失、重试、横向闪断、轻微震动和最终锁定
- 开场期间拦截输入，可用 Enter、Space、Escape 或鼠标点击跳过；任务重开不会重复播放
- 呼吸、负伤、紧张、低氧、通讯、等待授权、操作成功/失败与终局均有动态视觉反馈
- 电网恢复、泄漏封闭和逃生舱解锁会直接改变对应房间的灯光与环境特效
- 林岚始终用受困者的口语回应，不会说出“白名单、候选、授权、目标 ID”等界面或实现术语
- 模型只读取 NPC 的局部投影，只能从当前动作白名单中提议
- 独立上下文编译器先按 NPC、房间、任务和启用动作做硬过滤，再按角色/场景/信念/记忆/导演分区装箱
- 亲眼事实、调度员说法和主观记忆均带稳定来源 ID；模型返回实际引用 ID，服务端生成可回放 Prompt hash
- 世界状态始终由 Godot 本地核心验证和修改
- 玩家自述的时间跳跃不会被当成世界事实；本地与在线 NPC 都会拒绝“过了一年”等无依据叙述并保持当前位置
- 最近 10 条玩家/NPC 对话、本地姓名/承诺记忆、信任、恐惧与信念状态
- 信任与恐惧会影响危险操作意愿；安抚可准备聚焦细扫，连续纯对话会推进通讯耗氧周期
- 可点击的远端/现场双轨线索工作台，帮助玩家自己拼合证据而不自动给出答案
- 否定、条件、疑问和含糊指令不会生成可执行候选
- 程序化无线电环境音、移动/检查/危险/成功事件音效
- 字号、音量、静音、减少动态、在线/本地模式、安全动作 Enter 快速授权设置与窄屏布局
- 房间前景遮挡、现场特写框、信任/恐惧姿态和压力调节视觉反馈
- 在线失败两次后自动熔断 30 秒；等待期间可以取消
- 本地代理限制浏览器 Origin、按来源限流并通过 `/health` 提供无敏感信息的运行指标

## 直接运行

用 Godot 4.6 或更高版本打开 `project.godot`，运行主场景即可。命令行示例：

```powershell
& "C:\Users\ethanypan\Desktop\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe" --path .
```

不启动 Python 服务时，输入文字会自动使用本地 NPC 规则。离线解析支持房间名、颜色、路线物品以及 I/B/P 压力调节器等中文目标别名，因此离线模式仍包含完整玩法。含糊的“接一根线”或“调一个阀”会被要求澄清，不会替玩家猜答案。

操作：

- 鼠标：选择快捷询问、发送文本、授权或拒绝单个行动候选
- 关键词名片：点击将难输的设施、物品或接头名称插入输入框，不会自动发送
- `Enter`：发送输入；输入框为空且存在安全候选时快速授权
- `Ctrl+T`：聚焦输入框
- `Ctrl+R`：确认后重新开始任务
- 右上角 `SETTINGS`：调整字号、音频、动态效果和在线 AI 模式

## 启用 gpt-5.6-luna

API Key 只保存在本机 Python 进程中，不会进入 Godot 客户端或提交到版本库。

```powershell
Copy-Item .env.example .env
# 编辑 .env，填入 OPENAI_API_KEY
python server.py
```

然后正常启动 Godot。客户端默认请求 `http://127.0.0.1:8787/api/npc/decide`。项目也会在项目级 `.env` 缺失时读取上一层工作区已有的 `.env`，但独立发布时建议使用项目自己的配置。

代理使用 OpenAI Responses API、低推理强度和严格 JSON Schema。输出固定为：

```text
reply / intent / action / target / mood / referenced_ids
```

任何不存在的动作、错误目标或失效候选都会在 Python 和 Godot 两层被降级或拒绝。网络失败、超时或返回异常时，客户端自动切换到本地规则。

对话历史由游戏本地显式管理，Responses API 请求保持 `store: false`。详见 `docs/AI_AND_PRIVACY.md`。

## 架构

```text
玩家文本 ──> gpt-5.6-luna / 本地回复规则
                 │
                 └──> 角色回复 + 最多一个白名单候选
                                      │
                                  玩家授权
                                      │
                                      v
                           MissionSimulation.propose()
                                      │
                         ┌────────────┴────────────┐
                      安全动作                 危险动作
                         │                 候选卡明确确认
                         └────────────┬────────────┘
                                      v
                              更新权威状态与结局
```

在模型调用之前，`NpcContextCompiler` 会把权威模拟器给出的局部投影编译为六个独立预算区：角色与场景、已知信念、主观记忆、关系、导演意图和最近对话。未验证的调度员读数不会升级成世界事实；每轮 trace 只进入本地调试环，不进入角色 Prompt。模型返回后还有一层确定性质量门，拦截虚假通信故障话术、已确认事实遗漏和引用事实矛盾，并把触发原因写入 `quality_guard`。详见 [AI NPC 技术升级说明](docs/AI_NPC_TECH_UPGRADE.md)。

关键文件：

- `scripts/core/mission_simulation.gd`：权威状态机、关系机制、资源与结局
- `scripts/core/puzzles/power_routing_puzzle.gd`：电网读数谜题模块
- `scripts/core/puzzles/coolant_pressure_puzzle.gd`：可逆压力调节谜题模块
- `data/mission.json`：房间、物品、资源成本和任务数据
- `scripts/main.gd`：核心、UI、NPC 服务之间的唯一编排层
- `scripts/services/npc_decision_service.gd`：HTTP、白名单过滤和本地降级
- `scripts/services/npc_context_compiler.gd`：最小权限过滤、上下文分区、场景模式、导演意图与 trace
- `scripts/services/procedural_audio.gd`：运行时生成无线电环境音与事件提示音
- `scripts/ui/mission_console_ui.gd`：纯代码终端界面
- `scripts/ui/signal_boot_overlay.gd`：全屏中继抢接、信号闪断与震动开场
- `scripts/ui/npc_portrait.gd`：五个像素房间、转场和状态动画渲染器
- `assets/portraits/lin_lan_male_pixel.png`：林岚的男性肩部以上透明像素角色底图
- `server.py`：不向客户端暴露密钥的本地 OpenAI 代理

## 测试

```powershell
python -m unittest discover -s tests/python -v

$godot = "C:\path\to\Godot_v4.6.3-stable_win64_console.exe"
& $godot --headless --path . --editor --quit
& $godot --headless --path . res://tests/godot/mission_simulation_test.tscn
& $godot --headless --path . res://tests/godot/main_integration_test.tscn

# 可选：生成五个房间和五种角色状态的视觉对照图
& $godot --path . res://tests/godot/pixel_scene_visual_test.tscn
# 可选：生成主控制台与已拼合线索工作台截图
& $godot --path . res://tests/godot/main_visual_test.tscn
```

启动 `python server.py` 后还可以运行真实在线链路测试；这会产生一次 API 调用：

```powershell
& $godot --headless --path . res://tests/godot/online_service_test.tscn
```

当前验证基线：Python 22 项测试通过；Godot 核心 206 项检查通过；Godot 主流程集成 83 项检查通过；当前配置下的 `gpt-5.6-luna` 在线冒烟会返回真实 NPC 回复，姓名记忆通道也已验证。重新部署或更换模型后仍应再运行一次在线测试。

## 通关方法（答案每局变化）

先检查中继控制室的遥测台。完整修复路线需要带上相位保险芯，前往主电网舱检查三只接头，把现场读数与远端闭环读数拼合；也可以在中央交汇舱改拿应急旁路电芯，跳过接头谜题换取必然的代价撤离。便携氧气罐可留到返程时补气，但同样占用唯一携带槽。电网恢复后拿起低温密封剂，前往冷却回廊：远端给出当前与目标压力，林岚读取 I/B/P 三只调节器各自的增减量，玩家需要组合出目标值。压力锁定并密封裂口后即可前往逃生舱。重开任务会生成新的线路读数、压力标定和事故签名。

## 导出 Windows 构建

项目提供一键发行脚本。它把 Godot 4.6.3 GUI 运行时、编译后的 PCK、Python AI
代理和自动进程管理启动器封装到同一个 ZIP；玩家解压后只需双击
`BlindspotRelay.exe`，不需要安装 Godot、Python 或运行库。

```powershell
python -m pip install --user pyinstaller
& .\packaging\build_windows_release.ps1 -EmbedApiCredential
```

产物写入 `build/releases/BlindspotRelay-Windows-v0.4.0.zip`。加入
`-EmbedApiCredential` 会把当前 `.env` 配置打进本地代理，满足小范围测试玩家
解压即用在线 AI；桌面程序中的密钥仍可能被提取，因此公开发行不得使用个人或
高额度 Key，应改用带鉴权、TLS、限流和账单告警的托管代理。详见
`packaging/DISTRIBUTOR_SECURITY_NOTICE.md`。

对最终 ZIP 执行隔离解压、文件哈希、真实在线对话、入口启动和进程清理测试：

```powershell
python .\packaging\smoke_test_release.py .\build\releases\BlindspotRelay-Windows-v0.4.0.zip
```

不加 `-EmbedApiCredential` 时不会内置 `.env`，全部玩法仍可使用本地 NPC 完整
通关。正式发布前请逐项完成 `docs/RELEASE_CHECKLIST.md`。
