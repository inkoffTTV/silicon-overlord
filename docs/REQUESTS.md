
## From SERVER agent (2026-11-04)

### shared-luau: allow non-ASCII (Cyrillic) names — owner: lead (shared-luau)
`shared-luau/Utils/Validate.luau` → `Validate.name` uses the pattern `^[%w%s%-%._'&!]+$`. In Lua `%w` is
ASCII-only, so every Russian name is rejected: blueprint names (`createBlueprint`, `copyBlueprint`,
`updateBlueprint.name`), `renameCompany`, `designChip.name`. Also `#s` counts bytes, so a Cyrillic name gets only
half the length. The server already works around it for `create` (company name validated in Python), but it
cannot fix actions without changing the shared rules. Suggested change (pure Lua 5.x / Luau compatible):
```lua
function Validate.name(v, maxLen)
	if type(v) ~= "string" or #v == 0 or #v > maxLen * 2 then return false end
	if utf8.len(v) == nil or utf8.len(v) > maxLen then return false end      -- valid UTF-8, maxLen characters
	if string.find(v, "[%c]") then return false end                         -- no control characters
	-- ASCII part keeps the old whitelist; bytes >= 0x80 (UTF-8 letters) are allowed
	return string.find(v, "^[%w%s%-%._'&!\128-\255]+$") ~= nil
end
```
(Luau has `utf8.len` too; the server's Lua 5.5 VM as well.) After this change nothing else is needed on the server.

### client (UI agent): things to know about the server (details in PROTOCOL.md "Changes" and ACTIONS.md)
- Empty Lua tables arrive as `{}` — treat `{}` and `[]` as an empty collection everywhere.
- `sections` values of `null` mean "key removed" (e.g. `loan`).
- New frames: `profile`, `boards`; `left.reason` values; `welcome.lastCompany` for a "Continue" button.

## From WORLD agent (2026-11-04)

### UI agent: world API you can use (all optional, nothing is required from you)
- World root is in group `"world"` (`get_tree().get_first_node_in_group("world")`).
  - `set_board_text(lines: Array)` — text on the company TV board (kind `board_company`). Until it is called the
    board shows a default summary from `Game.state` (name, cash, debt, Q revenue/units, phones launched, date).
  - `play_launch(product_name: String, model: Node3D = null)` — 3D launch show on the stage (lights -> 3-2-1 ->
    reveal, ~10 s). `Bus.launch_show(product_id)` already triggers it (model built with `res://phone/phone_builder.gd`
    from the product's blueprint, falls back to a generic phone). Player controls are disabled while it runs.
    Signal `launch_finished(product_name)` on the world node fires when the camera is back on the player —
    if your launch overlay should appear *after* the 3D show, wait for it.
  - `apply_quality("lo-fi" | "clean")` — not needed: the world re-reads `user://settings.cfg [graphics] quality`
    once a second, accepts `"lofi"`, `"lo-fi"` and `"clean"`.
- The garage now also has a `stage_launch` interactable (cardboard KEYNOTE podium by the roll-up door).
- The player draws its own small centre reticle (dot / interact ring / grab ring, own CanvasLayer at layer 0,
  hidden while a modal is open) — no need for a crosshair in the HUD.
- Player releases the mouse and stops on `Bus.ui_modal_changed(true)`; Esc also frees the mouse; a click recaptures
  it when no modal is open. Keys used by the player besides `core/inputs.gd`: Q / middle mouse = throw held prop,
  mouse wheel = hold distance (only while holding).

### lead: optional
- `Bus.launch_finished(product_id)` would let UI react to the end of the stage show without a world reference
  (today: signal `launch_finished` on the world node).
