@tool
class_name SpriteBenchRecord
extends Resource

## One row of a SpriteBenchCollection: a key plus art per field.

@export_storage var id: String = ""
@export var key: StringName = &""
@export var textures: Dictionary[StringName, Texture2D] = {}
@export var arrays: Dictionary[StringName, Array] = {}


func ensure_id() -> String:
	if id.strip_edges().is_empty():
		id = preload("hasher.gd").uuid_v4()
	return id


func get_texture(field: StringName) -> Texture2D:
	return textures.get(field, null)


func get_textures(field: StringName) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for value in arrays.get(field, []):
		if value is Texture2D:
			out.append(value)
	if out.is_empty() and textures.has(field) and textures[field] != null:
		out.append(textures[field])
	return out


func set_texture(field: StringName, texture: Texture2D) -> void:
	textures[field] = texture
	emit_changed()


func set_textures(field: StringName, list: Array[Texture2D]) -> void:
	arrays[field] = list
	emit_changed()
