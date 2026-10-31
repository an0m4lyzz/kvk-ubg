# Tablet assist: tablet4 head/torso preference

This client script controls the camera and visuals. **It does not fire weapons or change the game's fire rate. Continue using the game's manual fire button.**

## Head / torso preference

The default **HeadChance = 0.70** means a new lock prefers the Head with probability 70%; otherwise it prefers the configured body part (UpperTorso, with standard R6 Torso/root fallback). Adjust **SETTINGS → Head preference** in 10 percentage-point steps.

The preference is sampled once for a search/new lock, not every render or shot. Empty searches retain their pending choice, and a valid retained part stays stable. If the chosen part becomes missing, blocked, or outside FOV, the script tries the other eligible visible point. With HeadChance zero, head fallback is disabled. HeadChance one gives head priority with body fallback when necessary.

Unlocked reselection queues a next-lock preference, ranks actual eligible points before switching players, and preserves the existing point when the current player remains nearest. Losing an unselected torso does not reset a valid head lock.

This is an **aim-point preference**, not a promised percentage of headshots, kills, or bullets. Manual firing, visibility, weapon spread, movement, and server validation affect actual results. A head-preferred lock may keep aiming at the head for its entire duration. No ratio guarantees avoiding suspicion or detection, and no anti-cheat bypass is included.

Stats/report expose the actual selected aim part. The settings status shows that part while tracking.

## Changes for inconsistent locking

- A missing target is searched for on the very next armed render, rather than waiting for the previous empty-search interval. AcquireInterval now limits only optional reselection of an already valid target with TargetLock off.
- Smoothing carries progress across frames when a game camera repeatedly supplies an absolute base angle. It no longer has to repeat a single small correction forever.
- A preparation phase removes the prior owned rotation before the normal camera update; tracking runs at priority2001, after typical camera writers. A rotation-only fuzzy comparison preserves legitimate camera position changes.
- Unknown external rotations rebase the saved correction, preventing recoil or another writer from receiving the old correction twice. Release, respawn, camera replacement, pause, reset, and unload clear this state.
- A best-effort observer at priority2002 reports intervening camera overwrites. It cannot detect every possible writer after that priority and does not guarantee control of arbitrary custom camera pipelines.
- Default preset is **Fast**: strength **0.35**, FOV **180 pixels**. Subtle/Tablet/Fast presets and manual strength/FOV controls remain available.
- The touch dock starts on the **left**, and its empty background is inactive, keeping the default right-side fire-control area free. The actual buttons remain interactive. Drag MOVE CONTROLS if your game's layout differs.
- Experimental local hitbox resizing starts **OFF** in this diagnostic build. It remains available as an opt-in toggle; client-only geometry can confound shot registration and should be tested separately from camera tracking.

## Controls and status

Tap **AIM** to arm/disarm. **ESP** controls outlines, **HITBOX** controls optional local resize, **SETTINGS** opens the scrollable panel, and **UNLOAD** stops/restores the system. Optional Hold mode uses one owning touch; unrelated fingers do not release it.

The AIM button and settings status distinguish:

| Status | Meaning |
| --- | --- |
| SEARCHING / TRACKING | Armed and acquiring or rotating toward a valid target |
| LOCKED | The selected aim point projects within 4 pixels of viewport center at the tracking callback; this is camera alignment, not confirmed firing or damage |
| OUTSIDE_FOV | Available targets are offscreen or outside the configured pixel radius |
| BLOCKED | In-FOV candidates failed obstruction checks |
| NO_ELIGIBLE | Team, health, missing-part, or character filters exclude candidates |
| CAMERA_PAUSED | Non-Custom camera or unsupported camera mode |
| CAMERA_OVERRIDE | Another observed writer changed the corrected rotation before the observer callback |
| IDLE / WAIT_CAMERA / NO_CHARACTER / PAUSED | Not armed or waiting for a valid camera/character/frame |

If delay remains, use **SETTINGS → Copy diagnostics** and paste the report. When the runtime does not expose setclipboard, the report is printed to its output instead. Reports include revision, state, target, camera type, FOV/strength, pixel error, scan counts, observed overwrites/rebases, and whether local resizing is active. They do not measure weapon fire timing or server hit acceptance.

The local controller also supports `Configure:Invoke("Stats")` for structured diagnostics and `Configure:Invoke("Report")` for the text report. Changing configuration releases activation; tap AIM again afterward.

## Optional local resize

HITBOX ON expands eligible enemy HumanoidRootParts to a minimum 6 studs on each axis, preserving originally larger axes. Size is adjustable from 2 to 12. It applies only to alive enemies within 300 studs, with a separate team filter. An optional amber box shows the local resized volume.

Only Size, CanCollide, and CanQuery change locally; CanTouch is untouched. Original changed values are restored on disable, death, team/range exclusion, root removal/replacement, character/player removal, unload, or reinitialization. Visibility checks exclude artificially enlarged roots so a protruding local box does not make a hidden torso appear visible.

**This does not establish a larger server damage hitbox.** Weapons may use different queries, filters, or server validation. No weapon remote, automatic firing, damage routine, or anti-cheat bypass is implemented. Keep this off while diagnosing camera response or delayed damage.

## Verification and limits

Official standalone Luau 0.745 compilation passed. All **267 local checks passed**: 21 scalar smoothing checks, 73 client/lifecycle checks, 38 touch checks, 36 local-resize checks, 62 tracking/scheduler checks, and 37 head-preference checks. Independent static reviews identified recoil-feedback, selected-part invalidation, and unlocked-ranking issues. Their covering regressions were reproduced before fixing and now pass.

New regressions reproduce and verify: next-render acquisition after an empty scan; cumulative convergence with an absolute-reset camera; convergence with a camera following CurrentCamera; late camera writers; release continuity; zero-strength native input; position changes before preparation; observed and unobserved incremental recoil; early resets to a known base; alignment status; obstruction/FOV/camera reasons; and complete render-phase cleanup.

The new preference checks use scripted uniform samples to verify threshold behavior, stable choice lifetime, visible/missing-part fallback, queued unlocked reselection, and cleanup. They do not validate a live headshot distribution. The scheduler/rotation fixture is a deterministic yaw-camera test double. It does not validate real Roblox 3D camera controllers, tablet touch delivery, weapon sampling phases, live Arsenal, server hit acceptance, latency, or hardware performance. Client gun code can sample the camera in different engine phases; this script does not hook or verify those weapon paths. If status is LOCKED but manual shots are delayed or rejected, actual game/input/network evidence is needed.

Primary references: [Random](https://create.roblox.com/docs/reference/engine/datatypes/Random), [CFrame composition and FuzzyEq](https://create.roblox.com/docs/reference/engine/datatypes/CFrame), [render callback priorities](https://create.roblox.com/docs/reference/engine/classes/RunService), [raycasting](https://create.roblox.com/docs/workspace/raycasting), [server-side weapon validation](https://create.roblox.com/docs/scripting/security/client-server-boundary).

