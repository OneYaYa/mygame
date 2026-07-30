# LEVEL ART VERTICAL SLICE PASS 01 · 视觉与功能审查

审查日期：2026-07-30  
正式来源：`godot/`  
审查尺度：Godot 4.6.3 stable、1152×648、OpenGL 3.3 Compatibility、NVIDIA GeForce RTX 2060、正式 HUD 与玩家角色。  
证据入口：`res://art_review/level_art_pass_01/contact_sheet.png`

## 量化结果

| 地图 | 有效面积 before → after | 缩小 | 空地比例 before → after | Camera2D zoom | 玩家截图高度 | 功能区 / 物件簇 | 前景 | 视觉中心 | 新增结构实例 | 新增小型资产 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| player-room | 187,552 → 139,870 px² | 25.4% | 57% → 27% | 1.00 → 1.25 | 48 → 60 px | 4 / 3 | 1 层、2 个遮挡件 | 1 主 + 2 次 | 3 大 + 1 中 | 0 |
| chapel-belfry | 191,880 → 120,640 px² | 37.1% | 64% → 24% | 1.00 → 1.20 | 48 → 58 px | 4 / 3 | 3 层、梁柱组合 | 1 主 + 2 次 | 5 大 | 0 |
| low-tide-cave | 205,215 → 145,080 px² | 29.3% | 62% → 25% | 1.00 → 1.15 | 48 → 55 px | 4 / 3 | 3 层、3 个洞顶遮挡组 | 1 主 + 2 次 | 4 大 + 1 中/光照补丁 | 0 |
| clock-basement | 306,140 → 214,520 px² | 29.9% | 52% → 26% | 1.00 → 1.15 | 48 → 55 px | 6 / 4 | 1 层、2 个前景管组 | 1 主 + 3 次 | 5 大 + 1 中 | 0 |

“新增结构实例”是由现有 atlas、已有大资产和代码原生像素结构组成的地图级装配，不是新增 manifest `asset_id`。本轮新增 raster、atlas、manifest 资产均为 0；新增小箱、工具、挂件、照片、随机地面装饰同样为 0。

## player-room

- 空间：把完整大地板收成左侧睡眠壁龛、上方壁炉/储物墙、右侧记录区和下方入口过渡；入口仍保留清楚的 56 px 门洞。
- 功能区：睡眠、记忆记录、壁炉休息、入口过渡。
- 物件簇：床/床头柜/灯/地毯/衣柜/窗帘；手账桌/椅/照片板/储物箱/工作灯；壁炉/围合/座椅/木柴/地毯/暖光。
- 构图与光：壁炉围合、尺寸、暖色、地毯轴线与周围留白建立主中心；床和记录桌成为两组次中心。壁炉暖光、记录工作灯、床头灯和入口引导光分层，不再整体均匀压暗。
- 玩法：保留 `repair_orders`、`player_journal`、`room8_to_hall`；补齐正式 `player_bed` 和 `player_memory_board` 交互。床可休息半小时，手账和跨循环照片分别打开正确面板。
- 正常尺度可读性：床、壁炉、照片板、桌和出口均可直接识别，玩家高度 60 px。
- 视觉差异：由“家具散落的大展厅”变为紧凑、有生活磨损和记忆保留语义的私人房间。
- 结论：`APPROVED`。

## chapel-belfry

- 空间：关闭普通矩形 room shell；以深处、中央维护平台、侧维护台、下楼台和不可进入的高梁架定义可走空间。
- 功能区：第七锤校准、右侧维护、高窗观察、左侧下楼。
- 物件簇：第七锤/锤座/锤架/机械轴/音叉槽/吊绳；高窗/工具/绳圈/维护灯/侧平台；楼梯/日志/钥匙牌/绳组/路径冷光。
- 构图与光：第七锤由尺寸、中心位置、金属对比、局部金光、校准地面和梁架引导六项强化；高窗冷光和下楼冷光分离高度层。
- 前景：上方近景横梁、下方近景梁和左右支柱会按玩家位置淡出，不长期遮住人物或锤架。
- 玩法：保留原四个稳定 ID，并新增与现有绳索视觉一致的 `belfry_calibration_rope`。已鉴定音叉可校准锤架；贝娅特丽斯承诺第七声后会真实调度到可达的钟楼维护位置，绳索进入待命状态。
- 正常尺度可读性：锤架、平台高差、开放边缘、楼梯和维护角无需放大即可辨认。
- 视觉差异：由“暗矩形仓库中的独立锤”变为狭窄、危险、具真实承重关系的高处钟楼。
- 结论：`APPROVED`。

## low-tide-cave

- 空间：完全取消室内墙脚线和规则地板；上方侵入岩壁、下方不规则水池、左右洞体和黑暗深处共同定义洞穴轮廓。
- 功能区：退潮入口、分段维护路径、旧设备区、隐藏证物/积水区。
- 物件簇：洞口/湿石/海藻/潮痕/冷光；石面/断板/泥地/旧设备/锈工具/黄灯；底片/遮挡岩/浅水/反光/轻微证物引导光。
- 构图与光：道路拆为石面、木板和泥地的折线段；入口冷光、玩家手电暖光、设备黄光、湿地反光和证物微光各司其职。
- 前景与水体：三组洞顶近景具有不规则剪影和近人淡出；水池使用多边形边缘、深色核心、浅水圈、高光和湿石碰撞，没有矩形水块。
- 玩法：低潮开放窗口、洞内停时、手电门槛、底片拾取、入口/离开 Portal、水域碰撞和连续可走路径均通过回归。
- 正常尺度可读性：入口、道路、深浅水边界、维护设备和证物路线可辨；保留危险/隐蔽所需留白。
- 视觉差异：由“暗房间中的灰色丝带”变为岩壁和潮水真正控制路线的自然空间。
- 结论：`APPROVED`。

## clock-basement

- 空间：设备墙龛、侧站结构、后部信号桥、放射地槽和入口脊线把外围空地收进统一机械系统。
- 功能区：中央协议、七见证位、红色清除站、白色继续站、三信号监控、制动/入口维护。
- 物件簇：协议台/环形地面/七条连接线/插槽弧架；红站/红光/警告框/手柄；白站/暖白光/克制框/条件显现；信号桥/三灯/高位框/中央连接。
- 构图与光：中央台由放射线、尺度、暗金主光、中心位置和周边负空间强化。红白站保持等量次焦点，信号桥形成第三组次焦点，外围进入可读暗部。
- 状态：第七槽锁定/激活视觉、白站完整显现和红白结局逻辑继续由 `slot_seven_filled` 与原有剧情条件控制。
- 玩法：七插槽、三灯、红白机关、两个结局、制动接口、Portal、存档跨循环状态均通过；阿瑟承诺停钟后会调度到地下室开放维护位置，玩家和 NPC 均可达。
- 正常尺度可读性：七槽弧、三灯、中央台与红白选择形成清楚层级，玩家高度 55 px。
- 视觉差异：由“大房间里的设备陈列”变为有仪式秩序、连线因果与叙事抉择的协议中心。
- 结论：`APPROVED`。

## 视觉评分

| 地图 | composition | spatial_density | structural_depth | functional_clustering | scale_consistency | lighting | environmental_storytelling | gameplay_readability | overall |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| player-room | 8.2 | 8.3 | 7.8 | 8.6 | 8.5 | 8.2 | 8.3 | 8.7 | 8.3 |
| chapel-belfry | 8.5 | 8.2 | 8.8 | 8.0 | 8.3 | 7.8 | 8.5 | 8.4 | 8.3 |
| low-tide-cave | 7.8 | 7.9 | 8.2 | 7.8 | 8.1 | 8.0 | 8.2 | 8.3 | 8.0 |
| clock-basement | 8.7 | 8.4 | 8.6 | 8.5 | 8.3 | 8.4 | 8.8 | 8.5 | 8.5 |

四图均达到：overall ≥ 7.5、composition ≥ 7、spatial_density ≥ 7、gameplay_readability ≥ 8。

## 截图证据

- 修改前完整图：`res://art_review/level_art_pass_01/before/<map-id>.png`
- 修改后完整图：`res://art_review/level_art_pass_01/after/<map-id>.png`
- 六视图：两个目录均包含 `<map-id>_full_scene.png`、`_gameplay_camera.png`、`_core_visual_center.png`、`_main_function_cluster.png`、`_foreground_layer.png`、`_entrance_and_path.png`。
- 局部视图：固定 2× nearest 整数倍放大，没有双线性缩放。
- 并排图：`res://art_review/level_art_pass_01/<map-id>_comparison.png`
- 总表：`res://art_review/level_art_pass_01/contact_sheet.png`
- 机器可读清单：`res://art_review/level_art_pass_01/review_manifest.json`

## 功能与工程回归

通过：

- `python tests/validate_project.py`：48 个源码/场景文件、18 个场景、7 个 NPC、0 失败。
- `prepare_full_map_assets.py --validate`：178 个源资产有效。
- `prepare_generated_tiles.py --validate`：通过。
- Godot editor import：Godot 4.6.3 stable，退出码 0。
- `test_runner.tscn`：最终常规回归 282 checks、0 failures；覆盖四图镜头、前景、空地/功能簇门槛、七插槽与三信号灯数量、稳定 ID、全部交互点和 Portal 图搜索可达性、实际出生/进入点物理移动、碰撞、Y 排序、NPC 调度/可达、低潮停时/手电/底片、红白结局和跨循环状态。
- 隔离存档：真实 `user://` 写入、读回与清理通过，未触碰正式存档。
- 正式 `main.tscn`：Compatibility GPU 启动并稳定运行 120 帧，退出码 0。
- `visual_smoke.tscn`：Compatibility GPU，退出码 0。
- 四地图 gallery：4 captures、0 failures；四图 `asset_errors=[]`、`warnings=[]`，Portal 和所有交互点均可达。
- OpenGL Compatibility：NVIDIA RTX 2060 / OpenGL 3.3 实机运行通过；desktop 与 mobile/Web fallback 均由测试确认配置为 `gl_compatibility`。

未判为通过、且没有越权修复：

- 独立运行全局 `process_art_assets.py --validate` 报告 6 个本轮范围外的旧资产仍有 1–3 个残余洋红像素：`env_bakery`、`env_bookbinder`、`env_chapel_tower`、`env_silver_salt_studio`、`env_harbor_control`、`prop_tree`。四张切片的正式 gallery 资源检查均为 0 错误；为遵守“不得修改其他地图/不得启动批量资产修复”，本轮没有改写这些资产。
- 仓库没有 `export_presets.cfg`，因此没有声称执行实际 HTML5/Web 导出。已验证 Web 所需 Compatibility 配置和同一渲染路径，但浏览器产物应在后续建立正式 Web preset 后单列执行。

## 推广规则

1. 先压缩无叙事用途的有效面积，再做资产摆放；空地只能由路径、仪式、危险、高度或焦点证明其必要性。
2. 先建结构骨架：边界、转折、平台/岩壁/设备墙、入口和主路径；至少三个元素形成一个功能簇。
3. 一个主中心必须同时借助至少三种构图因素；次级组不能与主中心争夺最高对比。
4. 特殊空间必须使用自身语法：钟楼用梁与高度，洞穴用岩壁与水，协议室用连线与设备层级，不能换色复用矩形 room shell。
5. 前景必须是真实结构且具可控遮挡；近人淡出是保险，不代替合理路径。
6. 镜头与有效面积联动评审，角色和交互物先满足正常尺度可读，再保留导航全貌。
7. 光照按环境、主、次、焦点和路径五层组织；整体压暗不计作氛围完成。
8. 新资产预算按“结构缺口”批准，不按装饰密度批准；已有 atlas 能装配就不新增 `asset_id`。

建议下一批按类型推广，而不是一次推完：生活室内先推广到 `inn-upstairs`；高处/工业平台推广到 `clock-cabin` 与 `harbor-control`；自然边界推广到 `harbor`；机械叙事空间最后推广到 `hidden-darkroom`。本轮没有自动修改这些地图。
