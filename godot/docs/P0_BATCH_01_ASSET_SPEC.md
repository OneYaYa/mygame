# P0 第一批基础图集规格

生成日期：2026-07-30。生成范围只包含 P0-A、P0-B、P0-C；未开始 P1/P2。

> 本文记录生成时规格。真实像素复核后的方向限制、索引修正和禁用格以 `P0_BATCH_01_VISUAL_AUDIT.md` 与 `res://data/art_atlas_semantics.json` 为准；尤其不要依据本页的早期“可镜像”说明变换边缘或岸线格。

## 交付规格

| asset_id | category | intended maps | source / processed canvas | module display | anchor / sort anchor | mirror | shadow | form |
|---|---|---|---:|---:|---|---|---|---|
| `grass_base_variants` | ground_texture | town、inn-yard、chapel-hill、photo-lane、archive-lane、harbor | 128×128 | 32×32 | (0,0) / (0,0) | yes | no | 4×4 tile set |
| `grass_path_edge_set` | path_texture | 六张主要室外图 | 128×128 | 32×32 | (0,0) / (0,0) | yes，按拓扑变换 | no | 4×4 transparent modular |
| `stone_path_corner_set` | path_texture | town、chapel-hill、photo-lane、archive-lane、harbor | 128×128 | 32×32 | (0,0) / (0,0) | yes，按拓扑变换 | no | 4×4 tile set |
| `water_shallow_deep_set` | water_texture | town、inn-yard、archive-lane、harbor、low-tide-cave | 128×128 | 32×32 | (0,0) / (0,0) | yes | no | 4×4 tile set |
| `natural_shoreline_set` | water_texture | town、inn-yard、harbor、low-tide-cave | 192×192 | 32×32 | (0,0) / (0,0) | yes，按拓扑变换 | no | 6×6 transparent modular |
| `interior_wall_modular_set` | wall_texture | 全部正式室内 | 160×240 | 32×48 | (0.5,1) / (0.5,1) | no | no；自带墙脚暗边 | 5×5 modular |
| `interior_corner_set` | wall_texture | 全部正式室内 | 192×240 | 48×48 | (0.5,1) / (0.5,1) | no | no | 4×5 modular |
| `baseboard_set` | wall_texture | 全部正式室内 | 160×60 | 32×12 | (0.5,1) / (0.5,1) | no | no；含 1–2 px 接地暗线 | 5×5 modular |

图集本身使用左上角 `(0,0)`；表中墙体的 `(0.5,1)` 是单模块实例锚点。墙角采用 48×48 而不是强压为 32×48，以保留 3/4 视角的侧面和 V 形轮廓。

## 图集顺序

- `grass_base_variants`：16 个低噪声变体；前 8 个最安静，8–11 有少量草叶，12–15 是轻微冷色变化。
- `grass_path_edge_set`：N/S/W/E、四外角、四内角、四方向草侵入。
- `stone_path_corner_set`：中心、四边、四外角、四内角、T 字、十字、小平台；T 字可按拓扑旋转。
- `water_shallow_deep_set`：0–7 浅水，8–15 深水；每组后四格含稀疏静态高光。
- `natural_shoreline_set`：第 0–1 行草岸，第 2–3 行泥岸，第 4–5 行石岸；每种岸线为四边、四外角、四内角。
- 三套室内图集主题行一致：暖旅店、礼拜堂/档案馆、相馆/港务、主钟机械、隐藏暗房。

## 生产与追溯

- 原创母版由内置图像生成工具逐资产生成，没有网络素材或商业游戏参考图。
- 透明母版使用纯 `#ff00ff` 或 `#00ff00` 色键，并通过 imagegen skill 的 `remove_chroma_key.py` 去底。
- `res://tools/prepare_generated_tiles.py` 负责逐 cell 裁切、方向端点贴齐、硬 alpha、限色和 nearest 缩放；不会覆盖 `masters/`。
- `res://tools/process_art_assets.py` 按 manifest 从规范 source 生成 processed PNG，并校验尺寸和残留洋红。
- 母版、规范 source、processed 三层路径均记录在 `art_manifest.json`；`batch_01_processing_report.json` 和 `processing_report.json` 保存尺寸报告。

## Godot 接入

地图调用方使用 `TimeEchoArtCatalog.get_named_tile(asset_id, semantic_name)`；裸索引接口仅保留给目录内部验证，不用于地图布局。`tile_size()`、`atlas_grid()` 和 `tile_count()` 可用于静态批量构建。所有 texture import 继承项目 nearest 默认值。

建议优先接入顺序：town 的草地/石路样板、harbor 的深浅水与岸线、player-room 的暖墙体样板；确认 terrain 邻接规则后再扩到其余地图。程序化回退应保留到逐图审查完成，缺图或无效 index 不得导致场景崩溃。
