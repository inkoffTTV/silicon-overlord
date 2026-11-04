# Silicon Overlord Online — architecture

Standalone online version of the Roblox game in /home/user/PhoneTycoon (same rules, new client).

```
shared-luau/   game rules, data and balance (copied from the Roblox project's src/shared).
               Pure Luau modules: Domain/*, Data/*, Config/*. THE single source of game rules.
tools/         luau_strip.py (Luau -> plain Lua), lua_shim.lua (Roblox globals for pure modules)
server/        Python 3.11+ authoritative server: lupa (Lua VM) runs shared-luau,
               websockets for clients, SQLite saves, room codes. Runs on the Linux VPS.
client/        Godot 4.5 project (GDScript, Forward+). First-person 3D world, UI. Talks to the
               server over WebSocket only; never decides game outcomes itself.
docs/          this file, PROTOCOL.md (wire format), VISUAL_STYLE.md, DEPLOY.md
```

## Ownership (parallel work)
| Area | Owner | Paths |
|---|---|---|
| Server, protocol implementation, saves, deploy | SERVER agent | server/**, docs/DEPLOY.md |
| 3D world, player controller, look/post-processing, props, avatars of other players | WORLD agent | client/world/**, client/player/**, client/fx/**, client/tools/shot*, docs/VISUAL_STYLE.md |
| Menus, HUD, screens (designer, research, market...), networking client, phone 3D preview model | UI agent | client/ui/**, client/net/**, client/phone/** |
| Shared skeleton (project.godot, main.tscn, core/*) | lead | client/project.godot, client/main.tscn, client/core/** |

Rules: do not edit another owner's paths. If you need something there, add a TODO in docs/REQUESTS.md.

## Client contracts (between WORLD and UI)
- `res://main.tscn`: Main (Node3D) → World (instance of res://world/world.tscn), Player (res://player/player.tscn),
  UI (CanvasLayer, res://ui/ui_root.tscn). Autoloads: `Inputs` (core/inputs.gd), `Bus` (core/bus.gd),
  `Net` (net/net.gd, UI agent), `Game` (core/game.gd: replicated state cache).
- `Bus` signals (core/bus.gd) are the ONLY coupling between world and UI:
  - `interact(kind: String, id: String)` — player pressed E on an interactable. kinds: "pc_design",
    "whiteboard_research", "workbench_production", "phone_shelf", "door_exit", "board_company", "stage_launch".
  - `ui_modal_changed(open: bool)` — UI opened/closed a full-screen screen; player releases/captures the mouse
    and stops moving while open.
  - `state_changed(keys: Array)` — Game cache updated (emitted by Game).
  - `notify(kind: String, title: String, body: String)`
  - `launch_show(product_id: String)` — UI asks the world to play the launch-on-stage sequence.
  - `world_rebuild()` — HQ level / rooms changed.
- Interactables: any node in group "interactable" with metadata `kind`, `id`, `prompt` (shown by UI as
  "[E] prompt"). Player raycasts and emits `Bus.interact`, and `Bus.focus_changed(prompt or "")`.

## Server
Authoritative. Each company = session with a Lua CompanyState, ticking days at speed 0/1/2/4/8
(same Balance as Roblox). Clients send actions (same names/payloads as the Roblox ActionRouter) and
receive snapshot + changed sections. See PROTOCOL.md.
