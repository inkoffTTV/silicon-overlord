
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
