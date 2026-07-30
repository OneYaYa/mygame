# Godot 美术审计

审计日期：2026-07-29。正式工程：`godot/project.godot`。基线证据位于 `res://art_review/before/`；18 张图由 Godot 4.6.3 OpenGL Compatibility 实际渲染生成。

## 工程与渲染

- 视口为 1152×648，拉伸模式 `canvas_items`，宽高比 `keep`。
- 正式渲染器与移动端渲染器均为 `gl_compatibility`。
- 默认 Canvas 纹理过滤已是 nearest；旧 `WorldView` 节点也使用 nearest。
- 摄像机原本启用位置平滑，会产生非整数位置和像素抖动风险。
- 角色图片原本以 `0.14` 小数缩放运行；建筑图片被强制拉伸到玩法矩形，长宽比失真。
- 四张 1024×1024 表面源图原本在运行时以 CanvasItem `0.25` 缩放平铺，高频细节明显。

## 原场景结构

修改前的 `location_runtime.tscn` 只有 `WorldView / CanvasModulate / Collisions / Actors / Player`。地面、道路、水域、建筑、家具、装饰、landmark 和 portal 全部由一个 `_draw()` 顺序绘制：

- 视觉矩形、碰撞矩形、交互矩形和 portal 触发矩形高度耦合。
- 建筑、家具、角色不在同一套可解释的排序数据中。
- 墙面装饰、地毯、前景遮挡和局部光照没有独立层。
- portal 和 interactive landmark 在正式画面直接绘制彩色框或圆点。
- `BUILDING_ASSETS`、`FURNITURE_ASSETS`、字符串包含判断承担资产语义；`table -> prop_desk`，`rug/curtain/quilt -> prop_banner` 均属错误映射。

## 数据

- `godot/data/maps.json` 有 18 个稳定地图 ID、33 个 portal 和全部玩法 landmark。
- 旧数组中的 zone/path/furniture 多数没有稳定 ID；新美术布局不得以数组下标关联它们。
- 剧情、物品、证据、NPC 与任务由 `godot/data/world.json` 和脚本规则维护，本轮不把这些字段复制进美术布局。
- 根目录 `data/maps.json`、`data/world.json` 和浏览器运行时没有被 Godot 运行时读取。

## 资产

- 11 个建筑、2 个船只地标、22 个可用道具、8 个角色已登记到 `art_manifest.json`。
- 建筑原生高度大多为 420 px，道具大多约 256 px，角色高度 300 px；原始分辨率不等于世界显示尺寸。
- `prop_buckets.webp` 的画面实际是照片晾晒架，与文件名不符，已禁用并标记 `concept_only`、`needs_review: true`。
- `prop_frame.webp` 也是立式照片展示架，只适用于相馆语境，不作墙上相框。
- `time_echo_horizon.webp` 为标题插图，标记 `concept_only`，不得作为碰撞地图背景。
- `spr_dorothea.webp` 的不透明像素比例明显低于其他角色；当前轮廓仍可用，但标记 `needs_review: true`。

## 地图基线问题

| 地图 | 修改前主要问题 |
|---|---|
| town | 巨大矩形十字石路；钟楼被压扁；左右机械对称；池塘为矩形；portal 框可见。 |
| inn-yard | 十字土路；菜圃/果园为规则矩形；后勤物件分散；池塘矩形。 |
| chapel-hill | 对称花圃与长直路；建筑缺少基座层次；旗帜和范围框抢眼。 |
| photo-lane | 大片空草地；道路过宽；两栋建筑没有形成窄巷。 |
| archive-lane | T 字路与矩形池塘；没有平台、高差或行政前庭。 |
| harbor | 水域是大矩形；码头与岸线断裂；功能物件稀疏；灯塔接地弱。 |
| player-room | 整室木地板；大地毯与黄色交互框主导；家具无私密分区。 |
| inn-lobby | 柜台、休息、后勤混在同一平面；大地毯和范围框主导。 |
| inn-upstairs | 更像大厅；门以旗帜代替；走廊宽而空；异常靠框表达。 |
| clock-cabin | 木地板与旅店一致；工作流不清楚；住宅感过强。 |
| chapel-interior | 木地板、书架和大地毯削弱礼仪与机械主题。 |
| chapel-belfry | 大地毯、宽阔房间与高处维护空间矛盾。 |
| photo-studio | 前厅/工作区不分；桌子散放；相片流程不可读。 |
| archive-room | 书架完全镜像；中央大地毯；服务区和阅览区混合。 |
| harbor-control | 仍是旅店木地板；控制台没有成为核心；货物无集中区。 |
| low-tide-cave | 使用木地板；水池矩形；洞穴边界依赖黑框。 |
| clock-basement | 木地板与大地毯；七插槽缺少系统秩序；装置范围框可见。 |
| hidden-darkroom | 红色大地毯和框线；艾达、显影台与照片没有叙事聚焦。 |

## UI 基线

- HUD 高 70 px，按钮为 44×42；地图有效画面被压缩。
- `_journal_visible` 默认 `true`，正常 `show_game()` 会把右侧 316 px 手账永久打开。
- 交互提示已位于底部，但需要限制宽度、优先级和与玩家的遮挡关系。
- 对话、谜题、结局和存档通知均由独立 modal/toast 构建，本轮保持调用语义。

## 基线验证

- 静态验证：39 个源/场景文件，18 地点，7 NPC，0 失败。
- Godot 编辑器导入：退出码 0。
- 运行测试：59 checks，0 failures。
- 基线画廊：18 maps，0 failures。
- 基线网格可达性审计发现 `harbor/enter_low_tide_cave` 与 `clock-basement/basement_to_cabin` 在旧碰撞近似下不可达；这是修改前记录，不宣称旧版通过。

