# SpriteBench

Godot 4.6 editor addon. Syncs opted-in `Sprite2D` / `AnimatedSprite2D` nodes and `SpriteBenchSet` resources with a SpriteBench project.

Copy or symlink this folder to `res://addons/spritebench` and enable it in Project Settings → Plugins.

```
ln -s /path/to/spritebench-godot/addons/spritebench res://addons/spritebench
```

## Setup

1. In SpriteBench: Settings → create a personal access token. Paste it in the SpriteBench dock (stored in EditorSettings, not the project).
2. Copy the project id from the Engine panel. Paste it in the dock (saved to ProjectSettings, committed).
3. Local app: set API URL to `http://127.0.0.1:4300`. Production default is `https://spritebench.com`.
4. Check a SpriteBench slot on a sprite (syncs immediately), or use Sync. Sync also runs on scene save once a PAT and project id are set.

## Slots

- Inspector checkbox on `Sprite2D` / `AnimatedSprite2D` writes `spritebench_slot_id` metadata and syncs the catalog.
- `Sprite2D` pulls one processed PNG. `AnimatedSprite2D` pulls named clips into `res://spritebench/{slot_id}/frames.tres` (merge by clip name).
- `SpriteBenchSet` is a keyed bag: `set.get_texture(&"grass")`. Check `as_array` on an item for `set.get_textures(&"bushes")` — one name, ordered PNGs, no per-image keys. `keys()` / `has_key` list the bag names.
- Pull writes under `res://spritebench/` (configurable), pins lossless / no-mipmaps import, assigns the texture or frames, then acks the catalog hash.

## Collections

`SpriteBenchCollection` is a table of keyed records with named art fields, for things like buildings where each image has a job (`front`, `roof`, …) instead of a position in an array.

- `fields` (a list of `SpriteBenchField`) is the schema. Godot owns it. Check `as_array` on a field for an ordered list instead of one image.
- `records` (a list of `SpriteBenchRecord`) hold `key` plus art per field: `record.get_texture(&"front")`, `record.get_textures(&"variants")`. Look records up with `collection.record_by_id(id)` or `record_by_key(&"brownstone")`.
- Each (record, field) is its own slot. SpriteBench shows the collection as a grid. Dropping an asset on a still cell replaces it, so swapping one building's front never touches the rest.
- Records can be added, renamed and deleted in SpriteBench as well as in Godot. The next sync adds, renames or removes them in the `.tres`, then pulls their art.
- Slot ids are derived from the record id and field key (`Hasher.field_slot_id`), so a record created in SpriteBench can take art before Godot has seen it.

Godot never uploads pixels. Assign art in the SpriteBench Engine panel. Editing a pulled PNG in Godot sticks until you assign again; the web app shows "edited in Godot".
