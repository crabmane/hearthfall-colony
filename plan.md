# Hearthfall Colony — Implementation Plan

## Product direction
A desktop browser colony simulation about a small band of survivors turning a forest clearing into a settlement. The promise is a living world: colonists make their own choices, resources move physically, work is visible, and environmental pressures create stories instead of scripted missions.

Approved production choices: Standard effort, original AI-generated 2D pixel art, English-only game content, offline single-player.

## Core loop
1. Survey the clearing, mark trees, stone, ore, and berry bushes for gathering.
2. Place blueprints for shelter, food, production, health, and defense buildings.
3. Set work priorities and watch autonomous colonists build, haul, farm, cook, craft, heal, hunt, and rest.
4. Balance food, warmth, health, hygiene, mood, and storage through day/night, weather, seasons, spoilage, illness, injury, fire, and wildlife.
5. Grow the colony through arrivals and resilience; inspect any colonist to understand the causes behind their behavior.

## Simulation ownership
- `scripts/game/colony_sim.gd` owns time, map generation, pathfinding, resources, construction, jobs, needs, moods, relationships, health, environment, weather, seasons, fire, wildlife, events, and save snapshots.
- `scripts/game/defs.gd` owns all authored resource, building, trait, crop, weather, and job definitions.
- `scripts/game/world_renderer.gd` owns the world canvas: terrain, depth-sorted sprites, selection, build ghosts, colonists, animals, piles, fire, night lighting, and weather particles.
- `scripts/ui/colony_hud.gd` owns resource HUD, clock, build drawer, order tools, colonist inspector, work priority matrix, alerts, log, objectives, toasts, and pause/help screens.
- `scripts/main.gd` owns screen flow, camera input, world interaction, save/load entry points, and wiring between simulation and UI.
- `autoload/hf_assets.gd` loads the sliced pixel-art library with nearest filtering.
- `scripts/ui/ui_kit.gd` owns the shared pixel-panel visual language.

## Presentation
A grounded frontier-pixel palette: spruce shadow, timber, parchment, moss, amber firelight, and rust warnings. Panels use chunky two-pixel borders and offset shadows. The generated title painting anchors the start screen; sprite sheets are sliced into transparent runtime assets. Live text and numbers remain engine-rendered.

## Persistence and controls
- Local save in `user://hearthfall_colony.json`; manual save/load plus dawn autosave.
- WASD/arrows pan, mouse wheel zooms, left click interacts, right click cancels, Esc pauses.
- Speed controls: pause, 1x, 2x, 4x.
- Start screen, how-to-play, pause, save/load, and colony-fallen screens.

## Project structure
- `assets/game/art/` generated masters and title painting.
- `assets/game/sprites/` sliced transparent runtime sprites.
- `assets/share/` favicon and OG cover.
- `scenes/main.tscn` minimal scene shell.
- `scripts/` game, UI, and autoload code.
- `test/` finite simulation and boot checks.
- `web/loading.html` project-specific loading screen.
