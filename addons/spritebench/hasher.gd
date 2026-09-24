@tool
extends RefCounted

## SHA-256 of raw PNG bytes as 64 lowercase hex chars. Must match
## SpriteBench `hashExportBytes` (Node `crypto.createHash("sha256")`).


static func file_sha256(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)


static func bytes_sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


static func text_sha256(text: String) -> String:
	return bytes_sha256(text.to_utf8_buffer())


## Must match SpriteBench `spriteFramesBundleText` + `hashExportBytes`.
static func sprite_frames_bundle_hash(clips: Array) -> String:
	var ordered := clips.duplicate()
	ordered.sort_custom(func(a: Variant, b: Variant) -> bool:
		return _clip_name(a) < _clip_name(b)
	)
	var lines: PackedStringArray = ["spritebench.bundle/1", "intent sprite_frames"]
	for clip in ordered:
		var row: Dictionary = clip
		var loop_bit := 1 if bool(row.get("loop", true)) else 0
		lines.append("clip %s %s %s" % [str(row.get("name", "")), int(row.get("fps", 6)), loop_bit])
		for frame in row.get("frames", []):
			var entry: Dictionary = frame
			lines.append("  %s %s" % [int(entry.get("hold", 1)), str(entry.get("sha256", ""))])
	return text_sha256("\n".join(lines) + "\n")


## Must match SpriteBench `texturesBundleText` + `hashExportBytes`.
static func textures_bundle_hash(hashes: PackedStringArray) -> String:
	var lines: PackedStringArray = ["spritebench.bundle/1", "intent textures"]
	for digest in hashes:
		lines.append("  1 %s" % digest)
	return text_sha256("\n".join(lines) + "\n")


static func _clip_name(value: Variant) -> String:
	if value is Dictionary:
		return str((value as Dictionary).get("name", ""))
	return ""


static func hash_from_dir(dir: String) -> String:
	var manifest_path := dir.path_join("manifest.json")
	if dir.is_empty() or not FileAccess.file_exists(manifest_path):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var format := str(parsed.get("format", ""))
	if format == "spritebench.clips/1":
		var clips: Array = []
		for clip in parsed.get("clips", []):
			var row: Dictionary = clip
			var frames: Array = []
			for frame in row.get("frames", []):
				var entry: Dictionary = frame
				var digest := file_sha256(dir.path_join(str(entry.get("file", ""))))
				if digest.is_empty():
					return ""
				frames.append({ "hold": int(entry.get("hold", 1)), "sha256": digest })
			clips.append({
				"name": str(row.get("name", "")),
				"fps": int(row.get("fps", 6)),
				"loop": bool(row.get("loop", true)),
				"frames": frames,
			})
		return sprite_frames_bundle_hash(clips)
	if format == "spritebench.bag/1":
		var hashes := PackedStringArray()
		for frame in parsed.get("frames", []):
			var file := str(frame.get("file", "")) if typeof(frame) == TYPE_DICTIONARY else str(frame)
			var digest := file_sha256(dir.path_join(file))
			if digest.is_empty():
				return ""
			hashes.append(digest)
		return textures_bundle_hash(hashes)
	return ""


static func uuid_v4() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	return "%s-%s-%s-%s-%s" % [
		bytes.slice(0, 4).hex_encode(),
		bytes.slice(4, 6).hex_encode(),
		bytes.slice(6, 8).hex_encode(),
		bytes.slice(8, 10).hex_encode(),
		bytes.slice(10, 16).hex_encode(),
	]
