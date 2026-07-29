class_name TimeEchoWorldView
extends Node2D

const BUILDING_ASSETS: Dictionary = {
	"master_clock_tower": "env_master_clock_tower",
	"bakery": "env_bakery",
	"bookbinder": "env_bookbinder",
	"lakeside_inn": "env_lakeside_inn",
	"inn_shed": "env_inn_shed",
	"chapel_tower": "env_chapel_tower",
	"silver_salt_studio": "env_silver_salt_studio",
	"frame_shop": "env_frame_shop",
	"town_archive": "env_town_archive",
	"harbor_control": "env_harbor_control",
	"lighthouse_watchtower": "env_lighthouse_watchtower",
}
const FURNITURE_ASSETS: Dictionary = {
	"barrel": "prop_barrel", "bed": "prop_bed", "bench": "prop_bench",
	"counter": "prop_counter", "crate": "prop_crate", "desk": "prop_desk",
	"fireplace": "prop_fireplace", "shelf": "prop_shelf", "table": "prop_desk",
}
const SURFACE_ASSETS: Dictionary = {
	"grass": "res://assets/images/source_art/world/tile_grass.png",
	"water": "res://assets/images/source_art/world/tile_water.png",
	"cobble": "res://assets/images/source_art/world/tile_cobble.png",
	"wood": "res://assets/images/source_art/world/tile_wood.png",
}
const SURFACE_SCALE: float = 0.25

var scene_data: Dictionary = {}
var game_state: Dictionary = {}
var _textures: Dictionary = {}


func set_world(scene: Dictionary, state: Dictionary) -> void:
	scene_data = scene
	game_state = state
	queue_redraw()


func update_state(state: Dictionary) -> void:
	game_state = state
	queue_redraw()


func _draw() -> void:
	if scene_data.is_empty():
		return
	var width: float = float(scene_data.get("width", 768.0))
	var height: float = float(scene_data.get("height", 480.0))
	var palette: Dictionary = scene_data.get("palette", {}) as Dictionary
	var ground: Color = _color(palette.get("ground", "#718b5f"), Color("718b5f"))
	if str(scene_data.get("kind", "outdoor")) == "interior":
		ground = _color(palette.get("floor", palette.get("ground", "#7a684f")), Color("6b5947"))
	var world_rect := Rect2(0, 0, width, height)
	draw_rect(world_rect, ground)
	var surface_name: String = "wood" if str(scene_data.get("kind", "outdoor")) == "interior" else "grass"
	var surface: Texture2D = _surface(surface_name)
	if surface != null:
		var ground_tint: Color = ground.lightened(0.42)
		ground_tint.a = 0.68 if surface_name == "grass" else 0.58
		_draw_tiled_surface(surface, world_rect, ground_tint)
	else:
		_draw_ground_grid(width, height, ground)
	for raw: Variant in scene_data.get("zones", []):
		_draw_zone(raw as Dictionary, palette)
	for raw: Variant in scene_data.get("paths", []):
		_draw_path(raw as Dictionary, palette)
	for raw: Variant in scene_data.get("buildings", []):
		_draw_building(raw as Dictionary, palette)
	for raw: Variant in scene_data.get("furniture", []):
		_draw_furniture(raw as Dictionary, palette)
	for raw: Variant in scene_data.get("decorations", []):
		_draw_decoration(raw as Dictionary, palette)
	for raw: Variant in scene_data.get("landmarks", []):
		_draw_landmark(raw as Dictionary, palette)
	for raw: Variant in scene_data.get("portals", []):
		var portal: Dictionary = raw as Dictionary
		if SceneManager.can_reveal_portal(portal, game_state):
			_draw_portal(portal, palette)
	_draw_dynamic_story_marks(palette)
	var border: Color = _color(palette.get("edge", "#324c47"), Color("324c47"))
	draw_rect(Rect2(4, 4, width - 8, height - 8), border, false, 6.0)


func _draw_ground_grid(width: float, height: float, ground: Color) -> void:
	var alt: Color = ground.lightened(0.045)
	for y: int in range(0, int(height), 24):
		for x: int in range(0, int(width), 24):
			if (int(x / 24) + int(y / 24)) % 2 == 0:
				draw_rect(Rect2(x, y, 24, 24), alt)


func _draw_zone(zone: Dictionary, palette: Dictionary) -> void:
	var rect: Rect2 = _rect(zone)
	var type: String = str(zone.get("type", "ground"))
	var color: Color
	var surface_name: String = ""
	if type in ["pond", "canal", "water"]:
		color = _color(palette.get("water", "#557f8d"), Color("557f8d"))
		surface_name = "water"
	elif type == "plaza":
		color = _color(palette.get("path", "#b7a178"), Color("b7a178"))
		surface_name = "cobble"
	elif type == "rug":
		color = _color(zone.get("color", palette.get("roof", "#795a59")), Color("795a59"))
	elif type == "flowerbed":
		color = _color(palette.get("path", "#b7a178"), Color("b7a178")).darkened(0.38)
	elif type in ["hedge", "orchard", "crop"]:
		color = _color(palette.get("groundAlt", "#627d55"), Color("627d55")).darkened(0.12)
	elif type in ["wall", "cliff"]:
		color = _color(zone.get("color", palette.get("edge", "#38554c")), Color("38554c")).darkened(0.08)
	elif type == "dune":
		color = _color(zone.get("color", palette.get("path", "#b7a178")), Color("b7a178")).lightened(0.08)
	else:
		color = _color(zone.get("color", palette.get("groundAlt", "#7f9968")), Color("7f9968"))
	draw_rect(rect, color)
	var surface: Texture2D = _surface(surface_name)
	if surface != null:
		var surface_tint: Color = Color(0.93, 0.93, 0.86, 0.72)
		if surface_name == "water":
			surface_tint = Color(0.74, 0.92, 0.98, 0.82)
		_draw_tiled_surface(surface, rect, surface_tint)
	if type in ["pond", "canal", "water"]:
		for y: int in range(int(rect.position.y + 8), int(rect.end.y), 14):
			draw_line(Vector2(rect.position.x + 8, y), Vector2(rect.end.x - 8, y), color.lightened(0.12), 2.0)
	elif type in ["hedge", "orchard", "crop"]:
		_draw_vegetation_zone(rect, type, color)
	elif type == "flowerbed":
		_draw_flowerbed(rect, palette, color)
	elif type == "rug":
		_draw_rug(rect, palette, color)


func _draw_path(path: Dictionary, palette: Dictionary) -> void:
	var color: Color = _color(palette.get("path", "#b7a178"), Color("b7a178"))
	var style: String = str(path.get("style", ""))
	if style == "dirt":
		color = color.darkened(0.12)
	elif style == "marble":
		color = color.lightened(0.18)
	elif style == "ruin":
		color = color.darkened(0.2)
	var rect: Rect2 = _rect(path)
	draw_rect(rect, color)
	if style in ["cobble", "royal", "marble", "ruin", "market"]:
		var cobble: Texture2D = _surface("cobble")
		if cobble != null:
			var stone_tint := Color(0.93, 0.9, 0.8, 0.78)
			if style == "marble": stone_tint = Color(1.0, 0.98, 0.9, 0.62)
			elif style == "ruin": stone_tint = Color(0.68, 0.72, 0.66, 0.74)
			elif style == "market": stone_tint = Color(0.9, 0.78, 0.62, 0.62)
			_draw_tiled_surface(cobble, rect, stone_tint)
	elif style in ["dirt", "garden"]:
		for x: int in range(int(rect.position.x + 10), int(rect.end.x), 28):
			var y: float = rect.position.y + 9.0 + float((x / 7) % max(10, int(rect.size.y - 18)))
			draw_line(Vector2(x, y), Vector2(x + 7, y + 2), color.darkened(0.13), 1.0)
	draw_rect(rect.grow(-2), color.darkened(0.22), false, 2.0)
	draw_rect(rect.grow(-5), color.lightened(0.12), false, 1.0)


func _draw_building(building: Dictionary, palette: Dictionary) -> void:
	var rect: Rect2 = _rect(building)
	var id: String = str(building.get("id", ""))
	var texture: Texture2D = _asset(str(BUILDING_ASSETS.get(id, "")))
	if texture != null:
		draw_texture_rect(texture, Rect2(rect.position + Vector2(6, 8), rect.size), false, Color(0.08, 0.12, 0.14, 0.42))
		draw_texture_rect(texture, rect, false)
	else:
		var wall: Color = _color(building.get("wallColor", palette.get("wall", "#c2a777")), Color("c2a777"))
		var roof: Color = _color(building.get("roofColor", palette.get("roof", "#6e4a46")), Color("6e4a46"))
		draw_rect(rect, wall)
		draw_colored_polygon(PackedVector2Array([
			rect.position + Vector2(-8, rect.size.y * 0.24), rect.position + Vector2(rect.size.x * 0.5, -16),
			rect.position + Vector2(rect.size.x + 8, rect.size.y * 0.24), rect.position + Vector2(rect.size.x, rect.size.y * 0.43),
			rect.position + Vector2(0, rect.size.y * 0.43),
		]), roof)
	if building.has("label"):
		var label_position: Vector2 = rect.position + Vector2(8, rect.size.y - 10)
		draw_string(ThemeDB.fallback_font, label_position + Vector2(1, 2), str(building["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.05, 0.07, 0.08, 0.82))
		draw_string(ThemeDB.fallback_font, label_position, str(building["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f2dfb0"))


func _draw_furniture(item: Dictionary, palette: Dictionary) -> void:
	var type: String = str(item.get("type", item.get("id", "")))
	var asset_name: String = ""
	for key: String in FURNITURE_ASSETS.keys():
		if key in type:
			asset_name = str(FURNITURE_ASSETS[key])
			break
	var texture: Texture2D = _asset(asset_name)
	var rect: Rect2 = _rect(item)
	if texture != null:
		draw_texture_rect(texture, Rect2(rect.position + Vector2(3, 4), rect.size), false, Color(0.08, 0.1, 0.12, 0.36))
		draw_texture_rect(texture, rect, false)
	else:
		draw_rect(rect, _color(palette.get("edge", "#55453c"), Color("55453c")))
		draw_rect(rect.grow(-3), _color(palette.get("wall", "#a88662"), Color("a88662")), false, 2.0)


func _draw_decoration(item: Dictionary, palette: Dictionary) -> void:
	var asset_name: String = _decoration_asset(str(item.get("id", item.get("type", ""))))
	var texture: Texture2D = _asset(asset_name)
	var rect: Rect2 = _rect(item)
	if texture != null:
		draw_texture_rect(texture, Rect2(rect.position + Vector2(2, 3), rect.size), false, Color(0.08, 0.1, 0.12, 0.32))
		draw_texture_rect(texture, rect, false)
	else:
		var fallback: Color = _color(item.get("color", palette.get("accent", "#d4ac60")), Color("d4ac60"))
		var wash: Color = fallback
		wash.a = 0.16
		draw_rect(rect, wash)
		fallback.a = 0.62
		draw_rect(rect.grow(-1), fallback, false, 1.0)


func _draw_landmark(item: Dictionary, palette: Dictionary) -> void:
	var rect: Rect2 = _rect(item)
	var type: String = str(item.get("type", "marker"))
	var texture: Texture2D
	if type == "boat":
		texture = _asset("lm_boat")
	elif type == "ferry":
		texture = _asset("lm_ferry")
	else:
		texture = _asset(_decoration_asset(str(item.get("id", type))))
	if texture != null:
		draw_texture_rect(texture, Rect2(rect.position + Vector2(3, 4), rect.size), false, Color(0.08, 0.1, 0.12, 0.36))
		draw_texture_rect(texture, rect, false)
	else:
		var color: Color = _color(item.get("color", palette.get("accent", "#d4ac60")), Color("d4ac60"))
		var wash: Color = color.darkened(0.18)
		wash.a = 0.14
		draw_rect(rect, wash)
		color.a = 0.72
		draw_rect(rect.grow(-2), color, false, 2.0)
	if bool(item.get("interactive", false)):
		draw_circle(rect.position + Vector2(rect.size.x - 5, 5), 3.0, Color("f4d880"))


func _draw_portal(portal: Dictionary, palette: Dictionary) -> void:
	var rect: Rect2 = _rect(portal)
	var color: Color = _color(palette.get("accent", "#d4ac60"), Color("d4ac60"))
	if str(portal.get("type", "")) == "road":
		draw_line(rect.get_center() - Vector2(10, 0), rect.get_center() + Vector2(10, 0), color, 3.0)
	else:
		var portal_fill: Color = color
		portal_fill.a = 0.18
		draw_rect(rect, portal_fill)
		draw_rect(rect, color, false, 2.0)


func _draw_dynamic_story_marks(palette: Dictionary) -> void:
	var flags: Dictionary = game_state.get("flags", {}) as Dictionary
	var repairs: Dictionary = game_state.get("repairs", {}) as Dictionary
	if str(scene_data.get("id", "")) == "town" and bool(repairs.get("master", false)):
		draw_arc(Vector2(576, 154), 45, 0, TAU, 32, Color("f3d47b"), 3.0)
	if str(scene_data.get("id", "")) == "harbor" and bool(flags.get("low_tide", false)):
		draw_line(Vector2(1050, 520), Vector2(1240, 520), _color(palette.get("path", "#b7a178"), Color("b7a178")), 8.0)
	if str(scene_data.get("id", "")) == "clock-basement" and bool(flags.get("slot_seven_filled", false)):
		draw_rect(Rect2(635, 122, 48, 64), Color("d7b568"), false, 4.0)


func _asset(name: String) -> Texture2D:
	if name.is_empty():
		return null
	if _textures.has(name):
		return _textures[name] as Texture2D
	var path: String = "res://assets/images/%s.webp" % name
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_textures[name] = texture
	return texture


func _surface(name: String) -> Texture2D:
	if name.is_empty():
		return null
	var cache_key: String = "surface:%s" % name
	if _textures.has(cache_key):
		return _textures[cache_key] as Texture2D
	var path: String = str(SURFACE_ASSETS.get(name, ""))
	var texture: Texture2D = null
	if not path.is_empty() and ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_textures[cache_key] = texture
	return texture


func _draw_tiled_surface(texture: Texture2D, rect: Rect2, tint: Color) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * SURFACE_SCALE)
	draw_texture_rect(texture, Rect2(rect.position / SURFACE_SCALE, rect.size / SURFACE_SCALE), true, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_vegetation_zone(rect: Rect2, type: String, base: Color) -> void:
	if type == "hedge":
		for x: int in range(int(rect.position.x + 7), int(rect.end.x), 14):
			var leaf: Color = base.lightened(0.12 if int(x / 14) % 2 == 0 else 0.04)
			draw_circle(Vector2(x, rect.get_center().y), minf(8.0, rect.size.y * 0.42), leaf)
		return
	if type == "crop":
		for y: int in range(int(rect.position.y + 10), int(rect.end.y), 18):
			draw_line(Vector2(rect.position.x + 6, y), Vector2(rect.end.x - 6, y), base.darkened(0.15), 2.0)
			for x: int in range(int(rect.position.x + 12), int(rect.end.x), 24):
				draw_circle(Vector2(x, y - 2), 3.0, base.lightened(0.18))
		return
	for y: int in range(int(rect.position.y + 18), int(rect.end.y), 40):
		for x: int in range(int(rect.position.x + 18), int(rect.end.x), 40):
			var offset: float = 8.0 if int(y / 40) % 2 == 0 else 0.0
			draw_circle(Vector2(x + offset, y), 11.0, base.darkened(0.08))
			draw_circle(Vector2(x + offset - 3, y - 3), 7.0, base.lightened(0.14))


func _draw_flowerbed(rect: Rect2, palette: Dictionary, soil: Color) -> void:
	draw_rect(rect.grow(-2), soil.darkened(0.24), false, 2.0)
	var accent: Color = _color(palette.get("accent", "#d4ac60"), Color("d4ac60"))
	var rose: Color = Color("d77b88")
	for y: int in range(int(rect.position.y + 10), int(rect.end.y), 16):
		for x: int in range(int(rect.position.x + 10), int(rect.end.x), 16):
			var flower_position := Vector2(x + (8 if int(y / 16) % 2 == 0 else 0), y)
			draw_circle(flower_position + Vector2(-2, 2), 3.0, Color("496b43"))
			draw_circle(flower_position + Vector2(2, 2), 3.0, Color("587d4d"))
			draw_circle(flower_position, 2.5, accent if int((x + y) / 16) % 2 == 0 else rose)


func _draw_rug(rect: Rect2, palette: Dictionary, base: Color) -> void:
	var trim: Color = _color(palette.get("accent", "#d4ac60"), Color("d4ac60"))
	trim.a = 0.82
	draw_rect(rect.grow(-3), base.lightened(0.14), false, 3.0)
	draw_rect(rect.grow(-8), trim, false, 2.0)
	var motif: Color = trim.darkened(0.08)
	motif.a = 0.52
	for y: int in range(int(rect.position.y + 18), int(rect.end.y - 10), 28):
		for x: int in range(int(rect.position.x + 18), int(rect.end.x - 10), 36):
			var center := Vector2(x + (18 if int(y / 28) % 2 == 0 else 0), y)
			var diamond := PackedVector2Array([
				center + Vector2(0, -6), center + Vector2(9, 0), center + Vector2(0, 6),
				center + Vector2(-9, 0), center + Vector2(0, -6),
			])
			draw_polyline(diamond, motif, 1.0)


func _decoration_asset(id: String) -> String:
	if "lantern" in id or "lamp" in id: return "prop_lantern"
	if ["banner", "flag", "quilt", "curtain", "rug"].any(func(word: String) -> bool: return word in id): return "prop_banner"
	if "flower" in id or "herb" in id: return "prop_flowers"
	if "bucket" in id or "pail" in id or "basket" in id: return "prop_buckets"
	if "bush" in id or "hedge" in id: return "prop_bush"
	if "grass" in id or "reed" in id: return "prop_grasstuft"
	if "tree" in id: return "prop_tree"
	if "net" in id: return "prop_net"
	if "rope" in id: return "prop_rope"
	if "cart" in id: return "prop_cart"
	if "crate" in id: return "prop_cratestack" if "stack" in id else "prop_crate"
	if "portrait" in id or "frame" in id or "canvas" in id: return "prop_frame"
	if "rack" in id or "crank" in id or "tool" in id: return "prop_rack"
	if "sign" in id or "notice" in id or "board" in id: return "prop_sign"
	if "laundry" in id or "cloth" in id: return "prop_banner"
	return ""


func _rect(item: Dictionary) -> Rect2:
	return Rect2(
		float(item.get("x", 0.0)), float(item.get("y", 0.0)),
		float(item.get("w", item.get("width", 24.0))), float(item.get("h", item.get("height", 24.0)))
	)


func _color(value: Variant, fallback: Color) -> Color:
	return Color.from_string(str(value), fallback)
