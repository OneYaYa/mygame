# Full Map Art Integration Report

## 结论

剩余 15 张地图的正式 Godot 4.6 美术生产、接入、截图与功能回归已经完成。三张标杆地图 `town`、`harbor`、`inn-lobby` 未接入本批新资产，浏览器版文件未修改。

本批新增 178 个可追溯 `asset_id`：Batch A 31、Batch B 29、Batch C 42、Batch D 44、Batch E 32。生成 13 张原始母版、178 张透明规范化 source、178 张 processed 运行图，并新增 35 套命名语义图集。完整逐资产记录见 `assets/images/source_art/generated/full_map_asset_processing_report.json`，其中包含 asset_id、source/processed 路径、原生/显示尺寸、anchor、SHA-256、目标地图、接入状态、再生成状态和最终审查状态。

## 正式资产路径

- 母版：`res://assets/images/source_art/generated/masters/full_map_batch_*_master.png`
- 清键母版：`res://assets/images/source_art/generated/alpha_clean/full_map_batch_*_master.png`
- 规范化 source：`res://assets/images/source_art/generated/<asset_id>.png`
- processed：`res://assets/images/processed/<asset_id>.png`
- 生成提示与来源：`res://assets/images/source_art/generated/full_map_generation_prompts.json`
- 逐资产处理报告：`res://assets/images/source_art/generated/full_map_asset_processing_report.json`

13 张母版分别覆盖 inn-yard、player-room、inn-upstairs、chapel-hill、chapel-interior、chapel-belfry、photo/archive、clock-cabin、harbor-control、clock-basement、low-tide-cave 和 hidden-darkroom 家族。全部透明边缘使用硬 alpha，未检测到洋红/绿色键残留、空图或重复 ID；运行图保持整数尺寸与 nearest 导入。

## 数据与运行时接入

- `map_asset_dependencies.json` 是 15 图/178 资产的机器可读依赖矩阵。
- `art_manifest.json` 从 75 项扩展到 253 项；所有新增项包含 source、processed、尺寸、anchor、hash、批次与目标地图。
- `art_atlas_semantics.json` 从 10 套扩展到 45 套；新增 35 套图集均使用命名 Tile，不依赖地图侧魔法索引。
- `missing_assets.json/full_map_rollout` 标为 `completed`，`needs_review` 为空。
- 15 个 `data/art_layouts/*.json` 已写入正式地板、墙体、道路、道具、灯光、遮挡层、Portal/交互视觉位置和固定 seed；原 gameplay ID、目标地图 ID 与传送逻辑保留。
- `art_tile_layer_builder.gd` 支持命名 atlas 的 `floor_fills`、GroundDetails 与 ForegroundTiles。
- `world_view.gd` 增加自然洞穴边界绘制，使 `low-tide-cave` 不再依赖矩形 room shell。

## 逐图主要变化

| 地图 | 主要美术与关卡变化 |
|---|---|
| inn-yard | 旅店入口平台成为中心；菜园、洗衣、水泵、池塘与后勤形成分区，路径和围栏不再是调试线。 |
| player-room | 正式床边桌、衣柜、洗脸架、行李、照片板、日志桌和地毯形成睡眠/记忆/储物三组。 |
| inn-upstairs | 七扇房门、八号异常、长跑毯、壁灯、楼梯平台与端窗建立安静走廊节奏。 |
| chapel-hill | 礼拜堂和仪式石阶成为唯一中心，墓石、枯花、烛台、低墙与树丛建立纪念地身份。 |
| chapel-interior | 六锤装置、支撑架、钟绳、祭坛、长椅和中轴跑毯构成可读的仪式机械厅。 |
| chapel-belfry | 第七锤及基座成为中心，梁架、垂绳、检修平台、工具和高窗明确垂直空间。 |
| photo-lane | 相馆与装裱店由灰石街连接，增加橱窗、招牌、框箱、户外晾架和边界细节。 |
| photo-studio | 大画幅相机、背景、双灯、座椅、工作台、显影台、药盘、晾片线组成完整摄影流程。 |
| archive-lane | 抬高入口、台阶、低栏杆、文件车、封箱和入口灯形成市政后勤坡道。 |
| archive-room | 服务柜台、查阅桌、索引柜、档案柜、地图和记录板建立有序查阅关系。 |
| clock-cabin | 三齿轮校准装置居中，工作台、蓝图桌、控制板、管线与工具形成维修闭环。 |
| harbor-control | 海图桌、信号台、观测窗、仪表/拉杆/电报/无线电形成港务控制流程。 |
| clock-basement | 房间尺度协议平台、七见证槽、红白机制、三色灯与中央控制台取代 UI 式块面。 |
| low-tide-cave | 非矩形天然洞壁、湿石、浅池、腐木路、锈工具和旧维护装置建立退潮洞穴路线。 |
| hidden-darkroom | 银盐门框、局部红安全灯、Ada 焦点、未完成肖像、显影与晾片区建立叙事中心。 |

## 审查与资产处置

- 被拒绝母版：0。
- 重新调用图像生成：0；13 张首轮母版均在人工审查后保留。
- 程序化像素修正：硬 alpha 清键、限制色板、图集语义化、低石墙/道路对比和接触阴影修正。
- `needs_review` 资产：0。
- 未把低质量结果强行替换现有回退。

## 真实运行验证

- `prepare_generated_tiles.py --all/--validate`：通过。
- `prepare_full_map_assets.py --all --validate`：178 source、35 atlas、0 needs_review，通过。
- `rollout_full_map_layouts.py --validate`：178/178 已引用，通过。
- `process_art_assets.py --all --remove-pink/--validate`：通过，键色残留 0。
- `validate_project.py`：48 个源码/场景文件、18 场景、7 NPC、0 失败。
- Godot editor import：通过，无 Parser Error、资源缺失或 AtlasTexture 越界。
- `test_runner.tscn --save-io-test`：215 checks、0 failures。
- 正式 `main.tscn` headless：退出码 0。
- `visual_smoke.tscn`：OpenGL 3.3 Compatibility / RTX 2060，退出码 0。
- `map_gallery.tscn`：18 maps、0 failures。

运行时测试覆盖玩家移动、NPC 移动/调度、NPC 对话规则、全部 Portal 目标/出生点/可达性、碰撞、Y 排序、存档/读档、旧存档迁移、时间循环、低潮/暂停时间、照片显影、四锚点、表结局与真结局。项目 desktop/mobile 渲染方法均保持 `gl_compatibility`；仓库无 Web export preset，因此 Web 验收采用正式 GL Compatibility 设置与真实 Compatibility 运行烟测，不虚构未生成的 Web 导出包。

## 截图证据

- 修改前：`res://art_review/full_map_rollout/before/`
- 修改后：`res://art_review/full_map_rollout/after/`
- 最终 18 图、36 张 nearest 2× 局部图和 Contact Sheets：`res://art_review/full_map_rollout/final_gallery/`
- 测试原始日志：`res://art_review/full_map_rollout/test_logs/`

冻结回归：`inn-lobby` 前后逐像素一致；`town` 的 1.8832% 差异仅在底部动态交互提示框；`harbor` 的 0.1037% 差异仅在 25×47 动态水面/船体帧。三张冻结布局 JSON 和正式资产引用均未修改，判定无场景美术回归。详细 SHA-256、差异框和分类见 `final_gallery/review_manifest.json`。
