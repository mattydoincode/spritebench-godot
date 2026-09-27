@tool
extends EditorPlugin

const Credentials := preload("credentials.gd")
const Hasher := preload("hasher.gd")
const ApiScript := preload("api.gd")
const InspectorScript := preload("inspector.gd")

var _api: Node
var _inspector: EditorInspectorPlugin
var _dock: Control
var _base_url: LineEdit
var _pat: LineEdit
var _project_id: LineEdit
var _output_dir: LineEdit
var _status: Label
var _log: TextEdit
var _check_btn: Button
var _sync_btn: Button
var _syncing := false
var _sync_queued := false
var _draining := false
var _reimport_pending := 0
## Slot path (a PNG, or a bag directory) → import profile, from the last
## collect. Paths not listed get the pixel-art defaults.
var _import_profiles := {}


func _enter_tree() -> void:
	Credentials.ensure_registered()
	_api = ApiScript.new()
	add_child(_api)
	_inspector = InspectorScript.new()
	_inspector.slot_changed.connect(_request_sync)
	add_inspector_plugin(_inspector)
	add_custom_type("SpriteBenchItem", "Resource", preload("spritebench_item.gd"), null)
	add_custom_type("SpriteBenchSet", "Resource", preload("spritebench_set.gd"), null)
	add_custom_type("SpriteBenchField", "Resource", preload("spritebench_field.gd"), null)
	add_custom_type("SpriteBenchRecord", "Resource", preload("spritebench_record.gd"), null)
	add_custom_type("SpriteBenchCollection", "Resource", preload("spritebench_collection.gd"), null)
	_dock = _build_dock()
	add_control_to_dock(DOCK_SLOT_LEFT_UR, _dock)
	_hook_filesystem()
	_load_fields()


func _exit_tree() -> void:
	_set_busy(false)
	_sync_queued = false
	if _inspector.slot_changed.is_connected(_request_sync):
		_inspector.slot_changed.disconnect(_request_sync)
	remove_inspector_plugin(_inspector)
	remove_custom_type("SpriteBenchCollection")
	remove_custom_type("SpriteBenchRecord")
	remove_custom_type("SpriteBenchField")
	remove_custom_type("SpriteBenchSet")
	remove_custom_type("SpriteBenchItem")
	remove_control_from_docks(_dock)
	_dock.free()
	_dock = null
	_unhook_filesystem()
	_api.queue_free()
	_api = null


func _save_external_data() -> void:
	if not Credentials.is_configured():
		return
	_request_sync()


func _request_sync() -> void:
	if not Credentials.is_configured():
		_set_status("Need a PAT and project id.")
		return
	_sync_queued = true
	if _draining or _syncing:
		return
	_draining = true
	var tree := get_tree()
	if tree:
		await tree.process_frame
	if not is_inside_tree():
		_draining = false
		return
	while _sync_queued:
		_sync_queued = false
		await _sync()
	_draining = false


func _get_plugin_name() -> String:
	return "SpriteBench"


func _build_dock() -> Control:
	var root := MarginContainer.new()
	root.name = "SpriteBench"
	root.add_theme_constant_override("margin_left", 8)
	root.add_theme_constant_override("margin_right", 8)
	root.add_theme_constant_override("margin_top", 8)
	root.add_theme_constant_override("margin_bottom", 8)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)

	_base_url = _add_field(col, "API URL")
	_pat = _add_field(col, "Personal access token")
	_pat.secret = true
	_project_id = _add_field(col, "Project ID")
	_output_dir = _add_field(col, "Output folder")

	var buttons := HBoxContainer.new()
	_check_btn = Button.new()
	_check_btn.text = "Check"
	_check_btn.pressed.connect(_check)
	_sync_btn = Button.new()
	_sync_btn.text = "Sync"
	_sync_btn.pressed.connect(_sync)
	buttons.add_child(_check_btn)
	buttons.add_child(_sync_btn)
	col.add_child(buttons)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Paste a PAT from SpriteBench Settings."
	col.add_child(_status)

	_log = TextEdit.new()
	_log.editable = false
	_log.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_log.custom_minimum_size = Vector2(0, 180)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_log)
	return root


func _add_field(parent: VBoxContainer, title: String) -> LineEdit:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var edit := LineEdit.new()
	parent.add_child(edit)
	return edit


func _load_fields() -> void:
	_base_url.text = Credentials.base_url()
	_pat.text = Credentials.pat()
	_project_id.text = Credentials.project_id()
	_output_dir.text = Credentials.output_dir()


func _save_fields() -> void:
	Credentials.set_base_url(_base_url.text)
	Credentials.set_pat(_pat.text)
	Credentials.set_project_id(_project_id.text)
	Credentials.set_output_dir(_output_dir.text)
	_load_fields()


func _set_busy(busy: bool) -> void:
	_syncing = busy
	if _check_btn:
		_check_btn.disabled = busy
	if _sync_btn:
		_sync_btn.disabled = busy
	var tree := get_tree()
	if tree == null:
		return
	if busy:
		tree.set_meta("spritebench_busy", true)
	elif tree.has_meta("spritebench_busy"):
		tree.remove_meta("spritebench_busy")


func _set_status(text: String) -> void:
	_status.text = text


func _log_line(text: String) -> void:
	if _log.text.is_empty():
		_log.text = text
	else:
		_log.text += "\n" + text
	_log.scroll_vertical = _log.get_line_count()


func _check() -> void:
	if _syncing:
		return
	_save_fields()
	_set_busy(true)
	_log.text = ""
	_set_status("Checking…")
	var me: Dictionary = await _api.get_json("/api/v1/me")
	if not me.ok:
		_set_status(me.error)
		_set_busy(false)
		return
	var user: Dictionary = me.data.get("user", {})
	var who := str(user.get("email", user.get("name", "signed in")))
	var projects: Dictionary = await _api.get_json("/api/v1/projects")
	if not projects.ok:
		_set_status("%s. %s" % [who, projects.error])
		_set_busy(false)
		return
	var project_id := Credentials.project_id()
	var name := ""
	for project in projects.data.get("projects", []):
		if str(project.get("id", "")) == project_id:
			name = str(project.get("name", ""))
			break
	if project_id.is_empty():
		_set_status("%s. Set a project id (Engine panel in SpriteBench)." % who)
	elif name.is_empty():
		_set_status("%s. Project %s is not in this account." % [who, project_id])
	else:
		_set_status("%s · %s" % [who, name])
	_set_busy(false)


func _sync() -> void:
	if _syncing:
		return
	_save_fields()
	if not Credentials.is_configured():
		_set_status("Need a PAT and project id.")
		return
	_set_busy(true)
	_log.text = ""
	_set_status("Syncing…")

	var slots := _collect_slots()
	await _apply_import_profiles()
	var catalog := await _push_catalog(slots)
	if catalog.is_empty():
		_set_busy(false)
		return

	# Assets, lists and tables made in SpriteBench become resources first, then
	# records added, renamed or deleted there land in them, so the pull below
	# has a local slot to assign each field into.
	var made := _apply_web_assets(catalog)
	if made > 0:
		_log_line("wrote %s changes from SpriteBench-made assets" % made)
	var changed := made + _apply_collections(catalog.get("collections", []))
	if changed > 0:
		_log_line("updated %s records from SpriteBench" % changed)
		slots = _collect_slots()
		catalog = await _push_catalog(slots)
		if catalog.is_empty():
			_set_busy(false)
			return

	_report_catalog(catalog.get("slots", []))
	var pulled := await _pull_and_write(slots)
	if pulled < 0:
		_set_busy(false)
		return

	if pulled > 0:
		slots = _collect_slots()
		catalog = await _push_catalog(slots)
		if catalog.is_empty():
			_set_busy(false)
			return

	var filled := _fill_missing_textures(_collect_slots())
	var fs := EditorInterface.get_resource_filesystem()
	if _fs_busy(fs):
		await _wait_fs_idle(fs)
		filled += _fill_missing_textures(_collect_slots())
	var slot_count := slots.filter(func(slot: Dictionary) -> bool: return not slot.has("collection")).size()
	_set_status("Synced %s slots, pulled %s." % [slot_count, pulled])
	if filled > 0:
		_log_line("assigned %s on-disk textures" % filled)
	_set_busy(false)


## Returns the response body (`slots`, `collections`), or {} on failure.
func _push_catalog(slots: Array[Dictionary]) -> Dictionary:
	var payload: Array = []
	for slot in slots:
		if slot.has("collection"):
			continue
		payload.append({
			"id": slot.id,
			"kind": slot.kind,
			"intent": slot.intent,
			"label": slot.label,
			"path": slot.path,
			"localHash": slot.localHash,
		})
	var collections: Array = []
	for slot in slots:
		if slot.has("collection"):
			collections.append(slot.collection)
	var response: Dictionary = await _api.post_json(
		"/api/v1/projects/%s/slots" % Credentials.project_id(),
		{"slots": payload, "collections": collections, "lane": Credentials.art()}
	)
	if not response.ok:
		_set_status(response.error)
		_log_line(response.error)
		return {}
	var data: Dictionary = response.data if typeof(response.data) == TYPE_DICTIONARY else {}
	if not data.has("slots"):
		data["slots"] = []
	return data


## Makes each local collection match SpriteBench: adds records created there,
## takes keys renamed there, and drops records deleted there. Returns how
## many records changed.
func _apply_collections(rows: Array) -> int:
	var changed := 0
	var paths := _collection_paths()
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var path := str(paths.get(str(row.get("id", "")), ""))
		if path.is_empty():
			continue
		var res := ResourceLoader.load(path)
		if not res is SpriteBenchCollection:
			continue
		var collection := res as SpriteBenchCollection
		var dirty := 0
		for removed in row.get("removedRecordIds", []):
			var gone := collection.record_by_id(str(removed))
			if gone:
				collection.records.erase(gone)
				_log_line("removed %s from %s" % [gone.key, path.get_file()])
				dirty += 1
		for entry in row.get("records", []):
			var record_id := str(entry.get("id", ""))
			var key := StringName(str(entry.get("key", "")))
			var local := collection.record_by_id(record_id)
			if local == null:
				local = SpriteBenchRecord.new()
				local.id = record_id
				local.key = key
				collection.records.append(local)
				_log_line("added %s to %s" % [key, path.get_file()])
				dirty += 1
			elif bool(entry.get("pending", false)) and local.key != key:
				_log_line("renamed %s to %s" % [local.key, key])
				local.key = key
				dirty += 1
		if dirty > 0:
			collection.emit_changed()
			_save(collection, path)
			changed += dirty
	return changed


## Writes what was made in SpriteBench into the project: standalone assets and
## lists into `assets.tres` (a SpriteBenchSet that SpriteBench manages), and
## each SpriteBench-made table into `tables/<name>.tres` with SpriteBench's
## name and fields. Returns how many things changed.
func _apply_web_assets(catalog: Dictionary) -> int:
	var changed := 0
	var dir := Credentials.output_dir()
	var web_slots: Array = []
	for row in catalog.get("slots", []):
		if typeof(row) != TYPE_DICTIONARY or str(row.get("origin", "")) != "web":
			continue
		var kind := str(row.get("kind", ""))
		if kind == "set_item" or kind == "set_bag":
			web_slots.append(row)
	var assets_path := dir.path_join("assets.tres")
	if not web_slots.is_empty() or ResourceLoader.exists(assets_path):
		changed += _sync_assets_set(assets_path, web_slots)
	var paths := _collection_paths()
	for row in catalog.get("collections", []):
		if typeof(row) == TYPE_DICTIONARY and str(row.get("origin", "")) == "web":
			changed += _sync_web_table(row, paths, dir)
	return changed


func _sync_assets_set(path: String, rows: Array) -> int:
	var set_res: SpriteBenchSet
	if ResourceLoader.exists(path):
		var loaded := ResourceLoader.load(path)
		if not loaded is SpriteBenchSet:
			_log_line("%s is not a SpriteBenchSet; leaving it alone" % path)
			return 0
		set_res = loaded as SpriteBenchSet
	else:
		set_res = SpriteBenchSet.new()
	var wanted := {}
	var dirty := 0
	for row in rows:
		var id := str(row.get("id", ""))
		var key := StringName(str(row.get("label", "")))
		var list := str(row.get("kind", "")) == "set_bag"
		wanted[id] = true
		var item: SpriteBenchItem = null
		for existing in set_res.items:
			if existing and existing.slot_id == id:
				item = existing
				break
		if item == null:
			item = SpriteBenchItem.new()
			item.slot_id = id
			item.key = key
			item.as_array = list
			set_res.items.append(item)
			_log_line("added %s to assets.tres" % key)
			dirty += 1
		elif item.key != key or item.as_array != list:
			item.key = key
			item.as_array = list
			dirty += 1
	# SpriteBench manages this file: anything it no longer lists goes.
	for existing in set_res.items.duplicate():
		if existing and not wanted.has(existing.slot_id):
			set_res.items.erase(existing)
			_log_line("removed %s from assets.tres" % existing.key)
			dirty += 1
	if dirty > 0:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		_save(set_res, path)
	return dirty


func _sync_web_table(row: Dictionary, paths: Dictionary, dir: String) -> int:
	var id := str(row.get("id", ""))
	var label := str(row.get("label", "table"))
	var path := str(paths.get(id, ""))
	var collection: SpriteBenchCollection
	var dirty := 0
	if path.is_empty():
		path = dir.path_join("tables").path_join("%s.tres" % label)
		collection = SpriteBenchCollection.new()
		collection.id = id
		_log_line("created %s" % path.get_file())
		dirty += 1
	else:
		collection = ResourceLoader.load(path) as SpriteBenchCollection
		if collection == null:
			return 0
	if collection.label != label:
		collection.label = label
		dirty += 1
	var incoming: Array = row.get("fields", [])
	var same := collection.fields.size() == incoming.size()
	var fields: Array[SpriteBenchField] = []
	for i in incoming.size():
		var field := SpriteBenchField.new()
		field.key = StringName(str(incoming[i].get("key", "")))
		field.as_array = str(incoming[i].get("intent", "")) == "textures"
		fields.append(field)
		var current := collection.fields[i] if same else null
		if same and (current == null or current.key != field.key or current.as_array != field.as_array):
			same = false
	if not same:
		collection.fields = fields
		dirty += 1
	if dirty > 0:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		_save(collection, path)
	return dirty


func _collection_paths() -> Dictionary:
	var out := {}
	for path in _walk("res://", [".tres", ".res"]):
		if not _looks_like(path, "SpriteBenchCollection"):
			continue
		var res := ResourceLoader.load(path)
		if res is SpriteBenchCollection:
			out[(res as SpriteBenchCollection).id] = path
	return out


func _report_catalog(rows: Array) -> void:
	var edited := 0
	var conflicts := 0
	for row in rows:
		var status := str(row.get("status", ""))
		var label := str(row.get("label", row.get("id", "")))
		if status == "edited_in_godot":
			edited += 1
			_log_line("edited in Godot: %s" % label)
		elif status == "conflict":
			conflicts += 1
			_log_line("conflict: %s" % label)
	_log_line("catalog %s slots" % rows.size())


func _pull_and_write(local_slots: Array[Dictionary]) -> int:
	var by_id := {}
	for slot in local_slots:
		by_id[slot.id] = slot
	var response: Dictionary = await _api.get_json(
		"/api/v1/projects/%s/slots/pull" % Credentials.project_id()
	)
	if not response.ok:
		_set_status(response.error)
		_log_line(response.error)
		return -1
	var pending: Array[Dictionary] = []
	var paths := PackedStringArray()
	for item in response.data.get("slots", []):
		var id := str(item.get("id", ""))
		var local: Dictionary = by_id.get(id, {})
		var staged := await _stage_slot(item, local)
		if staged.is_empty():
			continue
		pending.append(staged)
		for path in staged.paths:
			paths.append(path)
	await _import_paths(paths)
	var pulled := 0
	for row in pending:
		if _commit_slot(row):
			pulled += 1
	return pulled


func _stage_slot(item: Dictionary, local: Dictionary) -> Dictionary:
	var bundle: Variant = item.get("bundle", {})
	if typeof(bundle) == TYPE_DICTIONARY and not (bundle as Dictionary).is_empty():
		return await _stage_bundle(item, local, bundle as Dictionary)

	var id := str(item.get("id", ""))
	var url := str(item.get("url", ""))
	var remote_hash := str(item.get("remoteHash", ""))
	var dest := str(item.get("godotPath", ""))
	if dest.is_empty() or not dest.begins_with("res://"):
		dest = Credentials.png_path(id)
	var download: Dictionary = await _api.download(url)
	if not download.ok:
		_log_line("pull failed %s: %s" % [id, download.error])
		return {}
	var bytes: PackedByteArray = download.bytes
	if not remote_hash.is_empty() and Hasher.bytes_sha256(bytes) != remote_hash:
		_log_line("hash mismatch %s" % id)
		return {}
	if _write_png(dest, bytes) != OK:
		_log_line("could not write %s" % dest)
		return {}
	return {
		"kind": "texture",
		"local": local,
		"dest": dest,
		"bytes": bytes,
		"paths": PackedStringArray([dest]),
	}


func _stage_bundle(item: Dictionary, local: Dictionary, bundle: Dictionary) -> Dictionary:
	var id := str(item.get("id", ""))
	var remote_hash := str(item.get("remoteHash", ""))
	var dest := str(item.get("godotPath", ""))
	if dest.is_empty() or not dest.begins_with("res://") or dest.ends_with(".png"):
		dest = Credentials.slot_dir(id)
	dest = dest.rstrip("/")

	var format := str(bundle.get("format", ""))
	var keep := {}
	var hashed_clips: Array = []
	var hashed_bag := PackedStringArray()
	var paths := PackedStringArray()

	if format == "spritebench.clips/1":
		for clip in bundle.get("clips", []):
			var frames: Array = []
			for frame in clip.get("frames", []):
				var written := await _download_frame(dest, frame)
				if written.is_empty():
					return {}
				keep[written.file] = true
				paths.append(dest.path_join(str(written.file)))
				frames.append(written)
			hashed_clips.append({
				"name": str(clip.get("name", "")),
				"fps": int(clip.get("fps", 6)),
				"loop": bool(clip.get("loop", true)),
				"frames": frames,
			})
		if not remote_hash.is_empty() and Hasher.sprite_frames_bundle_hash(hashed_clips) != remote_hash:
			_log_line("hash mismatch %s" % id)
			return {}
		_write_manifest(dest, _clips_manifest(hashed_clips))
		_prune_slot_dir(dest, keep)
		return {
			"kind": "clips",
			"local": local,
			"dest": dest,
			"clips": hashed_clips,
			"paths": paths,
		}

	if format == "spritebench.bag/1":
		var files: Array = []
		for frame in bundle.get("frames", []):
			var written := await _download_frame(dest, frame)
			if written.is_empty():
				return {}
			keep[written.file] = true
			hashed_bag.append(str(written.sha256))
			files.append(written.file)
			paths.append(dest.path_join(str(written.file)))
		if not remote_hash.is_empty() and Hasher.textures_bundle_hash(hashed_bag) != remote_hash:
			_log_line("hash mismatch %s" % id)
			return {}
		var bag_rows: Array = []
		for file in files:
			bag_rows.append({ "file": file })
		_write_manifest(dest, { "format": "spritebench.bag/1", "frames": bag_rows })
		_prune_slot_dir(dest, keep)
		return {
			"kind": "bag",
			"local": local,
			"dest": dest,
			"files": files,
			"paths": paths,
		}

	_log_line("unknown bundle %s" % id)
	return {}


func _download_frame(dest: String, frame: Dictionary) -> Dictionary:
	var file := str(frame.get("file", ""))
	var url := str(frame.get("url", ""))
	if file.is_empty() or url.is_empty():
		return {}
	var download: Dictionary = await _api.download(url)
	if not download.ok:
		_log_line("pull failed %s: %s" % [file, download.error])
		return {}
	var path := dest.path_join(file)
	if _write_png(path, download.bytes) != OK:
		_log_line("could not write %s" % path)
		return {}
	return {
		"file": file,
		"hold": int(frame.get("hold", 1)),
		"sha256": Hasher.bytes_sha256(download.bytes),
	}


func _commit_slot(row: Dictionary) -> bool:
	var kind := str(row.get("kind", ""))
	if kind == "texture":
		var dest := str(row.dest)
		var texture := _imported_texture(dest)
		if texture == null:
			_log_line("waiting for import: %s" % dest)
			return false
		_assign_texture(row.local, texture)
		_log_line("pulled %s" % dest)
		return true
	if kind == "clips":
		_assign_sprite_frames(row.local, row.dest, row.clips)
		_log_line("pulled %s" % row.dest)
		return true
	if kind == "bag":
		_assign_bag(row.local, row.dest, row.files)
		_log_line("pulled %s" % row.dest)
		return true
	return false


func _clips_manifest(clips: Array) -> Dictionary:
	var rows: Array = []
	for clip in clips:
		var frames: Array = []
		for frame in clip.get("frames", []):
			frames.append({ "file": frame.file, "hold": int(frame.get("hold", 1)) })
		rows.append({
			"name": str(clip.get("name", "")),
			"fps": int(clip.get("fps", 6)),
			"loop": bool(clip.get("loop", true)),
			"frames": frames,
		})
	return { "format": "spritebench.clips/1", "clips": rows }


func _write_manifest(dir: String, data: Dictionary) -> void:
	var path := dir.path_join("manifest.json")
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if err != OK and err != ERR_ALREADY_EXISTS:
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "\t"))


func _prune_slot_dir(dir: String, keep: Dictionary) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	for name in access.get_files():
		if name.ends_with(".png") and not keep.has(name):
			access.remove(name)


func _write_png(path: String, bytes: PackedByteArray) -> Error:
	var dir := path.get_base_dir()
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	_ensure_pinned_import(path)
	return OK


func _import_paths(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	var fs := EditorInterface.get_resource_filesystem()
	for path in paths:
		_ensure_pinned_import(path)
	await _wait_fs_idle(fs)
	var needs_scan := false
	for path in paths:
		if fs.get_filesystem_path(path.get_base_dir()) == null:
			needs_scan = true
		fs.update_file(path)
	if needs_scan:
		fs.scan()
	# A pull that overwrites a file keeps its old import on record, and
	# `update_file` alone does not replace it; without this the old art stays
	# in the cache and gets assigned as if it were the new one.
	await _wait_fs_idle(fs)
	var stale := PackedStringArray()
	for path in paths:
		if not _import_current(path):
			stale.append(path)
	if not stale.is_empty():
		fs.reimport_files(stale)
	await _wait_paths_imported(fs, paths)
	for path in paths:
		if ResourceLoader.has_cached(path):
			ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)


func _hook_filesystem() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if not fs.resources_reimporting.is_connected(_on_resources_reimporting):
		fs.resources_reimporting.connect(_on_resources_reimporting)
	if not fs.resources_reimported.is_connected(_on_resources_reimported):
		fs.resources_reimported.connect(_on_resources_reimported)


func _unhook_filesystem() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs.resources_reimporting.is_connected(_on_resources_reimporting):
		fs.resources_reimporting.disconnect(_on_resources_reimporting)
	if fs.resources_reimported.is_connected(_on_resources_reimported):
		fs.resources_reimported.disconnect(_on_resources_reimported)
	_reimport_pending = 0


func _on_resources_reimporting(_files: PackedStringArray) -> void:
	_reimport_pending += 1


func _on_resources_reimported(_files: PackedStringArray) -> void:
	_reimport_pending = maxi(0, _reimport_pending - 1)


func _fs_busy(fs: EditorFileSystem) -> bool:
	if fs.is_scanning() or _reimport_pending > 0:
		return true
	return fs.has_method("is_importing") and fs.is_importing()


func _wait_fs_idle(fs: EditorFileSystem) -> void:
	await get_tree().process_frame
	var deadline := Time.get_ticks_msec() + 20000
	while _fs_busy(fs) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


## Waits while imports keep landing. Gives up after 30 s with no progress or
## 10 min in all, so a big batch of large images is not cut off mid-import.
func _wait_paths_imported(fs: EditorFileSystem, paths: PackedStringArray) -> void:
	await get_tree().process_frame
	var started := Time.get_ticks_msec()
	var last_progress := started
	var done := -1
	while Time.get_ticks_msec() - last_progress < 30000 and Time.get_ticks_msec() - started < 600000:
		var imported := 0
		for path in paths:
			if _import_current(path):
				imported += 1
		if imported != done:
			done = imported
			last_progress = Time.get_ticks_msec()
			if paths.size() > 4:
				_set_status("Importing %s/%s…" % [imported, paths.size()])
		if imported == paths.size() and not _fs_busy(fs):
			await get_tree().process_frame
			if not _fs_busy(fs):
				return
		await get_tree().process_frame


func _import_profile(png_path: String) -> Dictionary:
	if _import_profiles.has(png_path):
		return _import_profiles[png_path]
	return _import_profiles.get(png_path.get_base_dir(), {})


## Pixel art: lossless, no mipmaps. 3D art: VRAM-compressed with mipmaps.
func _import_params(profile: Dictionary) -> Dictionary:
	var for_3d := bool(profile.get("for_3d", false))
	return {
		"compress/mode": 2 if for_3d else 0,
		"mipmaps/generate": for_3d,
		"detect_3d/compress_to": 0,
		"process/size_limit": int(profile.get("max_size", 0)),
	}


## Returns true when the settings changed, meaning a reimport is due.
func _ensure_pinned_import(png_path: String) -> bool:
	var import_path := png_path + ".import"
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(import_path):
		cfg.load(import_path)
	if str(cfg.get_value("remap", "importer", "")).is_empty():
		cfg.set_value("remap", "importer", "texture")
		cfg.set_value("remap", "type", "CompressedTexture2D")
	var changed := false
	var params := _import_params(_import_profile(png_path))
	for key in params:
		if cfg.get_value("params", key, null) != params[key]:
			cfg.set_value("params", key, params[key])
			changed = true
	if changed or not FileAccess.file_exists(import_path):
		cfg.save(import_path)
	return changed


## Brings files already on disk in line with their slot's import profile,
## so switching a collection to 3D reimports what was pulled before.
func _apply_import_profiles() -> void:
	var changed := PackedStringArray()
	for path in _import_profiles:
		var files := PackedStringArray()
		if str(path).ends_with(".png"):
			if FileAccess.file_exists(path):
				files.append(path)
		else:
			for name in DirAccess.get_files_at(path):
				if name.ends_with(".png"):
					files.append(str(path).path_join(name))
		for file in files:
			if FileAccess.file_exists(file + ".import") and _ensure_pinned_import(file):
				changed.append(file)
	if changed.is_empty():
		return
	_log_line("reimporting %s images with new import settings" % changed.size())
	var fs := EditorInterface.get_resource_filesystem()
	await _wait_fs_idle(fs)
	fs.reimport_files(changed)
	await _wait_paths_imported(fs, changed)


## True when Godot's import of `png_path` was made from the file as it is on
## disk now, going by the source checksum Godot keeps next to the import.
func _import_current(png_path: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(png_path + ".import") != OK or not cfg.has_section("remap"):
		return false
	var dest := ""
	for key in cfg.get_section_keys("remap"):
		if key == "path" or str(key).begins_with("path."):
			dest = str(cfg.get_value("remap", key, ""))
			if not dest.is_empty():
				break
	if dest.is_empty():
		return false
	var md5_path := dest.substr(0, dest.find(".", dest.rfind("-"))) + ".md5"
	var md5 := ConfigFile.new()
	if md5.load(md5_path) != OK:
		return false
	return str(md5.get_value("", "source_md5", "")) == FileAccess.get_md5(png_path)


func _imported_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var loaded := ResourceLoader.load(path)
	if loaded is Texture2D and _is_file_backed(loaded):
		return loaded
	return null


func _is_file_backed(resource: Resource) -> bool:
	var path := resource.resource_path
	return path.begins_with("res://") and not "::" in path


## Last line of defence before a save: drops any texture that would be
## embedded. Returns how many were dropped.
func _strip_embedded(res: Resource) -> int:
	var dropped := 0
	if res is SpriteBenchCollection:
		for record in (res as SpriteBenchCollection).records:
			if record == null:
				continue
			for field in record.textures.keys():
				var tex: Texture2D = record.textures[field]
				if tex and not _is_file_backed(tex):
					record.textures.erase(field)
					dropped += 1
			for field in record.arrays.keys():
				var kept: Array = []
				for tex in record.arrays[field]:
					if tex is Texture2D and _is_file_backed(tex):
						kept.append(tex)
					else:
						dropped += 1
				record.arrays[field] = kept
	elif res is SpriteBenchSet:
		for item in (res as SpriteBenchSet).items:
			if item == null:
				continue
			if item.texture and not _is_file_backed(item.texture):
				item.texture = null
				dropped += 1
			var kept: Array[Texture2D] = []
			for tex in item.textures:
				if tex and _is_file_backed(tex):
					kept.append(tex)
				else:
					dropped += 1
			item.textures = kept
	elif res is SpriteFrames:
		var frames := res as SpriteFrames
		for anim in frames.get_animation_names():
			for index in range(frames.get_frame_count(anim) - 1, -1, -1):
				var tex := frames.get_frame_texture(anim, index)
				if tex and not _is_file_backed(tex):
					frames.remove_frame(anim, index)
					dropped += 1
	return dropped


func _save(res: Resource, path: String) -> void:
	var dropped := _strip_embedded(res)
	if dropped > 0:
		_log_line("skipped %s unimported textures in %s; the next sync assigns them" % [dropped, path.get_file()])
	ResourceSaver.save(res, path)


func _fill_missing_textures(slots: Array[Dictionary]) -> int:
	var filled := 0
	for slot in slots:
		var dest := str(slot.get("path", ""))
		if dest.is_empty() or slot.has("collection"):
			continue
		if slot.kind == "record_field":
			if not _record_field_empty(slot):
				continue
			if slot.intent == "textures":
				if FileAccess.file_exists(dest.path_join("manifest.json")):
					_assign_bag(slot, dest, _bag_files(dest))
					filled += 1
			elif FileAccess.file_exists(dest):
				var tex := _imported_texture(dest)
				if tex:
					_assign_texture(slot, tex)
					filled += 1
			continue
		if slot.kind == "set_bag":
			if not FileAccess.file_exists(dest.path_join("manifest.json")):
				continue
			var res := ResourceLoader.load(slot.set_path)
			if res is SpriteBenchSet:
				var item := (res as SpriteBenchSet).item_for_key(StringName(slot.item_key))
				if item and item.textures.is_empty():
					_assign_bag(slot, dest, _bag_files(dest))
					filled += 1
			continue
		if str(slot.get("intent", "")) == "sprite_frames":
			var tres := dest.path_join("frames.tres")
			if FileAccess.file_exists(tres) and _node_frames_empty(slot):
				var frames := ResourceLoader.load(tres)
				if frames is SpriteFrames:
					_apply_frames_to_slot(slot, frames as SpriteFrames)
					filled += 1
			continue
		if not FileAccess.file_exists(dest):
			continue
		if slot.kind == "set_item":
			var res := ResourceLoader.load(slot.set_path)
			if res is SpriteBenchSet:
				var item := (res as SpriteBenchSet).item_for_key(StringName(slot.item_key))
				if item and item.texture == null:
					var tex := _imported_texture(dest)
					if tex:
						_assign_texture(slot, tex)
						filled += 1
		elif _node_texture_empty(slot):
			var tex := _imported_texture(dest)
			if tex:
				_assign_texture(slot, tex)
				filled += 1
	return filled


func _bag_files(dir: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("manifest.json")))
	var files: Array = []
	if typeof(parsed) != TYPE_DICTIONARY:
		return files
	for frame in parsed.get("frames", []):
		files.append(str(frame.get("file", "")) if typeof(frame) == TYPE_DICTIONARY else str(frame))
	return files


func _node_texture_empty(slot: Dictionary) -> bool:
	var node := _edited_node(slot)
	return node is Sprite2D and (node as Sprite2D).texture == null


func _node_frames_empty(slot: Dictionary) -> bool:
	var node := _edited_node(slot)
	if not node is AnimatedSprite2D:
		return false
	var frames := (node as AnimatedSprite2D).sprite_frames
	return frames == null or frames.get_animation_names().is_empty()


func _edited_node(slot: Dictionary) -> Node:
	var scene_path := str(slot.get("scene_path", ""))
	var node_path := str(slot.get("node_path", "."))
	var edited := EditorInterface.get_edited_scene_root()
	if edited and edited.scene_file_path == scene_path:
		return edited if node_path == "." else edited.get_node_or_null(NodePath(node_path))
	return null


func _assign_texture(slot: Dictionary, texture: Texture2D) -> void:
	if slot.is_empty():
		_log_line("wrote PNG but no local slot to assign")
		return
	if slot.kind == "set_item":
		var res := ResourceLoader.load(slot.set_path)
		if res is SpriteBenchSet:
			var item := (res as SpriteBenchSet).item_for_key(StringName(slot.item_key))
			if item:
				item.texture = texture
				item.emit_changed()
				res.emit_changed()
				_save(res, slot.set_path)
		return
	if slot.kind == "record_field":
		_mutate_record(slot, func(record: SpriteBenchRecord) -> void:
			record.set_texture(StringName(slot.field_key), texture)
		)
		return
	_mutate_node(slot, func(node: Node) -> void:
		_apply_to_node(node, texture)
	)


func _assign_bag(slot: Dictionary, dest: String, files: Array) -> void:
	if slot.is_empty() or (slot.kind != "set_bag" and slot.kind != "record_field"):
		return
	var textures: Array[Texture2D] = []
	for file in files:
		var tex := _imported_texture(dest.path_join(str(file)))
		if tex == null:
			_log_line("waiting for import: %s" % dest.path_join(str(file)))
			return
		textures.append(tex)
	if slot.kind == "record_field":
		_mutate_record(slot, func(record: SpriteBenchRecord) -> void:
			record.set_textures(StringName(slot.field_key), textures)
		)
		return
	var res := ResourceLoader.load(slot.set_path)
	if res is SpriteBenchSet:
		var item := (res as SpriteBenchSet).item_for_key(StringName(slot.item_key))
		if item:
			item.as_array = true
			item.textures = textures
			item.emit_changed()
			res.emit_changed()
			_save(res, slot.set_path)


func _mutate_record(slot: Dictionary, apply: Callable) -> void:
	var res := ResourceLoader.load(slot.set_path)
	if not res is SpriteBenchCollection:
		return
	var record := (res as SpriteBenchCollection).record_by_id(str(slot.record_id))
	if record == null:
		return
	apply.call(record)
	res.emit_changed()
	_save(res, slot.set_path)


func _record_field_empty(slot: Dictionary) -> bool:
	var res := ResourceLoader.load(slot.set_path)
	if not res is SpriteBenchCollection:
		return false
	var record := (res as SpriteBenchCollection).record_by_id(str(slot.record_id))
	if record == null:
		return false
	var field := StringName(slot.field_key)
	if slot.intent == "textures":
		return (record.arrays.get(field, []) as Array).is_empty()
	return record.get_texture(field) == null


func _assign_sprite_frames(slot: Dictionary, dest: String, clips: Array) -> void:
	for clip in clips:
		for frame in (clip as Dictionary).get("frames", []):
			var file := dest.path_join(str((frame as Dictionary).get("file", "")))
			if _imported_texture(file) == null:
				_log_line("waiting for import: %s" % file)
				return
	var tres := dest.path_join("frames.tres")
	var frames := _sprite_frames_resource(slot, tres)
	for clip in clips:
		var row: Dictionary = clip
		var name := StringName(str(row.get("name", "default")))
		if not frames.has_animation(name):
			frames.add_animation(name)
		frames.clear(name)
		frames.set_animation_speed(name, float(row.get("fps", 6)))
		frames.set_animation_loop(name, bool(row.get("loop", true)))
		for frame in row.get("frames", []):
			var entry: Dictionary = frame
			var tex := _imported_texture(dest.path_join(str(entry.get("file", ""))))
			if tex:
				frames.add_frame(name, tex, float(entry.get("hold", 1)))
	frames.take_over_path(tres)
	_save(frames, tres)
	_apply_frames_to_slot(slot, frames)


func _sprite_frames_resource(slot: Dictionary, tres: String) -> SpriteFrames:
	if ResourceLoader.exists(tres):
		var loaded := ResourceLoader.load(tres)
		if loaded is SpriteFrames:
			return loaded as SpriteFrames
	var node := _edited_node(slot)
	if node is AnimatedSprite2D:
		var existing := (node as AnimatedSprite2D).sprite_frames
		if existing:
			return existing.duplicate(true) as SpriteFrames
	var scene_path := str(slot.get("scene_path", ""))
	if scene_path.is_empty() or not FileAccess.file_exists(scene_path):
		return SpriteFrames.new()
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return SpriteFrames.new()
	var root := packed.instantiate()
	var node_path := str(slot.get("node_path", "."))
	var target := root if node_path == "." else root.get_node_or_null(NodePath(node_path))
	var copy: SpriteFrames = null
	if target is AnimatedSprite2D:
		var existing := (target as AnimatedSprite2D).sprite_frames
		if existing:
			copy = existing.duplicate(true) as SpriteFrames
	root.free()
	return copy if copy else SpriteFrames.new()


func _apply_frames_to_slot(slot: Dictionary, frames: SpriteFrames) -> void:
	_mutate_node(slot, func(node: Node) -> void:
		if node is CanvasItem:
			(node as CanvasItem).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if node is AnimatedSprite2D:
			var sprite := node as AnimatedSprite2D
			sprite.sprite_frames = frames
			if sprite.animation == &"" and frames.get_animation_names().size() > 0:
				sprite.animation = StringName(frames.get_animation_names()[0])
	)


func _mutate_node(slot: Dictionary, apply: Callable) -> void:
	var scene_path := str(slot.get("scene_path", ""))
	var node_path := str(slot.get("node_path", "."))
	var edited := EditorInterface.get_edited_scene_root()
	if edited and edited.scene_file_path == scene_path:
		var node := edited if node_path == "." else edited.get_node_or_null(NodePath(node_path))
		if node:
			apply.call(node)
			EditorInterface.mark_scene_as_unsaved()
		return
	if scene_path.is_empty() or not FileAccess.file_exists(scene_path):
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var root := packed.instantiate()
	var target := root if node_path == "." else root.get_node_or_null(NodePath(node_path))
	if target:
		apply.call(target)
		var next := PackedScene.new()
		if next.pack(root) == OK:
			ResourceSaver.save(next, scene_path)
	root.free()


func _apply_to_node(node: Node, texture: Texture2D) -> void:
	if texture == null or not _is_file_backed(texture):
		return
	if node is CanvasItem:
		(node as CanvasItem).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if node is Sprite2D:
		(node as Sprite2D).texture = texture


func _collect_slots() -> Array[Dictionary]:
	_import_profiles.clear()
	var slots: Array[Dictionary] = []
	var seen := {}
	var edited := EditorInterface.get_edited_scene_root()
	var edited_path := edited.scene_file_path if edited else ""
	if edited:
		_collect_tree(edited, edited_path, slots, seen)
	for path in _walk("res://", [".tscn"]):
		if path == edited_path:
			continue
		_collect_tscn(path, slots, seen)
	for path in _walk("res://", [".tres", ".res"]):
		if not _looks_like(path, "SpriteBenchSet") and not _looks_like(path, "SpriteBenchCollection"):
			continue
		var res := ResourceLoader.load(path)
		if res is SpriteBenchSet:
			_collect_set(res as SpriteBenchSet, path, slots, seen)
		elif res is SpriteBenchCollection:
			_collect_collection(res as SpriteBenchCollection, path, slots, seen)
	return slots


func _collect_tree(root: Node, scene_path: String, slots: Array[Dictionary], seen: Dictionary) -> void:
	_walk_node(root, root, scene_path, slots, seen)


func _walk_node(root: Node, node: Node, scene_path: String, slots: Array[Dictionary], seen: Dictionary) -> void:
	if (node is Sprite2D or node is AnimatedSprite2D) and node.has_meta(Credentials.SLOT_META):
		var id := str(node.get_meta(Credentials.SLOT_META))
		if _is_uuid(id) and not seen.has(id):
			var node_path := str(root.get_path_to(node))
			slots.append(_node_slot(id, scene_path, node_path, node.name, node is AnimatedSprite2D))
			seen[id] = true
	for child in node.get_children():
		if child.scene_file_path != "" and child != root:
			continue
		_walk_node(root, child, scene_path, slots, seen)


func _collect_tscn(path: String, slots: Array[Dictionary], seen: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var name := ""
	var type := ""
	var parent := ""
	var node_path := ""
	var slot_id := ""
	for line in file.get_as_text().split("\n"):
		if line.begins_with("[node "):
			_flush_tscn_node(path, name, type, node_path, slot_id, slots, seen)
			name = _attr(line, "name")
			type = _attr(line, "type")
			parent = _attr(line, "parent")
			slot_id = ""
			if parent.is_empty():
				node_path = "."
			elif parent == ".":
				node_path = name
			else:
				node_path = parent.path_join(name)
		elif line.begins_with("metadata/%s" % Credentials.SLOT_META):
			slot_id = _quoted(line)
	_flush_tscn_node(path, name, type, node_path, slot_id, slots, seen)


func _flush_tscn_node(
	scene_path: String,
	name: String,
	type: String,
	node_path: String,
	slot_id: String,
	slots: Array[Dictionary],
	seen: Dictionary
) -> void:
	if slot_id.is_empty() or seen.has(slot_id):
		return
	if type != "Sprite2D" and type != "AnimatedSprite2D":
		return
	if not _is_uuid(slot_id):
		return
	slots.append(_node_slot(slot_id, scene_path, node_path, name, type == "AnimatedSprite2D"))
	seen[slot_id] = true


func _collect_set(res: SpriteBenchSet, path: String, slots: Array[Dictionary], seen: Dictionary) -> void:
	var dirty := false
	for item in res.items:
		if item == null:
			continue
		var before := item.slot_id
		var id := item.ensure_slot_id()
		if before != id:
			dirty = true
		if not _is_uuid(id) or seen.has(id):
			continue
		var key := String(item.key)
		if key.is_empty():
			key = id.substr(0, 8)
		var as_array := bool(item.as_array)
		var dest := Credentials.slot_dir(id) if as_array else Credentials.png_path(id)
		if not as_array and item.texture and item.texture.resource_path.begins_with("res://"):
			dest = item.texture.resource_path
		slots.append({
			"id": id,
			"kind": "set_bag" if as_array else "set_item",
			"intent": "textures" if as_array else "texture",
			"label": _clip(key, 255),
			"path": dest,
			"localHash": _bundle_hash(dest) if as_array else _local_hash(dest),
			"set_path": path,
			"item_key": key,
		})
		seen[id] = true
	if dirty:
		_save(res, path)


## One slot per record and field, plus one entry carrying the collection
## itself (marked by a `collection` key) for the catalog's `collections`.
func _collect_collection(
	res: SpriteBenchCollection,
	path: String,
	slots: Array[Dictionary],
	seen: Dictionary
) -> void:
	if res.ensure_ids():
		_save(res, path)
	if seen.has(res.id):
		return
	seen[res.id] = true
	var label := res.label.strip_edges()
	if label.is_empty():
		label = path.get_file().get_basename()

	var fields: Array = []
	var field_keys := {}
	for field in res.fields:
		if field == null or String(field.key).is_empty() or field_keys.has(field.key):
			continue
		field_keys[field.key] = true
		fields.append({
			"key": _clip(String(field.key), 64),
			"intent": "textures" if field.as_array else "texture",
		})

	var profile := { "for_3d": res.for_3d, "max_size": res.max_size }
	var records: Array = []
	for record in res.records:
		if record == null:
			continue
		var record_key := _clip(String(record.key), 120)
		records.append({ "id": record.id, "key": record_key })
		for field in fields:
			var id := Hasher.field_slot_id(record.id, field.key)
			var as_array: bool = field.intent == "textures"
			var dest := Credentials.slot_dir(id) if as_array else Credentials.png_path(id)
			_import_profiles[dest] = profile
			slots.append({
				"id": id,
				"kind": "record_field",
				"intent": field.intent,
				"label": _clip("%s/%s.%s" % [label, record_key, field.key], 255),
				"path": dest,
				"localHash": _bundle_hash(dest) if as_array else _local_hash(dest),
				"set_path": path,
				"record_id": record.id,
				"field_key": field.key,
			})
			seen[id] = true

	slots.append({
		"id": res.id,
		"kind": "collection",
		"path": path,
		"collection": {
			"id": res.id,
			"label": _clip(label, 255),
			"path": path,
			"fields": fields,
			"records": records,
		},
	})


func _node_slot(
	id: String,
	scene_path: String,
	node_path: String,
	node_name: String,
	animated: bool
) -> Dictionary:
	var dest := Credentials.slot_dir(id) if animated else Credentials.png_path(id)
	var label := node_name
	if not scene_path.is_empty():
		label = "%s:%s" % [scene_path.get_file(), node_path]
	return {
		"id": id,
		"kind": "node",
		"intent": "sprite_frames" if animated else "texture",
		"label": _clip(label, 255),
		"path": dest,
		"localHash": _bundle_hash(dest) if animated else _local_hash(dest),
		"scene_path": scene_path,
		"node_path": node_path,
	}


func _local_hash(path: String) -> Variant:
	var digest := Hasher.file_sha256(path)
	if digest.length() != 64:
		return null
	return digest


func _bundle_hash(path: String) -> Variant:
	var digest := Hasher.hash_from_dir(path)
	if digest.length() != 64:
		return null
	return digest


func _looks_like(path: String, type_name: String) -> bool:
	if path.ends_with(".res"):
		return true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var head := file.get_buffer(mini(file.get_length(), 2048)).get_string_from_utf8()
	return type_name in head


func _walk(path: String, suffixes: Array[String]) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	for name in dir.get_directories():
		if name.begins_with("."):
			continue
		if path == "res://" and name == "addons":
			continue
		out.append_array(_walk(path.path_join(name), suffixes))
	for name in dir.get_files():
		for suffix in suffixes:
			if name.ends_with(suffix):
				out.append(path.path_join(name))
				break
	return out


func _attr(header: String, key: String) -> String:
	var needle := '%s="' % key
	var start := header.find(needle)
	if start < 0:
		return ""
	start += needle.length()
	var end := header.find('"', start)
	if end < 0:
		return ""
	return header.substr(start, end - start)


func _quoted(line: String) -> String:
	var start := line.find('"')
	if start < 0:
		return ""
	var end := line.find('"', start + 1)
	if end < 0:
		return ""
	return line.substr(start + 1, end - start - 1)


func _clip(text: String, limit: int) -> String:
	if text.length() <= limit:
		return text
	return text.substr(0, limit)


func _is_uuid(value: String) -> bool:
	var re := RegEx.new()
	re.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
	return re.search(value) != null
