# 美术集成报告

## 唯一事实来源

正式运行只读取 `godot/data/maps.json`、`godot/data/world.json`、`godot/data/art_manifest.json` 和 `godot/data/art_layouts/`。仓库根目录浏览器数据与运行时代码没有被修改，也没有被 Godot 运行时引用。

## 渲染架构

- `location_runtime.tscn` 明确分为 Background、Ground、ArchitectureBack、WallDecorations、WorldObjects、Characters、ArchitectureFront、Foreground、Lighting、WeatherAndParticles、InteractionHints、DebugOverlay 与 Camera2D。
- `ArtObject2D` 将 Visual、ForegroundVisual、ContactShadow、CollisionBody、InteractionArea、EntranceMarker、NavigationObstacle 与 DebugOverlay 分离；正式碰撞由 WorldController 根据独立 `collision_rects` 构建。
- 逻辑交互/portal 通过稳定 gameplay ID 读取 `interaction_rect` 或 `trigger_rect`，不再把旧 x/y/w/h 当成 sprite、阴影、碰撞和入口的共同事实。
- 地面、水面、道路、room shell 与程序化家具由低噪声像素绘制；随机细节使用 map ID 和坐标固定 seed。水面高光使用世界坐标，正式 debug 默认关闭。
- 建筑、树、船和大型家具使用无模糊接触阴影；室内灯、路灯、壁炉、控制台和安全灯使用 CanvasModulate 与轻量 PointLight2D，兼容 GL Compatibility/Web 渲染器。

## 18 张地图的完成内容

| 地图 | 本轮正式布局 |
|---|---|
| town | 主钟缩放为完整视口中心，新增基座、台阶、四向连续道路、面包店/装订店前庭、公共长椅、花坛与自然池岸。 |
| inn-yard | 旅店主楼、门前平台与灯光成为中心；菜圃和木屋后勤区分侧布置，池岸、长椅、推车、桶箱形成生活分区。 |
| chapel-hill | 单一礼拜堂中心、短仪式路与台阶；纪念花地、少量长椅、落石、树与受控旗帜打破镜像对称。 |
| photo-lane | 相馆与相框店围成窄街；展架、相框、招牌和货箱聚成手工业组，并保留通向档案坡道和暗房线索。 |
| archive-lane | 档案馆门前台阶、连续抬升坡道和卷宗运输组建立行政秩序；无剧情池塘缩小，旧测试色块已移除。 |
| harbor | 连续深浅水区、岸线、陆地—码头—泊位动线完成；港务楼、灯塔、船/渡船、绳网桶箱和隐蔽洞口按航运功能组织。 |
| player-room | 暖木 room shell；床靠墙，壁炉、日志桌、照片、储物角和入口留白形成私人房间。 |
| inn-lobby | 接待柜台、钥匙/公告、壁炉休息区、组合桌椅、楼梯和后勤角形成清晰服务动线。 |
| inn-upstairs | 缩成狭长走廊；房门按节奏排列，长条地毯和壁灯引导八号房异常，NPC 日程点不阻塞通道。 |
| clock-cabin | 工程木/石地面；工作台、控制台、工具架、材料箱和中央维修区组成工作流。 |
| chapel-interior | 冷石 room shell、仪式中轴、少量长椅与六锤机构结合，钟绳和冷暖灯区分宗教与机械层。 |
| chapel-belfry | 收窄可走木台，以梁柱、悬绳、工具与第七锤为中心，取消大地毯并强化高处暗边。 |
| photo-studio | 灰蓝/暗木前厅展示区和后部摄影工作区分开；照片、展架、工作台和暗门暗示形成显影流程。 |
| archive-room | 冷静 floor/wall 主题；不对称书架、服务台、中央阅览桌、卷宗箱和阅读灯构成查阅空间。 |
| harbor-control | 深木灰蓝 room shell；控制台、海图桌、记录区、信号装置和后勤角围绕值守工作流。 |
| low-tide-cave | 完全移除木地板，改为湿石、黑岩边界、不规则积水、安全维护通道、旧工具和隐藏底片角。 |
| clock-basement | 石质机械地面、唯一中央协议控制台、七个有序插槽、三信号灯及显著区分的红/白装置。 |
| hidden-darkroom | 深红棕/灰黑 room shell、安全红灯、少量显影家具和集中照片记录，以艾达为叙事视觉中心。 |

## 已集成资产

建筑：`env_master_clock_tower`、`env_bakery`、`env_bookbinder`、`env_lakeside_inn`、`env_inn_shed`、`env_chapel_tower`、`env_silver_salt_studio`、`env_frame_shop`、`env_town_archive`、`env_harbor_control`、`env_lighthouse_watchtower`。

地标：`lm_boat`、`lm_ferry`。

道具：`prop_banner`、`prop_barrel`、`prop_bed`、`prop_bench`、`prop_bush`、`prop_cart`、`prop_counter`、`prop_crate`、`prop_cratestack`、`prop_desk`、`prop_fireplace`、`prop_flowers`、`prop_frame`、`prop_grasstuft`、`prop_lantern`、`prop_net`、`prop_pebbles`、`prop_rack`、`prop_rope`、`prop_shelf`、`prop_sign`、`prop_tree`。普通桌、椅、长椅、齿轮、钟锤、控制台、显影台、信号和安全灯使用语义明确的程序化结构件。

角色：玩家与 Arthur、Beatrice、Conrad、Dorothea、Elias、Florence、Ada 均使用整数画布 processed sprite 和脚点 anchor。

## 2026-07-30：P0 第一批生成资产

新增 `grass_base_variants`、`grass_path_edge_set`、`stone_path_corner_set`、`water_shallow_deep_set`、`natural_shoreline_set`、`interior_wall_modular_set`、`interior_corner_set`、`baseboard_set`。共交付 16 个草 tile、16 个草路过渡、16 个石路拓扑、16 个深浅水 tile、36 个岸线模块、25 个直墙、20 个墙角和 25 个墙脚线模块。

原始图像生成母版位于 `source_art/generated/masters/`；经过色键去底、逐 cell 裁切、硬 alpha、限色和 nearest 处理后的规范 source 位于 `source_art/generated/`；Godot 运行图位于 `processed/`。`ArtCatalog` 现在校验 `tile_size`/`atlas_grid`，并通过 `get_atlas_tile(asset_id, index)` 返回 `AtlasTexture`，因此运行层不需要从文件名或固定像素坐标猜用途。

这批只建立可直接接入的正式图集与类型化 region 访问，未把 18 张地图一次性切换到未经 terrain 邻接审查的新 tile。建议按 town、harbor、player-room 三个既有样板逐图替换并保留程序化回退；这避免错误角块在全部地图扩散。完整规格与顺序见 `P0_BATCH_01_ASSET_SPEC.md`。

## 2026-07-30：P0 三图高影响垂直切片

- 只对 town、harbor、inn-lobby 启用高覆盖语义 Tile/room shell，其余 15 图保持原布局与程序化回退。
- 修复版 `natural_shoreline_set_v2.png`、`stone_path_corner_set_v2.png`、`water_shallow_deep_set_v2.png` 分别写入 `source_art/generated/` 与 `processed/`；原 batch-01 source 和 `masters/` 未覆盖。
- `art_manifest` 的稳定 asset_id 不变，runtime/source 路径升级为 `_v2`，并记录 `previous_source_path`、`repair_reference_path`、`source_generation_script` 与处理脚本。石路和水面因剩余 32px 模块节奏标记 `needs_review: true`；岸线闭合修复通过，`needs_review: false`。
- `TimeEchoArtTileLayerBuilder` 现在通过命名语义一次性构建静态深浅水、岸线、道路、结构墙与门洞；碰撞、交互范围和 portal 仍由稳定 gameplay 数据独立管理。
- 真实截图、差异率、局部最近邻检查与独立地图结论见 `P0_VISUAL_IMPACT_REVIEW.md`。批量推广保持关闭。

## concept_only 与 processed

- `prop_buckets`：实际画面是照片晾晒架而不是水桶，禁用，`concept_only`、`needs_review: true`。
- `time_echo_horizon`：只用于标题插图，`concept_only`，不作为地图 sprite。
- `spr_dorothea` 仍可运行，但源图透明像素比例异常，保留 `needs_review: true`。
- 47 个建筑、地标、道具、角色和表面资产已生成到 `assets/images/processed/`；标题插图沿用正式 runtime WebP，禁用的 `prop_buckets` 不生成输出。完整源路径、alpha bbox、原始/输出尺寸和粉色残留数位于 `processing_report.json`，源图未覆盖。

## UI 与开发工具

- HUD 从 70 px 常驻双行布局压缩为约 50 px 单行信息区；J/I 面板默认关闭，只以可关闭模态层打开。交互提示仅显示一个最近且最高优先级目标，位于底部居中。
- `res://scenes/tools/art_review.tscn` 可选择/重载全部 18 图，切换白天、黄昏、夜晚与 Art Debug；右侧报告资源失败、非整数/重叠警告、玩家出生点、NPC 日程点和逐 portal 可达性。
- F3 或启动参数 `--art-debug` 切换 bounds、anchor、collision、interaction、portal 与资源 ID；DebugOverlay 不参与正式视觉层。
- map gallery 支持 `--output-dir`、重复 `--map-id`、`--suffix`、`--time-of-day` 与 `--art-debug`。

## 实际验证结果

- 修改前：静态验证 0 失败；Godot test runner 59 checks / 0 failures；18 图 gallery / 0 failures。
- 修改后：静态验证 0 失败；Godot test runner 151 checks / 0 failures；隔离 `user://` 的真实存档写入/读取模式 156 checks / 0 failures；18 图 OpenGL gallery / 0 failures。
- 修改后画廊共实例化 268 个正式 art object、审计 34 个 portal；全部资源错误列表和布局警告列表为空，所有入口均可达。
- 18 张 after 图均为 1152×648，粉色残留为 0，且每一张都与 before 图像内容不同。
- 白天/夜晚、低潮/暗房、三钟、显影、四锚点、红/白结局、时间倍率/停时、跨循环、NPC 日程、离线 AI 与旧版本存档迁移均进入自动回归。

## 仍需人工美术生产

P0 是专用草/路边 tile、自然水岸、模块墙角/墙脚、普通桌椅、礼拜堂长椅、洞穴/地下室地面、门前平台与手绘阴影图集。当前程序化回退可公开检查且语义正确，但不能完全替代专职像素美术逐 tile 精修。P1/P2 的精确规格见 `missing_assets.json`。

已知限制：未实现可拖拽并回写 JSON 的可选 `@tool MapArtEditor`；Art Review 提供只读可视化审查。复杂 NPC 导航仍沿用现有移动模型，没有新增导航网格；本轮通过碰撞、出生点、NPC 日程点和 portal 网格连通审计避免新增阻塞。`spr_dorothea` 和禁用的 `prop_buckets` 仍建议人工复核源素材。
