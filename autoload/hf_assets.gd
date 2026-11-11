extends Node

const SPRITE_ROOT := "res://assets/game/sprites/"
const TITLE_ART := "res://assets/game/art/title_hearthfall.png"

var _cache: Dictionary = {}
var _title: Texture2D

func tex(asset_name: String) -> Texture2D:
	if asset_name.is_empty():
		return null
	if _cache.has(asset_name):
		return _cache[asset_name]
	var path := SPRITE_ROOT + asset_name + ".png"
	if not ResourceLoader.exists(path):
		push_warning("Hearthfall asset missing: " + path)
		_cache[asset_name] = null
		return null
	var texture := load(path) as Texture2D
	if texture != null:
		texture.set_meta("nearest", true)
	_cache[asset_name] = texture
	return texture

func title_art() -> Texture2D:
	if _title == null and ResourceLoader.exists(TITLE_ART):
		_title = load(TITLE_ART) as Texture2D
	return _title

func resource_icon(resource_id: String) -> Texture2D:
	var def: Dictionary = HFDefs.RESOURCES.get(resource_id, {})
	return tex(str(def.get("icon", resource_id)))

func building_icon(building_id: String) -> Texture2D:
	var def: Dictionary = HFDefs.BUILDINGS.get(building_id, {})
	return tex(str(def.get("icon", building_id)))

func clear_cache() -> void:
	_cache.clear()
