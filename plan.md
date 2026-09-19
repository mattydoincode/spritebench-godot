# SpriteBench Godot plugin

A Godot 4.6 editor addon (`addons/spritebench/`). GDScript so it works in C# games and GDScript games. Editor-only. Exported games just have normal `Texture2D` / `SpriteFrames` already filled in.

Godot owns the catalog of slots. SpriteBench assigns art and sends processed PNGs down. Editing a PNG in Godot sticks until someone assigns again in SpriteBench; the web app can warn "edited in Godot".

This repo assumes the SpriteBench `/api/v1` surface already exists.

## Two surfaces, one slot

**A — Opt-in Sprite2D / AnimatedSprite2D.** `EditorInspectorPlugin`, no subclass, no required node script. Checkbox writes metadata (`spritebench_slot_id`). Pull sets `texture` / fills `SpriteFrames`.

This is the typical character path: a placeholder sprite on an actor. Check the box, assign art, the placeholder goes away (or stays until `texture` is set).

**B — `SpriteBenchSet` resource.** Keyed bag of items. Any node can `@export` / `ResourceLoader.Load` it and call `get_texture(&"grass")`. C# can do the same once `class_name` is registered.

This is the typical tile/kit path: a generator that already spawns `Sprite2D`s from `Texture2D`s. A set keyed by tile name is the programmatic hook.

Stills first. `AnimatedSprite2D` / sequences after.

## Auth in the editor

Dock: paste PAT once (EditorSettings). Confirm SpriteBench project id (ProjectSettings, committed). Sync button.

Do not put the token in a `.tres` in the project.

## Sync

On scene save or dock Sync:

1. Collect opted-in nodes + every `SpriteBenchSet` under `res://`.
2. `POST` catalog (slot id, kind, label, godot path, local content hash).
3. `GET` pull: slots whose remote hash differs and local was not edited.
4. Write PNG under `res://spritebench/` (configurable), pin `.import` (filter nearest, mipmaps off, no compress), assign into the resource or node, save.

Conflict is three hashes (last pushed / local / remote). Godot-edited + remote unchanged → skip overwrite, report it. Both changed → skip, surface conflict.

Godot never uploads pixels in v1.

## Layout

```
addons/spritebench/
  plugin.cfg
  plugin.gd
  inspector.gd
  spritebench_item.gd
  spritebench_set.gd
  api.gd
  credentials.gd
  hasher.gd
  LICENSE
  README.md
plan.md
.gitignore
```

Repo is the addon root (Asset Library style: zip is `addons/spritebench` plus license). Games copy or symlink it into `res://addons/spritebench`.

## Build order

1. `plugin.cfg` + dock: store PAT, project id, `GET /api/v1/me`.
2. `SpriteBenchSet` + catalog push + still pull.
3. Inspector checkbox on Sprite2D.
4. Then AnimatedSprite2D.
