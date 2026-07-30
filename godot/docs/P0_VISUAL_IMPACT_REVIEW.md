# P0 高视觉影响垂直切片复核

复核日期：2026-07-30

## 范围与基线结论

本轮只修改 `town`、`harbor`、`inn-lobby`。上一轮小范围接入正式记为 `VISUAL_REJECTED`：新 Tile 覆盖不足，主要构图、道路、水陆边界和室内有效面积在正常游戏尺度下变化过小。其余 15 张地图的布局未推广本轮 `atlas_tile_art`。

保留的工程能力包括 `art_manifest`、`art_atlas_semantics`、`TimeEchoArtCatalog`、`TimeEchoArtTileLayerBuilder`、程序化回退、稳定 gameplay ID、碰撞与 portal 系统。本轮没有生成 P1/P2，也没有修改浏览器版。

## 仅针对标杆图的图集修复

- `natural_shoreline_set_v2`：重新构造草岸、泥岸、石岸的四直边、四外角和四内角。直边在 10px 基线闭合，内外角使用互补四分之一圆弧，消除旧版黑断条、透明边和放大图中的描线断点。town 使用草岸；harbor 主岸使用草岸、码头和灯塔岛使用石岸。
- `stone_path_corner_set_v2`：保持 32×32 密度，T 字和十字路口可读宽度扩大到 24px；地图侧只以命名语义选格，不旋转猜测。
- `water_shallow_deep_set_v2`：保留低噪声静态水纹，新增四个浅深水直向过渡与四个角过渡。深水降低亮度，浅水只占岸边一至两格，高光采用固定 seed。
- 三个原始 batch-01 source 文件与 `masters/` 均未覆盖；修复版使用 `_v2` 路径。`references/` 中保留三张内置图像生成参考，最终运行图由 `repair_p0_benchmark_tiles.py` 精确重建并经 `process_art_assets.py` 处理。

## 地图视觉变化

### town

- 旧平滑十字道路退出最终可见层；横向主街、纵向通道、主钟前庭以及三处建筑入口改为正式命名石路 Tile。
- 主钟前庭扩为非矩形公共广场，主钟仍是绝对中心；面包店、装订店由窄支路和磨损门台接入主街。
- 池塘改为固定网格的不对称轮廓：草岸闭合、外围浅水、内层深水；两侧灌木和石块压住边缘，不再显示旧程序岸线。
- 下半部重组为池塘与公共休息区两组视觉重量；长椅、花坛、公告牌形成生活功能组合，前景树冠/灌木负责边界。
- 当前限制：32px 深水核心在最近邻放大图中仍可读出格网节奏；石路中心纹理在大面积区域略密。因此结论为 `APPROVED_WITH_FIXES`，不直接推广。

### harbor

- 旧程序水面、主岸线、港务灰盒平台和灯塔岛底层退出最终可见层；连续水域、浅深过渡与岸线由正式 Tile 构建一次。
- 主岸采用低频弯折和闭合草岸，码头连接段改用石岸；灯塔岛以石路核心和显式石岸语义构成。
- 码头起点嵌入岸边工作平台，保留底部暗线；渡船、船长和洞穴入口的 gameplay 语义未移动。
- 港务楼前平台、主通路和码头入口形成工作流；桶箱组合与渔网/绳索组合分开，不再沿直线散放。
- 当前限制：浅深水的 32px 过渡带在最近邻局部图仍有轻微模块节奏。因此结论为 `APPROVED_WITH_FIXES`，不直接推广。

### inn-lobby

- room canvas 由 732×454 收紧为 672×432，有效面积减少约 18%；收紧来自真实左右墙、顶墙、底墙、后勤隔墙与门框，而不是放大黑边。
- 只使用 `inn_warm`：完整顶墙、左右墙、墙角、连续墙脚线、门洞中断、两扇窗和墙面装饰均在非 Y-sort 层。
- 接待柜台与 Dorothea 日程点关联；壁炉/长椅、公共桌椅、入口地毯、楼梯和后勤箱桶形成六个可读区。
- 楼梯改为有逐级踏板与边梁的程序像素结构；门洞、柜台和 NPC 保持清晰，壁炉/柜台/壁灯使用局部暖光。
- 结论：`APPROVED`，但本轮仍不把墙体主题推广至其他室内图。

## 视觉差异统计

工具：`python godot/tools/build_p0_visual_impact_review.py`。

- 机位、时间、玩家位置和 1152×648 Compatibility 渲染尺寸相同；HUD 的前 50 行排除。
- 严格像素率要求单像素最大通道差至少 24 且 RGB 差值和至少 42。
- 语义影响率按 8×8 块统计：至少 20% 像素达到中等差异，且平均最大通道差至少 7。它用于识别低饱和 Tile 的整块纹理/结构替换；报告同时保留严格率，不能用语义率隐藏轻微调色。
- 最终机器数据在 `art_review/p0_visual_impact/diff/impact_metrics.json`：

| 地图 | 严格像素率 | 8×8 语义影响率 | 人工判断 |
|---|---:|---:|---|
| town | 13.964% | 27.425% | 接近约 30% 防小改阈值；主道路、广场、池塘与生活区在正常尺度明显变化 |
| harbor | 9.645% | 50.746% | 大面积低饱和水面像素单点差异较小，但水陆轮廓、深浅层与后勤构图覆盖超过半屏 |
| inn-lobby | 27.186% | 51.384% | 完整 room shell、面积收紧、家具分区和楼梯结构均为高影响变化 |

严格率与语义率都保留。town 未把 27.425% 四舍五入伪称为达到 30%；其 `APPROVED_WITH_FIXES` 来自正常尺度人工对照满足全部 town 专项标准，而不是只依赖百分比。

## 真实截图证据

- 完整 before：`art_review/p0_visual_impact/before/town.png`、`harbor.png`、`inn-lobby.png`
- 完整 after：`art_review/p0_visual_impact/after/town.png`、`harbor.png`、`inn-lobby.png`
- 差异图：`art_review/p0_visual_impact/diff/town_diff.png`、`harbor_diff.png`、`inn-lobby_diff.png`
- town 局部：`town_clock_plaza.png`、`town_road_edge.png`、`town_pond.png`、`town_bakery_entrance.png`
- harbor 局部：`harbor_main_shore.png`、`harbor_dock_connection.png`、`harbor_lighthouse_island.png`、`harbor_water_transition.png`、`harbor_logistics_area.png`
- inn-lobby 局部：`inn_full_room_shell.png`、`inn_main_door.png`、`inn_reception.png`、`inn_fireplace_area.png`、`inn_stair_connection.png`

全部局部图从 after 的真实 Godot 截图裁切并使用 nearest 整数倍放大，没有重绘或插值模糊。

## 功能与推广决策

本轮推广状态保持关闭：其余 15 张地图不加入 batch-01 Tile 配置。

实际回归结果：

- `repair_p0_benchmark_tiles.py --validate`：3 source + 3 processed 修复图集通过。
- `prepare_generated_tiles.py --validate`：通过。
- `process_art_assets.py --validate`：通过。
- `validate_project.py`：48 个 source/scene 文件、18 个地点、7 个 NPC，0 failures。
- Godot 4.6.3 headless editor import：通过，无 Parser Error。
- `test_runner.tscn`：178 checks，0 failures。
- `test_runner.tscn -- --save-io-test`：183 checks，0 failures；隔离 `user://` 写入、读取并清理成功。
- `visual_smoke.tscn`：退出码 0。
- 正式主场景 headless Compatibility `--quit-after 10`：退出码 0。
- NVIDIA GeForce RTX 2060 / OpenGL 3.3 Compatibility 三图 gallery：3 maps，0 failures。
- 最终 gallery：town 1123 个静态语义格、5/5 portal 可达；harbor 1606 个静态语义格、3/3 portal 可达；inn-lobby 65 个静态模块、2/2 portal 可达。三图均为 0 asset errors、0 layout warnings。

- town：`APPROVED_WITH_FIXES`
- harbor：`APPROVED_WITH_FIXES`
- inn-lobby：`APPROVED`
- 全项目推广：`NOT_APPROVED_FOR_BULK_PROMOTION`
