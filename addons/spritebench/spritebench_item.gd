@tool
class_name SpriteBenchItem
extends Resource

@export var key: StringName = &""
@export var as_array: bool = false
@export var texture: Texture2D
@export var textures: Array[Texture2D] = []
@export_storage var slot_id: String = ""


func ensure_slot_id() -> String:
	if slot_id.strip_edges().is_empty():
		slot_id = preload("hasher.gd").uuid_v4()
	return slot_id
