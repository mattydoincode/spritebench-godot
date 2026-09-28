# SpriteBench

> **Alpha.** Early and experimental: it works, but expect rough edges, and back up your project before trying it.

Godot 4.6 editor addon for [SpriteBench](https://spritebench.com). It syncs opted-in `Sprite2D` / `AnimatedSprite2D` nodes and `SpriteBench` resources with a SpriteBench project, pulling in the art you assign there.

Copy this folder to `res://addons/spritebench` and enable it under Project → Project Settings → Plugins.

## Setup

1. In SpriteBench: **Settings → Account & keys → Personal access tokens**, create a token, and paste it into the **SpriteBench** dock. It's stored in your EditorSettings, never in the project, so it won't end up in version control.
2. Paste your SpriteBench **Project ID** into the dock. It's the long id in the project's address (`spritebench.com/projects/<project id>`), and it's also shown in the **Game Assets** tab until your first sync. It's saved to ProjectSettings, so commit it and your team shares it.
3. Leave **API URL** as `https://spritebench.com`.
4. Tick **SpriteBench slot** on a sprite (this syncs immediately), or press **Sync**. Sync also runs on scene save once a token and project id are set. **Check** confirms the token works.

## Slots

- The **SpriteBench slot** checkbox on `Sprite2D` / `AnimatedSprite2D` writes `spritebench_slot_id` metadata and syncs the catalog.
- A `Sprite2D` pulls one processed PNG. An `AnimatedSprite2D` pulls named clips into `res://spritebench/{slot_id}/frames.tres`, merged by clip name.
- `SpriteBenchSet` is a keyed bag: `set.get_texture(&"grass")`. Check `as_array` on an item for `set.get_textures(&"bushes")`: one name, ordered PNGs, no per-image keys. `keys()` / `has_key` list the names.
- Pulls are written under `res://spritebench/` (the **Output folder** in the dock) with lossless, no-mipmap import settings, assigned to the texture or frames, and acknowledged back to SpriteBench.

## Collections

`SpriteBenchCollection` is a table of keyed records with named art fields, for things like buildings where each image has a job (`front`, `roof`, …) rather than a position in a list.

- `fields` (a list of `SpriteBenchField`) is the schema. Check `as_array` on a field for an ordered list instead of one image.
- `records` (a list of `SpriteBenchRecord`) hold a `key` plus art per field: `record.get_texture(&"front")`, `record.get_textures(&"variants")`. Look records up with `collection.record_by_id(id)` or `record_by_key(&"brownstone")`.
- Each (record, field) pair is its own slot. SpriteBench shows the collection as a grid, and dropping an image on one cell replaces just that one.
- Records can be added, renamed and deleted in SpriteBench as well as in Godot. The next sync updates the `.tres` and pulls their art.

## Made in SpriteBench

Assets, lists and tables can also be created in SpriteBench (**Game Assets → + new**), for projects designed there first:

- Standalone **assets** and **lists** go into `res://spritebench/assets.tres`, a `SpriteBenchSet`: `load("res://spritebench/assets.tres").get_texture(&"hero_idle")`, or `get_textures(&"rock_variants")` for a list. SpriteBench manages that file, so keep your own sets in other files.
- **Tables** become `res://spritebench/tables/<name>.tres` (a `SpriteBenchCollection`) with SpriteBench's fields. Rows and art sync like any other collection.

Remove these in SpriteBench and the next sync takes them out of `assets.tres`. A removed table's `.tres` is currently left in place.

## Prototype and final art

Every slot can hold two sets of art in SpriteBench: the AI **prototype** and an artist's **final**. Project Settings → SpriteBench → **Art** picks what the game pulls:

- `final` (default): each slot's final where it has one, otherwise its prototype.
- `prototype`: only prototypes, for comparing or playtesting before the art is done.

It's a project setting, so the team and every build agree. Changing it takes effect on the next sync, and game code doesn't change, since each slot keeps its file path.

## Good to know

- Godot never uploads pixels. Assign art in SpriteBench's **Game Assets** tab.
- Editing a pulled PNG in Godot sticks until you assign again in SpriteBench, which shows "edited in Godot".
- Feedback and bugs: the feedback box inside SpriteBench, or an issue on [GitHub](https://github.com/mattydoincode/spritebench-godot).
