# Full Map Art Production Plan

## Scope and safety boundary

The formal Godot 4.6 project is the only source of truth. This rollout changes only the 15 maps listed in `map_asset_dependencies.json`, their Godot-native art data, processing tools, tests, screenshots, and reports. `town`, `harbor`, and `inn-lobby` remain frozen and are rendered only for regression comparison. Repository-root HTML, CSS, JavaScript, and browser data remain read-only.

Before production, the original Godot data, layouts, world/location/UI scenes and scripts, and tests were copied to `tmp/godot-full-map-art-backup/`. The `.godot` import cache and generated `.import` files are not part of the backup or manual editing scope.

## Pipeline

1. Generate one traceable master sheet per coherent scene family using the approved top-down three-quarter pixel-art direction and solid chroma background.
2. Normalize masters into individual transparent sources in `assets/images/source_art/generated/` with integer canvases, hard alpha, palette limits, nearest sampling, safe margins, and chroma decontamination.
3. Write processed runtime PNGs to `assets/images/processed/` without overwriting pre-existing source art.
4. Extend existing preparation/processing validation so every enabled asset has a source, processed file, dimensions, SHA-256 hash, and semantic mapping where it is an atlas.
5. Integrate assets through the data-driven art layouts. Preserve gameplay IDs, update portal/interaction rectangles with visual positions, and keep integer display sizes and positions.
6. Render each batch in OpenGL Compatibility, review at normal game scale, repair/revert poor results, then continue automatically.
7. Render the final 18-map gallery, nearest-neighbor detail crops, contact sheets, and frozen-map regression comparisons.
8. Run the full static, import, runtime, gallery, portal, movement, interaction, save/load, time-loop, puzzle, ending, and Web Compatibility checks.

## Batch gates

| Batch | Maps | Master families | New IDs | Visual gate | Functional gate |
|:---:|---|---|---:|---|---|
| A | inn-yard, player-room, inn-upstairs | inn outdoor, room furniture, corridor | 31 | lived-in warm inn identity; no empty warehouse/corridor blocks | yard and room portals, all numbered-door locks, sleep/journal |
| B | chapel-hill, chapel-interior, chapel-belfry | memorial exterior, ritual mechanism, belfry | 29 | chapel sole center; six/seventh hammer are spatial machines | chapel/belfry portals, repair and tuning-fork conditions |
| C | photo-lane, photo-studio, archive-lane, archive-room | photo street/studio, archive exterior/interior | 42 | recognizable photographic workflow and ordered archive | east/west routes, darkroom thresholds, dialogue/development/indexing |
| D | clock-cabin, harbor-control, clock-basement | clock workshop, harbor control, protocol core | 44 | engineering workflows; basement reads as a room-sized machine | calibration, tide control, both ending mechanisms |
| E | low-tide-cave, hidden-darkroom | natural cave, forgotten darkroom | 32 | natural non-rectangular cave; Ada-focused local red light | low-tide/time-stop reveal, four anchors and true ending |

## Acceptance rules

- A new master receives one initial generation and at most two automatic repair/regeneration attempts.
- A result with unclear perspective, chroma contamination, unreadable silhouette, pseudo-text, blur, or inconsistent palette is not integrated.
- After three failed attempts, the semantic procedural fallback stays active, the asset is marked `needs_review`, and production continues.
- Atlases use named semantics; layouts do not depend on arbitrary rotation or undocumented numeric indexes.
- High contrast is reserved for characters, entrances, mechanisms, and story-critical objects. Ground and large architectural surfaces remain low noise.
- All screenshots are from the Godot 4.6 Compatibility renderer; detail crops use nearest integer scaling.

## Integration order

The order is `inn-yard` → `player-room` → `inn-upstairs` → `chapel-hill` → `chapel-interior` → `chapel-belfry` → `photo-lane` → `photo-studio` → `archive-lane` → `archive-room` → `clock-cabin` → `harbor-control` → `clock-basement` → `low-tide-cave` → `hidden-darkroom`.

This order establishes reusable scene-family palettes before more mechanical and narrative-critical spaces, while keeping every batch independently renderable and testable.
