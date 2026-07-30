# P0 Batch 01 标杆地图接入复核

复核日期：2026-07-30

## 最终结论：VISUAL_REJECTED（已由高影响垂直切片复核取代）

本文件保留上一轮低覆盖接入的真实记录，但其视觉结论已按后续 before/after 人工复核撤销。新的独立地图结论与证据见 `P0_VISUAL_IMPACT_REVIEW.md`；不能引用本文件的旧结论作为推广依据。

这不是对八套图集整体推广的批准。草地、水面底纹和暖旅店墙体在三个标杆地图中明显优于旧回退；石路与草侵入只能限量使用；`natural_shoreline_set` 在真实 town/harbor 岸线上试铺后出现离散深色水条，且多枚角块包含纯黑伪影，已从最终可见层撤回。修复指定岸线格并重新做标杆截图前，不得推广到其余 15 张地图。

## 三张标杆地图

### town

- 使用 `grass_base_variants`：固定 seed、10% 常规变化、17% 地图边缘变化，建筑/道路邻近格不放变化。
- 使用 `stone_path_corner_set`：仅钟塔前庭、面包店门台和装订店门台；旧程序化四向主路保留，避免高频石纹铺满画面。
- 使用 `grass_path_edge_set`：只在小型石台边缘以固定 seed 稀疏侵入。
- 使用 `water_shallow_deep_set`：加载地图时一次性合成世界坐标纹理，再由原 `town_pond` 自然多边形裁切；高光比率 4.5%。
- `natural_shoreline_set`：草岸直边真实试铺产生与多边形错位的深色条带，最终改回连续低对比程序化岸边；语义和资源路径仍校验。
- 建筑、portal、出生点、碰撞和交互矩形未改。

### harbor

- 使用 `grass_base_variants`：固定 seed，普通变化 8%、地图边缘 14%。
- 使用 `water_shallow_deep_set`：大面积连续水纹以深水为主，边界采浅水，高光比率 5.5%，世界坐标固定。
- 使用 `stone_path_corner_set` 与 `grass_path_edge_set`：仅港务楼前的小型后勤台；原道路和码头结构保留。
- `natural_shoreline_set`：泥岸直边在弯曲岸线上形成离散深色竖条，石岸多枚格含黑像素；最终保持连续程序化岸线和灯塔岛回退。
- 码头下增加 1 px 接触暗线；船只、渡船、洞穴、灯塔和 NPC/交互语义未改。

### inn-lobby

- 仅使用 `inn_warm` 主题的 `interior_wall_modular_set`、`interior_corner_set`、`baseboard_set`。
- 顶墙混排安静、密面板和轻面板，轻微降亮以避免压过家具。
- 左右 48×48 内角固定在非 Y-sort 墙体层。
- 上墙墙脚线连续；下墙分成左右两段，在入口门洞显式中断并使用止口。
- `door_compatible` 对齐 `lobby_to_yard`，portal 触发矩形与碰撞仍由玩法数据管理。
- 接待区、壁炉区、入口区、后勤区和家具 Y 排序未改。

## 截图依据

- before：`res://art_review/p0_batch_01_before/01_town.png`、`06_harbor.png`、`08_inn-lobby.png`
- after：`res://art_review/p0_batch_01_after/01_town.png`、`06_harbor.png`、`08_inn-lobby.png`
- 局部：after 目录内 `town_path_closeup.png`、`town_pond_closeup.png`、`harbor_shore_closeup.png`、`harbor_water_closeup.png`、`inn_wall_corner_closeup.png`、`inn_doorway_closeup.png`
- 对照表：`res://art_review/p0_batch_01_contact_sheet.png`

截图的 nearest 局部图来自最终 Godot 兼容渲染截图，不是重绘或伪造。首轮失败试铺保存在 `p0_batch_01_after_draft/`、`p0_batch_01_after_draft_2/`、`p0_batch_01_after_draft_3/`，用于证明撤回岸线和缩小石路范围的依据。

## 成功项与限制

- 成功：草地大面积无明显 4×4 棋盘；变化不是每次加载随机。
- 成功：水面连续、世界坐标固定、无网格黑缝；town 池塘保留自然轮廓。
- 成功：inn-lobby 顶墙厚度、墙角、墙脚线和门洞比旧盒状 shell 清楚。
- 限制：水图集没有浅深过渡专格，当前用边界浅水/内部深水加多边形裁切缓和，而非虚构 terrain 索引。
- 限制：石路 `t_junction`/`cross_junction` 的可走带过窄，主路禁用。
- 限制：墙体每 32 px 有竖框节奏，推广时需要按房间人工混排，不可机械重复。
- 阻止推广的问题：岸线索引 `5,7,9,10,11,16,17,19,21,23,24,25,28,29,30,31,32,33,34,35` 需要重绘/清理黑像素，并提供适配自然多边形的过渡策略。

## 测试记录

- `python godot/tools/prepare_generated_tiles.py --validate`：通过。
- `python godot/tools/process_art_assets.py --validate`：通过。
- `python godot/tools/build_p0_batch_01_review.py --validate`：13 个审查图片通过尺寸/可读校验。
- `python godot/tests/validate_project.py`：48 个脚本/场景源、18 张地图、7 个 NPC，0 failures。
- Godot 4.6.3 editor import（headless）：通过，无 Parser Error。
- `res://tests/test_runner.tscn`：177 checks，0 failures。
- `res://tests/test_runner.tscn -- --save-io-test`：182 checks，0 failures；真实写入、读取并清理隔离存档目录。
- 正式项目主场景 headless `--quit-after 10`：退出码 0。
- OpenGL 3.3 Compatibility gallery：3 maps，0 failures；真实设备为 NVIDIA GeForce RTX 2060。
- 最终 gallery 指标：town 2637 个静态生成格、5/5 portal 可达；harbor 2898 个静态生成格、3/3 portal 可达；inn-lobby 67 个静态生成模块、2/2 portal 可达；三图均为 0 asset errors、0 warnings。

测试过程中曾真实出现 21 个失败：侵入格使用了 `intrusion_north` 等错误名称，导致目录错误在后续地图沿用。现已改为 `intrusion_n/e/s/w` 语义并重跑至 0 failures；失败没有被隐去或当作通过。

## 推广门槛

1. 修复 `natural_shoreline_set` 的黑像素和角块闭合。
2. 在 town 池塘、harbor 主岸、灯塔岛分别重新试铺并生成相同局部截图。
3. 若继续使用 stone T/十字路口，需重绘到角色可读宽度；否则明确永久禁用。
4. 通过以上复核后，才可按地图逐张推广；本轮其余 15 张地图保持原布局和程序化回退。
