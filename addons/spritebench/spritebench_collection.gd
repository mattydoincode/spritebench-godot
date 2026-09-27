@tool
class_name SpriteBenchCollection
extends Resource

## A table of keyed records with named art fields, synced with SpriteBench.
## Godot owns `fields`; records can be added, renamed or deleted from either
## side. Each (record, field) is its own SpriteBench slot.

@export_storage var id: String = ""
## Shown in SpriteBench. Defaults to the file name.
@export var label: String = ""
@export var fields: Array[SpriteBenchField] = []
@export var records: Array[SpriteBenchRecord] = []

@export_group("Import")
## For art drawn on 3D surfaces (building faces): mipmaps and VRAM
## compression, so it does not shimmer when shrunk or seen at an angle.
## Leave off for pixel art, which wants exact, uncompressed pixels.
@export var for_3d: bool = false
## Largest side after import, in pixels. 0 keeps the source size.
@export_range(0, 8192, 1) var max_size: int = 0


## Mints missing ids, and splits records that share an id (or an instance)
## after a duplicate in the inspector. Returns true when anything changed.
func ensure_ids() -> bool:
	var dirty := false
	if id.strip_edges().is_empty():
		id = preload("hasher.gd").uuid_v4()
		dirty = true
	var seen := {}
	for i in records.size():
		var record := records[i]
		if record == null:
			continue
		if seen.has(record.id) and not record.id.is_empty():
			record = record.duplicate(true) as SpriteBenchRecord
			record.id = ""
			records[i] = record
		var before := record.id
		record.ensure_id()
		if before != record.id:
			dirty = true
		if String(record.key).is_empty():
			record.key = StringName("record_%s" % record.id.substr(0, 8))
			dirty = true
		seen[record.id] = true
	return dirty


func record_by_id(record_id: String) -> SpriteBenchRecord:
	for record in records:
		if record and record.id == record_id:
			return record
	return null


func record_by_key(record_key: StringName) -> SpriteBenchRecord:
	for record in records:
		if record and record.key == record_key:
			return record
	return null


func field(field_key: StringName) -> SpriteBenchField:
	for entry in fields:
		if entry and entry.key == field_key:
			return entry
	return null


func record_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for record in records:
		if record and not record.id.is_empty():
			out.append(record.id)
	return out


func record_keys() -> Array[StringName]:
	var out: Array[StringName] = []
	for record in records:
		if record:
			out.append(record.key)
	return out
