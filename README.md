# SpriteBench for Godot

> **Alpha.** This addon is early and experimental. It works, but expect rough edges, and back up your project before trying it.

A Godot 4.6 editor addon that syncs art from [SpriteBench](https://spritebench.com) into your game. SpriteBench is a web app for prototyping game art with AI and finishing it with artists; this addon is the bridge that puts the results into your Godot project as ordinary textures and sprite frames.

- Tick **SpriteBench slot** on a `Sprite2D` or `AnimatedSprite2D`, or use a `SpriteBenchSet` / `SpriteBenchCollection` resource.
- Assign art to those slots in SpriteBench's **Game Assets** tab.
- Press **Sync** in Godot. Processed PNGs land under `res://spritebench/` and are wired into your nodes and resources.

Editor-only and written in GDScript, so it works in GDScript and C# projects alike. Exported games just contain normal `Texture2D` and `SpriteFrames`.

## Install

1. Download this repository (Code → Download ZIP) or clone it.
2. Copy the `addons/spritebench` folder into your project as `res://addons/spritebench`.
3. Enable **SpriteBench** under Project → Project Settings → Plugins.

## Quick start

1. Sign in at [spritebench.com](https://spritebench.com) and open (or create) a project.
2. In SpriteBench, go to **Settings → Account & keys → Personal access tokens** and create one. Paste it into the **SpriteBench** dock in Godot.
3. Paste your SpriteBench **Project ID** into the dock. It's the long id in the project's address (`spritebench.com/projects/<project id>`), and it's also shown in the Game Assets tab until your first sync.
4. Tick **SpriteBench slot** on a sprite, or press **Sync**.

The full guide is in [`addons/spritebench/README.md`](addons/spritebench/README.md), and SpriteBench's in-app **Help → Godot** tab covers the web side.

## Feedback

Found a bug or want a feature? Use the feedback box inside SpriteBench, or open an issue here.

## License

MIT. See [`addons/spritebench/LICENSE`](addons/spritebench/LICENSE).
