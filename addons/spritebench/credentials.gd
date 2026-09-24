@tool
extends RefCounted

const SLOT_META := "spritebench_slot_id"

const SETTING_PAT := "spritebench/personal_access_token"
const SETTING_PROJECT_ID := "spritebench/project_id"
const SETTING_BASE_URL := "spritebench/base_url"
const SETTING_OUTPUT_DIR := "spritebench/output_dir"

const DEFAULT_BASE_URL := "https://spritebench.com"
const DEFAULT_OUTPUT_DIR := "res://spritebench"


static func ensure_registered() -> void:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(SETTING_PAT):
		settings.set_setting(SETTING_PAT, "")
	settings.set_initial_value(SETTING_PAT, "", false)
	settings.add_property_info({
		"name": SETTING_PAT,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_PASSWORD,
	})

	_ensure_project(SETTING_PROJECT_ID, "")
	_ensure_project(SETTING_BASE_URL, DEFAULT_BASE_URL)
	_ensure_project(SETTING_OUTPUT_DIR, DEFAULT_OUTPUT_DIR)


static func _ensure_project(key: String, default_value: String) -> void:
	if not ProjectSettings.has_setting(key):
		ProjectSettings.set_setting(key, default_value)
	ProjectSettings.set_initial_value(key, default_value)
	ProjectSettings.add_property_info({
		"name": key,
		"type": TYPE_STRING,
	})
	if ProjectSettings.has_method("set_as_basic"):
		ProjectSettings.set_as_basic(key, true)


static func pat() -> String:
	return str(EditorInterface.get_editor_settings().get_setting(SETTING_PAT)).strip_edges()


static func set_pat(value: String) -> void:
	EditorInterface.get_editor_settings().set_setting(SETTING_PAT, value.strip_edges())


static func project_id() -> String:
	return str(ProjectSettings.get_setting(SETTING_PROJECT_ID, "")).strip_edges()


static func set_project_id(value: String) -> void:
	ProjectSettings.set_setting(SETTING_PROJECT_ID, value.strip_edges())
	ProjectSettings.save()


static func base_url() -> String:
	var url := str(ProjectSettings.get_setting(SETTING_BASE_URL, DEFAULT_BASE_URL)).strip_edges()
	if url.is_empty():
		url = DEFAULT_BASE_URL
	return url.rstrip("/")


static func set_base_url(value: String) -> void:
	var url := value.strip_edges().rstrip("/")
	if url.is_empty():
		url = DEFAULT_BASE_URL
	ProjectSettings.set_setting(SETTING_BASE_URL, url)
	ProjectSettings.save()


static func output_dir() -> String:
	var dir := str(ProjectSettings.get_setting(SETTING_OUTPUT_DIR, DEFAULT_OUTPUT_DIR)).strip_edges()
	if dir.is_empty():
		dir = DEFAULT_OUTPUT_DIR
	return dir.rstrip("/")


static func set_output_dir(value: String) -> void:
	var dir := value.strip_edges().rstrip("/")
	if dir.is_empty():
		dir = DEFAULT_OUTPUT_DIR
	ProjectSettings.set_setting(SETTING_OUTPUT_DIR, dir)
	ProjectSettings.save()


static func png_path(slot_id: String) -> String:
	return output_dir().path_join("%s.png" % slot_id)


static func slot_dir(slot_id: String) -> String:
	return output_dir().path_join(slot_id)


static func frames_path(slot_id: String) -> String:
	return slot_dir(slot_id).path_join("frames.tres")


static func manifest_path(slot_id: String) -> String:
	return slot_dir(slot_id).path_join("manifest.json")


static func is_configured() -> bool:
	return not pat().is_empty() and not project_id().is_empty()
