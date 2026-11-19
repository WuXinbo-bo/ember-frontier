extends "res://tests/ui/run_zone_planning_ui.gd"
## Delta only: ephemeral token reload, meter-height terrain, real candidate
## queries, actual finite life action. No injected land, item, job or clock.
const Content=preload("res://scripts/runtime/content_definitions.gd")

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(original)
	check("original actual25 input decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=TestNative.new();root.add_child(host)
	if not await assemble_capture(decoded.capture):return finish(1)
	region=str(runtime.actor("player").regionId);ui.open_panel("zone_planning");await idle();await idle()
	var stable:=runtime.capture_checkpoint();var reads:int=ui.zone_planning.projection_reads
	var basis:Dictionary=runtime.zone_view_basis();var same:=world.snapshot();var loaded:Dictionary=world.load_snapshot(same)
	ui.refresh();await idle()
	check("same-world same-revision reload invalidates exact token",loaded.get("ok",false) and runtime.zone_view_basis().zones_revision==basis.zones_revision and runtime.zone_view_basis().zones_generation!=basis.zones_generation and ui.zone_planning.projection_reads==reads+1 and Data.json_equal(stable,runtime.capture_checkpoint()))
	reads=ui.zone_planning.projection_reads
	for index in 5:ui.refresh();ui._on_router_changed()
	await idle();check("stable token still reuses list across router refresh",ui.zone_planning.projection_reads==reads)
	start_cell=find_patch();check("real known patch found",not start_cell.is_empty(),start_cell)
	if start_cell.is_empty():return finish(1)
	ui.zone_planning.kind="terrain";ui.zone_planning.policy.clear();ui.zone_planning.clear_preview();ui.queue_refresh();await idle()
	var point:=hit(start_cell);var size:float=world.config().cellSize
	var height:float=world.surface_height((start_cell.x+.5)*size,(start_cell.z+.5)*size)
	point.position={"x":(start_cell.x+.5)*size,"y":height,"z":(start_cell.z+.5)*size}
	ui.handle_world_click(hit(start_cell),mouse_button(true));await idle()
	check("missing surface height refuses terrain draft and zero fallback",not ui.zone_planning.drawing and not ui.zone_planning.policy.has("target_height"))
	ui.handle_world_click(point,mouse_button(true));ui.handle_world_click(point,mouse_button(false));await create_timer(.12).timeout;await idle()
	check("terrain initializes meters from true top height",ui.zone_planning.policy.target_height==height and ui.zone_planning.make_spec().policy.target_height==height and ui.zone_planning.anchor.height_m==height,{"height":height,"solid_cell":start_cell.y,"preview":ui.zone_planning.preview})
	var mode:=keyed("zone:terrain:mode") as OptionButton;var fill:=keyed("zone:terrain:fill") as OptionButton
	check("five exact terrain modes and three legal material ids are offered",mode!=null and mode.item_count==5 and fill!=null and fill.item_count==3)
	var changed_height:=height+.5;ui.zone_planning.policy.target_height=changed_height
	for kind_:String in ["cut","fill","balance","ramp_x","ramp_z"]:
		ui.zone_planning.policy.mode=kind_;ui.zone_planning.policy.fill_material=3
		ui.handle_world_click(point,mouse_button(true));ui.handle_world_click(point,mouse_button(false));await create_timer(.12).timeout;await idle()
		check("explicit height and legal fill survive real preview "+kind_,ui.zone_planning.make_spec().policy.target_height==changed_height and ui.zone_planning.make_spec().policy.fill_material==3 and Data.json_equal(stable,runtime.capture_checkpoint()))
	check("typed material estimates render without changing authority",Data.json_equal(stable,runtime.capture_checkpoint()))
	ui.zone_planning.clear_preview();ui.zone_planning.kind="farm";ui.zone_planning.policy.clear();ui.queue_refresh();await idle()
	var crops:=keyed("zone:policy:crop_id") as OptionButton
	check("real farm publishes potato bean rice choices",crops!=null and crops.item_count==3 and keyed("zone:reserve_seed")!=null)
	ui.zone_planning.kind="forestry";ui.zone_planning.policy.clear();await draft(start_cell,start_cell);await activate("zone:submit")
	var zones:Array=runtime.zone_records();check("candidate test uses one actual created zone",zones.size()==1)
	if zones.size()==1:
		ui.zone_planning.choose_zone(ui,str(zones[0].id));await idle()
		var panel=ui.zone_planning.work_panel;var scan_count:int=panel.candidate_reads;var jobs_count:int=panel.projection_reads
		for index in 5:ui.refresh();ui._on_router_changed()
		await idle();check("idle jobs view never rescans candidates",panel.candidate_reads==scan_count and panel.projection_reads==jobs_count)
		await activate("zone:work:refresh")
		var expected:Array=runtime.zone_work_projection("player",true).candidates.filter(func(row:Dictionary):return row.zone_id==zones[0].id)
		check("explicit native refresh loads actual same-zone candidates only",panel.candidate_reads==scan_count+1 and Data.json_equal(panel.candidates,expected))
		var before_reject:=runtime.capture_checkpoint();var reject:Dictionary=ui.execute("zonework.start",str(zones[0].id),{"candidate_id":"expired:ui-test"})
		check("invalid current candidate fails atomically with actual feedback",not reject.get("ok",false) and Data.json_equal(before_reject,runtime.capture_checkpoint()) and not ui._notice.text.is_empty(),reject)
	ui.close_panels();ui.open_panel("factory_people");await idle();await idle()
	check("care uses actual finite safe water option",runtime.life_consumables("player","drink").size()==1 and runtime.life_consumables("player","drink")[0].item_id=="water" and keyed("care:select:drink")!=null)
	check("zero free food disables eat instead of faking a menu",runtime.life_consumables("player","eat").is_empty() and keyed("care:use:eat") is Button and keyed("care:use:eat").disabled)
	for id:String in ["r34:raw_water","r34:filtered_water","r34:potato_seed","r34:potato","r34:rice"]:check("unsafe or raw content excluded from life selection "+id,Content.consumable_definition(id).is_empty())
	var before_bad:=runtime.capture_checkpoint();var denied:Dictionary=ui.execute("drink","",{"item_id":"r34:raw_water"})
	check("explicit unsafe drink request rejected without lost stock",not denied.get("ok",false) and Data.json_equal(before_bad,runtime.capture_checkpoint()),denied)
	var before_key:=runtime.capture_checkpoint();await key(KEY_W);await key(KEY_E)
	check("care modal consumes movement and E",Data.json_equal(before_key,runtime.capture_checkpoint()))
	await activate("care:use:drink")
	check("native drink submits exact safe water and returns to scene",ui.pages.is_empty() and runtime.actor("player").get("intent") is Dictionary)
	for index in 100:runtime.tick(.02)
	check("finite safe water consumed once by real life action",runtime.actor("player").pack.water==0 and runtime.life_consumables("player","drink").is_empty(),runtime.actor("player").get("intent"))
	check("source save remains exact and resources never injected",FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)
