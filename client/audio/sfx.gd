extends Node
## Audio service (AUDIO agent owns client/audio/**). Stable API used by world and UI:
##   Sfx.play(name: String, at: Variant = null, volume_db := 0.0)  # at = Vector3 for 3D, null for 2D
##   Sfx.ui(name: String)                                           # UI click/hover/confirm/error/toast
##   Sfx.music(name: String)                                        # "" stops; crossfades
##   Sfx.ambient(name: String)                                      # room tone loop ("garage", "loft", "stage", "")
##   Sfx.speak(user_id: int, display_name: String, text: String, at: Variant = null)  # chat → character voice
## Until implemented every call is a safe no-op.

func play(_name: String, _at: Variant = null, _volume_db := 0.0) -> void: pass
func ui(_name: String) -> void: pass
func music(_name: String) -> void: pass
func ambient(_name: String) -> void: pass
func speak(_user_id: int, _display_name: String, _text: String, _at: Variant = null) -> void: pass
