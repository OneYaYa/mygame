# Blindspot Relay

 Blindspot是一个已经可以从头玩到结局的 Godot 4.6 单人原型。玩家是远程调度员，掌握 K-17 设施的全局遥测；受困技术员林岚只知道当前房间里能亲眼确认的事。玩家需要通过文字中继交叉核对两边的信息，向他下达单步指令并授权执行，最终恢复电网与冷却回路并撤离。

这个版本专门按独立开发范围收敛：仅使用一张男性肩部以上的透明像素角色底图；五个房间背景、角色动画、视频信号效果和状态反馈都由 Godot 绘制代码实时生成，因此增加房间或状态时不需要重画完整动画帧。

## 已实现

- 1 名 NPC、5 个房间、8 类动作、氧气与电力两项资源
- 单格携带槽、两道每局随机化的信息拼合谜题、危险操作单次明确确认
- 正常成功、代价成功、失败三类结局和一键重开
- 完整本地规则回复；不启动网络服务也能通关
- 可选 OpenAI `gpt-5.6-luna` 对话与候选动作
- 谜题线索拆分为调度员独占遥测与 NPC 当前房间的局部观察
- 不显示完整动作清单；明确自然语言指令只生成一个待授权候选
- 右侧快捷交流只显示宽泛意图，点击后再发送对应的自然问句
- 远程画面随 NPC 所在房间切换，并带像素化转场
- 首次启动包含约 4 秒的中继抢接动画：冷启动、信号丢失、重试、横向闪断、轻微震动和最终锁定
- 开场期间拦截输入，可用 Enter、Space、Escape 或鼠标点击跳过；任务重开不会重复播放
- 呼吸、负伤、紧张、低氧、通讯、等待授权、操作成功/失败与终局均有动态视觉反馈
- 电网恢复、泄漏封闭和逃生舱解锁会直接改变对应房间的灯光与环境特效
- 林岚始终用受困者的口语回应，不会说出“白名单、候选、授权、目标 ID”等界面或实现术语
- 模型只读取 NPC 的局部投影，只能从当前动作白名单中提议
- 世界状态始终由 Godot 本地核心验证和修改
- 最近 12 条玩家/NPC 对话、本地姓名/承诺记忆、信任、恐惧与信念状态
- 否定、条件、疑问和含糊指令不会生成可执行候选
- 程序化无线电环境音、移动/检查/危险/成功事件音效
- 字号、音量、静音、减少动态、在线/本地模式设置与窄屏布局
- 在线失败两次后自动熔断 30 秒；等待期间可以取消
- 本地代理限制浏览器 Origin、按来源限流并通过 `/health` 提供无敏感信息的运行指标

## 直接运行

用 Godot 4.6 或更高版本打开 `project.godot`，运行主场景即可。命令行示例：

```powershell
& "C:\Users\ethanypan\Desktop\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe" --path .
```

不启动 Python 服务时，输入文字会自动使用本地 NPC 规则。离线解析支持房间名、颜色、物品以及 I/B/P 阀门等中文目标别名，因此离线模式仍包含完整玩法。含糊的“接一根线”或“先开一个阀”会被要求澄清，不会替玩家猜答案。

操作：

- 鼠标：选择快捷询问、发送文本、授权或拒绝单个行动候选
- `Enter`：在输入框中发送
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
reply / intent / action / target / mood
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

关键文件：

- `scripts/core/mission_simulation.gd`：权威状态机和谜题
- `data/mission.json`：房间、物品、资源成本和任务数据
- `scripts/main.gd`：核心、UI、NPC 服务之间的唯一编排层
- `scripts/services/npc_decision_service.gd`：HTTP、白名单过滤和本地降级
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
```

启动 `python server.py` 后还可以运行真实在线链路测试；这会产生一次 API 调用：

```powershell
& $godot --headless --path . res://tests/godot/online_service_test.tscn
```

当前验证基线：Python 15 项测试通过；Godot 核心 163 项检查通过；Godot 主流程集成 68 项检查通过；当前配置下的 `gpt-5.6-luna` 在线冒烟已返回合法动作，姓名记忆通道也已验证。重新部署或更换模型后仍应再运行一次在线测试。

## 通关方法（答案每局变化）

先检查中继控制室的遥测台并拿上相位保险芯。前往主电网舱，让林岚检查三只接头的现场读数，把它们与本轮调度端要求的闭环读数对照，再明确点名颜色。恢复电网后拿起低温密封剂，前往冷却回廊；把林岚报告的 I/B/P 管路映射与调度端“来流→回环→排气”阶段记录对照。密封裂口后返回中央交汇舱并前往逃生舱。重开任务会生成新的事故签名和答案，旧答案不能复用。

## 导出 Windows 构建

安装 Godot 4.6 导出模板后：

```powershell
& $godot --headless --path . --export-release "Windows Desktop"
```

产物写入 `build/windows/BlindspotRelay.exe`。正式发布前请逐项完成 `docs/RELEASE_CHECKLIST.md`。
