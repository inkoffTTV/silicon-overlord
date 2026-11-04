# Wire protocol v1 (WebSocket, JSON text frames)

Endpoint: `ws://<host>:7350/ws` (later `wss://` behind a reverse proxy). One JSON object per frame,
field `t` = message type. Numbers are JSON numbers; Lua maps with non-string keys are sent with string keys.

## Client → server
| t | fields | reply |
|---|---|---|
| hello | v:1, name, token? (saved from a previous welcome) | welcome {playerId, token, name} |
| create | company:{name, colorA:"#RRGGBB", colorB, mode:"solo"/"cofounder"} | joined + snapshot |
| join | code:"ABC-123" | joined + snapshot, or error |
| resume | — (rejoin last company of this token) | joined + snapshot, or error |
| leave | — | left |
| act | id:int, action:String, args:Object | res {id, ok, data?, error?} |
| speed | speed: 0/1/2/4/8 | (sections time) |
| pos | p:[x,y,z], yaw, pitch, anim:String (≤10 Hz) | broadcast peers |
| chat | text (≤200 chars) | broadcast chat |
| ping | n | pong {n} |

`act.action` uses the Roblox ActionRouter names (startResearch, createBlueprint, updateBlueprint,
publishBlueprint, launchProduct, setPrice, hire, buildRoom, upgradeHQ, ...) with the same payloads.

## Server → client
| t | fields |
|---|---|
| welcome | playerId:int, token:String, name |
| joined | code, companyId, you:{userId, role}, members:[{userId,name,color,role,online}] |
| snapshot | state: full CompanyState |
| sections | data:{sectionKey: value} — top-level CompanyState keys that changed (replace whole key) |
| res | id, ok, data?, error? |
| notify | kind ("info"/"success"/"warning"/"error"), title, body |
| members | list as in joined |
| peers | list:[{userId, name, color, p, yaw, pitch, anim}] |
| chat | userId, name, text |
| left | reason |
| error | message |
| pong | n |

Room codes: 6 chars from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, shown as `ABC-123`.
