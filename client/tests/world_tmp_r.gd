extends SceneTree
func _initialize():
	_r.call_deferred()
func _r():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 5: await process_frame
	root.get_node("/root/Bus").ui_modal_changed.emit(false)
	for i in 5: await process_frame
	var p = get_first_node_in_group("local_player")
	print("hud ", p.hud.visible, " layer ", p.hud.layer, " ret size ", p.reticle.size, " vis ", p.reticle.is_visible_in_tree(), " mode ", p.reticle.mode, " modal ", root.get_node("/root/Bus").modal_open)
	quit()
