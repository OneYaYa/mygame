# TIME ECHO 地图实际渲染画廊

## 渲染条件

- 引擎：Godot 4.6.3 stable，OpenGL Compatibility。
- 视口：1152×648 PNG。
- 截图保留顶部 HUD，关闭右侧手账以展示完整地图；这属于游戏内可达到的 UI 状态。
- 户外和工作场景使用星期六 10:00；旅店二楼使用星期日 00:00；洞穴与隐藏暗房使用星期日 02:30。
- 预览存档启用全部维修和隐藏入口，以便渲染所有地点及 Ada。

## 六宫格总览

- [总览 1：户外地图 01–06](tests/render/maps_v2/gallery_page_1.png)
- [总览 2：室内地图 07–12](tests/render/maps_v2/gallery_page_2.png)
- [总览 3：室内/隐藏地图 13–18](tests/render/maps_v2/gallery_page_3.png)

## 原分辨率单图

| # | 地点 | ID | 截图 |
|---:|---|---|---|
| 01 | 钟影广场 | `town` | [1152×648 PNG](tests/render/maps_v2/01_town.png) |
| 02 | 湖畔旅店前庭 | `inn-yard` | [1152×648 PNG](tests/render/maps_v2/02_inn-yard.png) |
| 03 | 六声礼拜堂 | `chapel-hill` | [1152×648 PNG](tests/render/maps_v2/03_chapel-hill.png) |
| 04 | 银盐巷 | `photo-lane` | [1152×648 PNG](tests/render/maps_v2/04_photo-lane.png) |
| 05 | 档案坡道 | `archive-lane` | [1152×648 PNG](tests/render/maps_v2/05_archive-lane.png) |
| 06 | 回潮港 | `harbor` | [1152×648 PNG](tests/render/maps_v2/06_harbor.png) |
| 07 | 湖畔旅店 · 八号房 | `player-room` | [1152×648 PNG](tests/render/maps_v2/07_player-room.png) |
| 08 | 湖畔旅店 · 大堂 | `inn-lobby` | [1152×648 PNG](tests/render/maps_v2/08_inn-lobby.png) |
| 09 | 湖畔旅店 · 二楼走廊 | `inn-upstairs` | [1152×648 PNG](tests/render/maps_v2/09_inn-upstairs.png) |
| 10 | 主钟维修舱 | `clock-cabin` | [1152×648 PNG](tests/render/maps_v2/10_clock-cabin.png) |
| 11 | 六声礼拜堂 · 钟厅 | `chapel-interior` | [1152×648 PNG](tests/render/maps_v2/11_chapel-interior.png) |
| 12 | 六声礼拜堂 · 钟楼 | `chapel-belfry` | [1152×648 PNG](tests/render/maps_v2/12_chapel-belfry.png) |
| 13 | 银盐照相馆 | `photo-studio` | [1152×648 PNG](tests/render/maps_v2/13_photo-studio.png) |
| 14 | 市政档案馆 | `archive-room` | [1152×648 PNG](tests/render/maps_v2/14_archive-room.png) |
| 15 | 港务控制室 | `harbor-control` | [1152×648 PNG](tests/render/maps_v2/15_harbor-control.png) |
| 16 | 退潮维护洞穴 | `low-tide-cave` | [1152×648 PNG](tests/render/maps_v2/16_low-tide-cave.png) |
| 17 | 主钟地下室 | `clock-basement` | [1152×648 PNG](tests/render/maps_v2/17_clock-basement.png) |
| 18 | 消失的第二暗房 | `hidden-darkroom` | [1152×648 PNG](tests/render/maps_v2/18_hidden-darkroom.png) |

机器可读索引位于 `tests/render/maps_v2/gallery_manifest.json`。

## 重新生成

```powershell
& 'C:\Users\ethanypan\Desktop\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe' `
  --path 'C:\Users\ethanypan\Desktop\mygame\godot' `
  'res://tests/map_gallery.tscn' --fixed-fps 30 --disable-vsync
```
