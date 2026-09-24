@tool
class_name SpriteBenchSet
extends Resource

@export var items: Array[SpriteBenchItem] = []


func get_texture(key: StringName) -> Texture2D:
	for item in items:
		if item and item.key == key:
			return item.texture
	return null


func get_textures(key: StringName) -> Array[Texture2D]:
	for item in items:
		if item and item.key == key:
			return item.textures
	return []


func item_for_key(key: StringName) -> SpriteBenchItem:
	for item in items:
		if item and item.key == key:
			return item
	return null


func has_key(key: StringName) -> bool:
	return item_for_key(key) != null


func keys() -> Array[StringName]:
	var out: Array[StringName] = []
	for item in items:
		if item and item.key != &"":
			out.append(item.key)
	return out
