@tool
extends EditorInspectorPlugin

signal slot_changed

const Credentials := preload("credentials.gd")
const Hasher := preload("hasher.gd")


func _can_handle(object: Object) -> bool:
	return object is Sprite2D or object is AnimatedSprite2D


func _parse_begin(object: Object) -> void:
	var row := HBoxContainer.new()
	var box := CheckBox.new()
	box.text = "SpriteBench slot"
	box.tooltip_text = "Opt this sprite into SpriteBench sync. Checking pushes the catalog immediately."
	box.set_pressed_no_signal(object.has_meta(Credentials.SLOT_META))
	box.toggled.connect(func(enabled: bool) -> void:
		_toggle(object, enabled)
	)
	row.add_child(box)

	if object.has_meta(Credentials.SLOT_META):
		var id := Label.new()
		id.text = str(object.get_meta(Credentials.SLOT_META))
		id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		id.clip_text = true
		id.modulate = Color(1, 1, 1, 0.55)
		row.add_child(id)

	add_custom_control(row)


func _toggle(object: Object, enabled: bool) -> void:
	var undo := EditorInterface.get_editor_undo_redo()
	if enabled:
		var existing := ""
		if object.has_meta(Credentials.SLOT_META):
			existing = str(object.get_meta(Credentials.SLOT_META))
		var id := existing if _is_uuid(existing) else Hasher.uuid_v4()
		undo.create_action("Enable SpriteBench slot")
		undo.add_do_method(object, "set_meta", Credentials.SLOT_META, id)
		if object.has_meta(Credentials.SLOT_META):
			undo.add_undo_method(object, "set_meta", Credentials.SLOT_META, existing)
		else:
			undo.add_undo_method(object, "remove_meta", Credentials.SLOT_META)
	else:
		var previous := str(object.get_meta(Credentials.SLOT_META)) if object.has_meta(Credentials.SLOT_META) else ""
		undo.create_action("Disable SpriteBench slot")
		undo.add_do_method(object, "remove_meta", Credentials.SLOT_META)
		if not previous.is_empty():
			undo.add_undo_method(object, "set_meta", Credentials.SLOT_META, previous)
	undo.add_do_method(EditorInterface, "mark_scene_as_unsaved")
	undo.add_undo_method(EditorInterface, "mark_scene_as_unsaved")
	undo.commit_action()
	slot_changed.emit()


func _is_uuid(value: String) -> bool:
	var re := RegEx.new()
	re.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
	return re.search(value) != null
