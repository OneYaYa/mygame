# Remaining 15 Maps — Asset Dependency Matrix

This matrix is the production gate for the full-map rollout. `town`, `harbor`, and `inn-lobby` are frozen reference maps and are excluded from asset rollout. The machine-readable source is `res://data/map_asset_dependencies.json`.

| Order | Batch | Map | Primary visual center | Zones | Reuse direction | Replaced procedural fallback | New IDs |
|---:|:---:|---|---|---:|---|---|---:|
| 1 | A | inn-yard | inn entry and platform | 7 | validated grass/water/shore, inn buildings | garden lines, bucket, polygon roads | 11 |
| 2 | A | player-room | journal desk, photo board, bed | 5 | inn wall kit, bed, fireplace | photo/rug/door/chair blocks | 10 |
| 3 | A | inn-upstairs | room-eight anomaly | 5 | inn wall kit | repeated block doors, rug and lamps | 10 |
| 4 | B | chapel-hill | chapel and ritual steps | 5 | chapel building, grass, trees | polygon path/garden | 9 |
| 5 | B | chapel-interior | six-hammer mechanism | 6 | modular wall kit | black clockwork panel, block pews/ropes | 11 |
| 6 | B | chapel-belfry | seventh hammer | 6 | crates and lantern | beams, ropes and bell blocks | 9 |
| 7 | C | photo-lane | studio craft display | 6 | both lane buildings, edge plants | wide path and frame blocks | 7 |
| 8 | C | photo-studio | camera/backdrop/light composition | 5 | wall kit, generic small seating | console/rack/door/photo blocks | 16 |
| 9 | C | archive-lane | raised archive entry | 5 | archive building and grass | T-path and rock blocks | 7 |
| 10 | C | archive-room | counter and reading table | 6 | wall kit, directional chairs | shelf/table/notice blocks | 12 |
| 11 | D | clock-cabin | three-gear calibration device | 6 | wall kit, limited logistics props | generic desk/console/gear blocks | 14 |
| 12 | D | harbor-control | chart table and signal console | 6 | wall kit, limited logistics props | black console/signal/notice blocks | 13 |
| 13 | D | clock-basement | protocol console | 7 | mechanical wall kit only | entire UI-like console/slot/gear field | 17 |
| 14 | E | low-tide-cave | maintenance remains and negative route | 6 | water transition palette | rectangular shell and rock blocks | 17 |
| 15 | E | hidden-darkroom | Ada and unfinished portrait | 6 | corner kit only | red block shell, slot and safelight blocks | 15 |

## Production totals

- Batch A: 31 asset IDs for three inn-life maps.
- Batch B: 29 asset IDs for three chapel maps.
- Batch C: 42 asset IDs for four photo/archive maps.
- Batch D: 44 asset IDs for three engineering maps.
- Batch E: 32 asset IDs for two hidden maps.
- Total: 178 new asset IDs with an explicit consumer and purpose.

Every map entry records its wall/floor theme, light sources, foreground occlusion, animation needs, integration order, and gameplay risks in the JSON. Asset IDs are not shared into the three frozen reference layouts during this rollout.
