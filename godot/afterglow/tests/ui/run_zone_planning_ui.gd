extends "res://tests/ui/run_os_feedback_ui.gd"
## Exact old QA capture + actual Native/Runtime/zone/ecology services. The
## supplied hit is an observed World cell, not a fabricated free-land fixture.
## This verifies Controls and the adapter contract; A owns real ray/OS tests.
var region := ""
var start_cell: Dictionary = {}
var created_id := ""

func run() -> void:
	var args := OS.get_cmdline_user_args(); output=args[0]; DirAccess.make_dir_recursive_absolute(output)
	if args.size()<2: check("sealed actual25 capture supplied",false); return finish(1)
	var original := FileAccess.get_file_as_string(args[1]); var decoded := Store.decode(original)
	check("unchanged actual25 input decodes",decoded.get("ok",false))
	if not decoded.get("ok",false): return finish(1)
	root.size=Vector2i(1280,800); root.content_scale_size=root.size
	host=TestNative.new(); root.add_child(host)
	if not await assemble_capture(decoded.capture): return finish(1)
	var before: Dictionary = runtime.capture_checkpoint()
	region=str(runtime.actor("player").regionId)
	# This fixture supplies observed cells instead of mounting DirectInteraction.
	router.set_world_pointer_consumer(Callable(), func(): return ui.is_zone_planning())
	ui.open_panel("zone_planning"); await idle(); await idle()
	check("original GameUI mounts actual zone service",ui.is_zone_planning() and ui.planning_active() and ui.zone_planning.projection.get("available",false))
	check("planning keeps its panel shortcuts and hides the world hotbar", not ui._hotbar.is_visible_in_tree() and ui._modal_policy_hint.text.is_empty())
	check("planning sidebar preserves scene and modal world policy",ui._dialog.size.x<=1280*.42 and not router.state().pause_reasons.modal and root.get_visible_rect().encloses(ui._dialog.get_global_rect()),{"rect":str(ui._dialog.get_global_rect()),"router":router.state()})
	var reads: int=ui.zone_planning.projection_reads
	for index in 6: ui.refresh(); ui._on_router_changed()
	await idle()
	check("local refresh and router notifications reuse zone projection",ui.zone_planning.projection_reads==reads,{"before":reads,"after":ui.zone_planning.projection_reads})
	ui._on_changed({"clock":runtime.clock(),"revision":before.command_revision}); await idle()
	check("clock-only notification does not pull zone list",ui.zone_planning.projection_reads==reads)
	ui._on_changed({"unknown_permission_refresh":true}); await idle()
	check("unknown authority notification immediately invalidates",ui.zone_planning.projection_reads>reads)
	start_cell=find_patch()
	check("real known resident terrain supplies four-by-three patch",not start_cell.is_empty(),start_cell)
	if start_cell.is_empty(): return finish(1)
	await draft(start_cell,offset(start_cell,2,2))
	check("drag draft shows original valid cells and estimate without committing",ui.zone_planning.preview.get("ok",false) and ui.zone_planning.preview.cells.size()==9 and ui.planning_view().preview.cells==ui.zone_planning.preview.cells and Data.json_equal(before,runtime.capture_checkpoint()),ui.zone_planning.preview)
	var replant := keyed("zone:policy:replant") as CheckBox
	check("visible replant default matches service default",replant!=null and replant.button_pressed)
	# Model a stale display without changing the transaction or terrain fixture.
	ui.zone_planning.preview.cells.pop_back()
	var stale: Dictionary = ui.zone_planning.submit(ui)
	check("confirmation reads authority again and retains a changed draft", not stale.get("ok", false) and ui.zone_planning.preview.cells.size() == 9 and runtime.zone_records().is_empty() and not ui.zone_planning.bounds.is_empty(), stale)
	await idle()
	var focus := root.gui_get_focus_owner()
	if focus != null: focus.release_focus()
	await key(KEY_ENTER)
	await key(KEY_ENTER)
	var zones: Array=runtime.zone_records()
	check("native Enter confirms exactly one zone",zones.size()==1,{"count":zones.size(),"receipt":ui.zone_planning.receipt})
	if zones.size()!=1:return finish(1)
	created_id=str(zones[0].id); ui.zone_planning.choose_zone(ui,created_id); await idle()
	check("selected projection has actual cells not bounds reconstruction",ui.zone_planning.selected().get("cells",[]).size()==9 and ui.zone_planning.selected().policy.replant==true)
	ui.zone_planning.choose_tool(ui,"erase"); await idle()
	await draft(offset(start_cell,1,1),offset(start_cell,1,1))
	check("erase preview identifies original selected intersection",ui.zone_planning.preview.get("ok",false) and ui.zone_planning.preview.cells.size()==1)
	await activate("zone:submit")
	check("erase removes only one planned cell",runtime.zone_records()[0].cells.size()==8)
	ui.zone_planning.choose_tool(ui,"append"); await idle()
	await draft(offset(start_cell,3,0),offset(start_cell,3,2)); await activate("zone:submit")
	var current: Dictionary=runtime.zone_records()[0]
	check("append uses authoritative union and preserves erased hole",current.cells.size()==11 and not current.cells.any(func(cell:Dictionary):return cell.x==int(start_cell.x)+1 and cell.z==int(start_cell.z)+1),current)
	var policy_before: Dictionary=runtime.capture_checkpoint()
	ui.zone_planning.policy.mature_only=false
	ui.queue_refresh(); await idle(); await activate("zone:policy:apply")
	check("policy command changes actual plan without resource settlement",runtime.zone_records()[0].policy.mature_only==false and same_resources(policy_before,runtime.capture_checkpoint()),{"policy":runtime.zone_records()[0].policy,"receipt":ui.zone_planning.receipt})
	var stable: Dictionary=runtime.capture_checkpoint()
	await motion(Vector2(1100,250))
	ui.zone_planning.choose_tool(ui,"create"); await idle()
	ui.handle_world_click(hit(start_cell),mouse_button(true))
	ui.handle_world_click({},mouse_button(false)); await idle()
	check("unknown release retains last valid point without committing",not ui.zone_planning.drawing and not ui.zone_planning.bounds.is_empty() and Data.json_equal(stable,runtime.capture_checkpoint()))
	ui.zone_planning.cancel_draft()
	ui.handle_world_click(hit(start_cell),mouse_button(true))
	await motion(ui._title.get_global_rect().get_center()); await button(false)
	check("release over real sidebar ends drag without committing",not ui.zone_planning.drawing and Data.json_equal(stable,runtime.capture_checkpoint()))
	await draft(start_cell,start_cell); await key(KEY_ESCAPE)
	check("first Esc retracts draft and retains planning page",ui.is_zone_planning() and ui.zone_planning.bounds.is_empty() and Data.json_equal(stable,runtime.capture_checkpoint()))
	await key(KEY_ESCAPE)
	check("next Esc exits planning and clears renderer preview",not ui.is_zone_planning() and ui.planning_view().preview.is_empty() and Data.json_equal(stable,runtime.capture_checkpoint()))
	ui.open_panel("zone_planning"); await idle(); await draft(start_cell,start_cell); ui._on_focus_exited(); await idle()
	check("focus release preserves resolved draft without world changes",not ui.zone_planning.drawing and not ui.zone_planning.bounds.is_empty() and Data.json_equal(stable,runtime.capture_checkpoint()))
	for viewport: Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport; root.content_scale_size=viewport; ui.set_text_scale(1.0 if viewport.x==1280 else 1.5); await idle(); await idle()
		check("planning stays scene-side at viewport "+str(viewport),root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and ui._dialog.size.x<=viewport.x*.45,str(ui._dialog.get_global_rect()))
		check("planning toolbar fits scroll width "+str(viewport),ui._body.get_combined_minimum_size().x<=ui._scroll.size.x+1,{"body":ui._body.get_combined_minimum_size().x,"scroll":ui._scroll.size.x})
	ui.zone_planning.choose_zone(ui,created_id); ui.factory_view["fold:zone:maintenance"]=true; ui.queue_refresh(); await idle()
	await activate("zone:cancel")
	check("stopping zone first requires native consequence confirmation",ui.zone_planning.confirming_cancel and runtime.zone_records()[0].enabled)
	await activate("zone:cancel:confirm")
	check("confirmed stop disables real plan while keeping worked world",not runtime.zone_records()[0].enabled and runtime.zone_records()[0].cells.size()==11 and same_resources(before,runtime.capture_checkpoint()),{"zone":runtime.zone_records()[0],"receipt":ui.zone_planning.receipt})
	var encoded: Dictionary=Store.encode(runtime.capture_checkpoint())
	check("real new zone persists through existing codec",encoded.get("ok",false),encoded.get("reason"))
	if encoded.get("ok",false):
		var saved: Dictionary=Store.decode(encoded.text)
		if await assemble_capture(saved.capture): check("cold Native assembly keeps exact zone cells and stopped policy",runtime.zone_records().size()==1 and Data.json_equal(runtime.zone_records()[0].cells,current.cells) and not runtime.zone_records()[0].enabled)
	check("old input bytes and original resource facts stay unchanged",FileAccess.get_file_as_string(args[1])==original and same_resources(before,runtime.capture_checkpoint()))
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)

func find_patch() -> Dictionary:
	var actor: Dictionary=runtime.actor("player"); var size: float=world.config().cellSize
	var x0:=floori(float(actor.x)/size); var z0:=floori(float(actor.z)/size)
	for dz: int in range(-16,17,4):
		for dx: int in range(-16,17,4):
			var spec: Dictionary={"kind":"forestry","region_id":region,"bounds":{"x0":x0+dx,"z0":z0+dz,"x1":x0+dx+4,"z1":z0+dz+3},"policy":{}}
			var value: Dictionary=runtime.zone_preview(spec)
			if value.get("ok",false) and value.get("cells",[]).size()==12:return value.cells[0].duplicate(true)
	return {}

func same_resources(a: Dictionary,b: Dictionary) -> bool:
	# Successful commands add real zone-changed ledger events. Those are not
	# resource mutations; all other facts must remain byte-equivalent in JSON.
	var left: Dictionary=a.facts.duplicate(true);var right: Dictionary=b.facts.duplicate(true)
	left.erase("ledger");right.erase("ledger")
	return Data.json_equal(left,right)

func offset(cell: Dictionary, x: int, z: int) -> Dictionary:
	var size: float=world.config().cellSize
	var y: Variant=world.surface_height((int(cell.x)+x+.5)*size,(int(cell.z)+z+.5)*size)
	return {"x":int(cell.x)+x,"y":roundi(float(y)/size) if y!=null else int(cell.y),"z":int(cell.z)+z}

func hit(cell: Dictionary) -> Dictionary: return {"cell":cell,"region_id":region}

func mouse_button(down: bool) -> InputEventMouseButton:
	var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=down; event.position=Vector2(1100,250); return event

func draft(first: Dictionary,last: Dictionary) -> void:
	await motion(Vector2(1100,250)); ui.handle_world_click(hit(first),mouse_button(true))
	var event:=InputEventMouseMotion.new(); event.position=Vector2(1150,300)
	ui.handle_world_click(hit(last),event); ui.handle_world_click(hit(last),mouse_button(false))
	await create_timer(.12).timeout; await idle()

func activate(id: String) -> void:
	var node:=keyed(id) as Button
	check("real Control exists for "+id,node!=null)
	if node==null:return
	if ui._scroll.is_ancestor_of(node): ui._scroll.ensure_control_visible(node)
	await idle()
	var rect:=node.get_global_rect()
	check("real Control reachable for "+id,root.get_visible_rect().encloses(rect) and not node.disabled,{"rect":str(rect),"reason":node.tooltip_text})
	if not node.disabled:await click(rect.get_center())

func finish(code: int) -> void:
	var failed: int=checks.filter(func(row:Dictionary):return not row.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"method":"Unchanged actual25 QA + real Native/Runtime/Zone/Ecology owners; observed resident World cells supplied to A/UI pointer contract; native Viewport buttons/Esc; original codec/cold Native restore","scope":"Current-source headless Control and transaction support only; no real renderer ray, physical OS, package, VA or FPS"},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(code)
