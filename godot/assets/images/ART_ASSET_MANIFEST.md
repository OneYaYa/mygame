# TIME ECHO 美术资产清单

## 迁移范围

`source_art/` 是仓库根目录 `art/` 的只读镜像。迁移时只复制图片本体，不复制旧 Godot `.import` sidecar；首次导入后，Godot 4.6.3 会在这里为当前 `res://` 路径生成新的旁车和 `.godot/` 缓存，这是预期结果。

| 来源目录 | 图片数 | Godot 目录 | 用途 |
|---|---:|---|---|
| `art/runtime/` | 46 | `source_art/runtime/` | 已去底的建筑、角色、道具、地标与标题远景备份 |
| `art/world/` | 50 | `source_art/world/` | 运行时原图、角色方向稿与四类无缝表面纹理 |
| `art/town_square/` | 22 | `source_art/town_square/` | 广场构图、建筑、角色和道具概念稿 |
| `art/_gen/` | 17 | `source_art/_gen/` | 第一批生成源稿，供重新切图或修订 |
| `art/_gen2/` | 12 | `source_art/_gen2/` | 第二批生成源稿，供重新切图或修订 |
| **总计** | **147** | `source_art/` | 完整源图片归档 |

## 运行时选择

- `assets/images/` 根目录的 46 张 PNG/WebP 是当前运行时透明版本，继续保持稳定路径，避免破坏场景和脚本引用。
- `source_art/world/tile_grass.png`、`tile_water.png`、`tile_cobble.png`、`tile_wood.png` 已由 `world_view.gd` 实际加载，用于户外地面、水域、广场/石路和室内木地板。
- 建筑、家具、装饰和地标使用透明运行时图，并增加统一的右下落影，保持俯视 3/4 视角的层次和可读性。
- `town_square/keyart_town_square.png` 作为构图与暖色调参考保留。它不是碰撞地图，避免概念图中的固定人物和建筑与 JSON 交互坐标冲突。
- `world/` 与 `town_square/` 中带洋红背景的原稿不会直接进入游戏画面；对应去底版本位于运行时目录。

## 视觉方向

当前方向采用温暖、清晰、生活感强的 16-bit 湖镇像素美术语言：草木和石路较明亮，钟楼、档案馆与湖面保留 TIME ECHO 的悬疑冷色。目标是获得舒适的田园探索可读性，同时保持本作自己的钟表、白线与时间循环身份。
