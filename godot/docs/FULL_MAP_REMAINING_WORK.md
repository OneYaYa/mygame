# Full Map Remaining Work

## 阻塞项

无。178 个新增资产均完成 source/processed/manifest/semantic/layout 接入，`needs_review` 为 0；15 张目标地图全部通过功能回归。

## 非阻塞 P1 美术余量

- chapel-hill：为西侧低墙增加一个轻微折线变体，并在墓园留白处增加一组低对比枯叶/小墓碑。
- photo-lane：南侧草地增加一处不遮挡道路的生活物件组合。
- archive-lane：平台外缘增加一处小型市政绿化或石柱组合，保持宽阔可走肩部。
- low-tide-cave：右侧湿区增加一处冷色硬边反光，不提高全屏亮度。

这些工作不需要新资产家族，可复用现有 atlas 语义，不影响当前剧情、碰撞或 Portal。若把本轮管线推广为后续内容模板，建议先完成以上四个 P1 布局变体，再冻结 18 图 Gallery 作为统一回归基线。

## 保持不动

- 不修改仓库根目录 HTML、CSS、JavaScript 和浏览器数据。
- 不向 `town`、`harbor`、`inn-lobby` 推广本批 178 个资产。
- 不覆盖原有 `source_art`；13 张母版、清键母版和规范化 source 继续保留追溯链。
- 不自动提交或改写 Git 历史。
