# Tablet aim assist + ESP

`Arsenal_Assist_ESP.lua` is client source with touch controls. It uses general Roblox APIs; live Arsenal hit acceptance is not verified.

## Faster tablet defaults

- Tracking strength: **0.22**, previously 0.055. Its interpolation coefficient is four times larger at 60 FPS. Equal-time smoothing remains independent of frame rate for a stationary goal.
- Targeting circle: **140 pixel radius**, previously 75.
- Candidate search interval: **0.04 seconds**, previously 0.075.
- Settings → **Aim preset** cycles Tablet → Fast → Subtle. Fast uses strength 0.35 and FOV 180; Subtle restores strength 0.055 and FOV 75. Manual controls remain available.

## Tablet controls

Tap **AIM** to arm/disarm tracking. **ESP** controls outlines. **HITBOX** controls the experimental local resize. **SETTINGS** opens the scrollable panel, including preset/strength/FOV/size controls and optional Hold mode. **UNLOAD** restores modified parts and removes the system. Drag **MOVE CONTROLS** to reposition the dock.

Configuration changes release active aim, so tap AIM again afterward. Re-running the loader unloads the previous instance first.

## Local resize: what it does and what is unverified

The default local resize is enabled, with a minimum **6 studs on each axis** of an eligible enemy's `HumanoidRootPart`. Originally larger axes are preserved. It applies only to alive enemies within 300 studs, with a separate team filter. The optional translucent amber box visualizes the enlarged **local** volume.

This changes the local part's Size, CanCollide, and CanQuery. It leaves CanTouch, transparency, and other properties alone. Original changed properties are restored on disable, death, team/range exclusion, root removal/replacement, character removal, player departure, unload, or reinitialization. Size is adjustable from 2 to 12 studs; use HITBOX OFF to restore original geometry immediately.

**This is not a claim that Arsenal accepts a larger damage hitbox.** A weapon may use a different query/filter, and its server may reject hits outside server-side geometry. No damage remote, firing routine, server validation, or anti-cheat bypass is changed. Real server-authoritative hitbox changes require changing the game's own server implementation.

Assist visibility queries exclude all locally enlarged roots so a box protruding through a wall does not make the underlying torso appear visible. The marker's occlusion follows the ESP wall-display setting.

## Verification

Official standalone Luau 0.745 compilation passed. All **148 local checks passed**: 15 smoothing, 67 existing client behavior, 34 tablet controls, and 32 upgrade-specific checks. The fixture is a deterministic engine test double, with Studio false and no script global. An independent static review found no concrete Important/Critical defects.

The upgrade checks cover stronger defaults/render correction, presets, local sizing without shrinking large originals, collision/query restoration, unchanged local-player geometry, marker behavior, visibility exclusions, touch toggle, independent ESP, team/range/death handling, root streaming/replacement, respawns, reinitialization, and unload.

**Actual Roblox/tablet property behavior, physical side effects, live damage registration, and updated camera feel have not been tested here.** Test these in the target environment; local checks do not establish server acceptance.

Primary references: [BasePart](https://create.roblox.com/docs/reference/engine/classes/BasePart), [raycasting](https://create.roblox.com/docs/workspace/raycasting), [server-side weapon validation](https://create.roblox.com/docs/scripting/security/client-server-boundary), [BoxHandleAdornment](https://create.roblox.com/docs/reference/engine/classes/BoxHandleAdornment).
