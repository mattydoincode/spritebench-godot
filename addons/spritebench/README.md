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

Godot never uploads pixels. Assign art in the SpriteBench Engine panel. Editing a pulled PNG in Godot sticks until you assign again; the web app shows "edited in Godot".
