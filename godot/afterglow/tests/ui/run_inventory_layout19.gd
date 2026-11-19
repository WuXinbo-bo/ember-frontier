extends "res://tests/ui/run_factory_native_drag.gd"
## Unchanged Native save; real slot indices, native GUI events and responsive bounds.
const F=preload("res://scripts/ui/factory_projection.gd")
const Access=preload("res://scripts/ui/factory_service_access.gd")

func _initialize()->void:
	create_timer(90).timeout.connect(func():check("inventory19 finishes before watchdog",false);finish(2))
	call_deferred("run")

func tagged(key:String)->Array:
	var result:Array=[]
	for node in ui.find_children("*","Control",true,false):
		if node.has_meta(key):result.append(node)
	return result

func inventory_slots(stock_id:String)->Array:
	return slots(ui).filter(func(node):return node.slot.get("kind")=="inventory" and node.slot.get("stock_id")==stock_id)

func verify_slots(stock:Dictionary,label:String)->void:
	var actual:Array=inventory_slots(str(stock.get("id","")))
	var expected:Array=ui.layout.cells(stock,ui.snapshot)
	var indices:Array=[]
	var keys:Array=[]
	var unique_keys:Dictionary={}
	for node in actual:
		indices.append(int(node.slot.index))
		keys.append(str(node.get_meta("ui_focus_key","")))
		unique_keys[str(node.get_meta("ui_focus_key",""))]=true
	indices.sort()
	var wanted:Array=[]
	for index in expected.size():wanted.append(index)
	check(label+" preserves every original slot index once",indices==wanted,{"actual":indices,"count":expected.size()})
	check(label+" preserves unique original focus keys",keys.size()==unique_keys.size() and keys.all(func(value):return str(value).begins_with(str(stock.id)+":")))
	var scroll_rect:Rect2=ui._scroll.get_global_rect()
	check(label+" slots fit horizontally inside page",actual.all(func(node):
		var rect:Rect2=node.get_global_rect()
		return rect.position.x>=scroll_rect.position.x-1 and rect.end.x<=scroll_rect.end.x+1),{"scroll":str(scroll_rect),"first":str(actual[0].get_global_rect()) if not actual.is_empty() else "none"})

func expose(node:Control)->void:
	if node!=null:ui._scroll.ensure_control_visible(node)
	await idle()

func first_material(stock_id:String)->Button:
	for node in inventory_slots(stock_id):
		if node.slot.get("reference",{}).get("kind")=="item" and float(node.slot.get("quantity",0))>0:return node
	return null

func reach_stock(subject:String)->bool:
	var module:Dictionary={}
	# The no-page UI intentionally holds only the HUD projection. Resolve the
	# stock's owner from the original complete public facade, which still
	# applies player discovery and permissions; never scan private world data.
	var published:Dictionary=runtime.factory_snapshot("player",false)
	for candidate:Dictionary in F.rows(published,"modules","instances"):
		if candidate.get("stock_refs",{}).values().has(subject):module=candidate;break
	check("source belongs to an original published module",not module.is_empty(),subject)
	if module.is_empty():return false
	ui.open_panel("factory_module",str(module.id));await idle()
	var provider:Dictionary=ui.read_service_approaches(str(module.id),true)
	var candidates:Array=Access.rows(provider,module).filter(func(row:Dictionary):return row.get("stock_ref")==subject)
	var reached:bool=candidates.any(func(row:Dictionary):return provider.get("available",false) and row.get("at_service",false))
	var walk:Dictionary={}
	if not reached:
		for row:Dictionary in candidates:
			if Access.access_reason(provider,row).is_empty():walk=Access.walk_command(row)
			if not walk.is_empty():break
		check("original public approach supplies a real walk",not walk.is_empty(),provider)
		if walk.is_empty():return false
		ui.close_panels();runtime.set_paused(false)
		walk.merge({"command_id":"inventory19-walk","actor_id":"player"},true)
		var started:Dictionary=runtime.command(walk)
		check("original walk command is admitted",started.get("ok",false),started)
		if not started.get("ok",false):return false
		for _index in 1400:
			if runtime.actor("player").get("intent")==null:break
			runtime.tick(0.1)
		check("original walk finishes within bounded simulation",runtime.actor("player").get("intent")==null)
		ui.open_panel("factory_module",str(module.id));await idle()
	provider=ui.read_service_approaches(str(module.id),true)
	candidates=Access.rows(provider,module).filter(func(row:Dictionary):return row.get("stock_ref")==subject)
	reached=candidates.any(func(row:Dictionary):return provider.get("available",false) and row.get("at_service",false))
	check("actual arrival makes exact original stock locally reachable",reached,provider)
	ui.close_panels();await idle()
	return reached

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():return finish(2)
	output=args[0];DirAccess.make_dir_recursive_absolute(output)
	if args.size()<2:check("unchanged Native save supplied",false);return finish(1)
	var original:=FileAccess.get_file_as_string(args[1])
	var decoded:Dictionary=Store.decode(original)
	check("unchanged Native save decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=TestNative.new();root.add_child(host)
	var made:Dictionary=host._assemble(decoded.capture)
	check("original Native owners assemble",made.get("ok",false),made.get("reason"))
	if not made.get("ok",false):return finish(1)
	runtime=made.runtime;world=made.world
	router=Router.new();host.add_child(router);router.configure(runtime)
	ui=Mount.mount(host,runtime,router);await idle()
	var subject:String=args[2] if args.size()>2 else "r34:generated:RH-HOME:home:stock:supplies"
	if not await reach_stock(subject):return finish(1)
	var before:Dictionary=runtime.capture_checkpoint()
	for dimensions in [Vector2i(1000,700),Vector2i(1280,800)]:
		for scale_value in [1.0,1.25]:
			ui.close_panels();await idle()
			root.size=dimensions;root.content_scale_size=dimensions
			ui.set_text_scale(scale_value);await idle()
			for target in ["","pack:player",subject]:
				ui.open_panel("factory_inventory",target);await idle();await idle()
				var label:String=str(dimensions)+" scale "+str(scale_value)+" "+target
				var paired:bool=target==subject
				check(label+" dialog and close button stay inside viewport",root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and root.get_visible_rect().encloses(ui._back_button.get_global_rect()),str(ui._dialog.get_global_rect()))
				check(label+" shows each real stock once",tagged("ui_inventory_stock").size()==(2 if paired else 1))
				verify_slots(P.player_stock(ui.snapshot),label+" backpack")
				if paired:
					var current:Dictionary=runtime.stock(subject)
					check(label+" real current container exists",not current.is_empty())
					if not current.is_empty():verify_slots(current,label+" source")
				else:
					check(label+" never offers self take-all or transfer",keyed("factory:inventory:take-all")==null and keyed("factory:inventory:transfer")==null)
				ui.close_panels();await idle()
	check("layout and read-only resize never change authority",Data.json_equal(before,runtime.capture_checkpoint()))
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	ui.set_text_scale(1.0);ui.open_panel("factory_inventory",subject);await idle();await idle()
	var source:Button=first_material(subject)
	check("real source publishes an available material for Shift transfer",source!=null)
	if source!=null:
		var item_id:String=str(source.slot.reference.item_id)
		var source_before:float=float(runtime.stock(subject).items.get(item_id,0))
		var pack_before:float=float(runtime.actor("player").pack.get(item_id,0))
		await expose(source);await click(source.get_global_rect().get_center(),MOUSE_BUTTON_LEFT,true)
		var transferred:float=source_before-float(runtime.stock(subject).items.get(item_id,0))
		check("native Shift transfers finite source to actual pack exactly once",transferred>0 and float(runtime.actor("player").pack.get(item_id,0))==pack_before+transferred and ui.carry.is_empty() and ui.drag.is_empty(),{"source_before":source_before,"transferred":transferred,"notice":ui._notice.text})
		var paid:Dictionary=runtime.capture_checkpoint()
		ui.open_panel("factory_inventory","pack:player");await idle();await idle()
		source=cell("inventory","pack:player",-1,"item:"+item_id)
		await expose(source)
		check("single actual backpack keeps native drag callbacks",await start(source))
		var destination:Button=cell("hotbar","pack:player",6)
		if destination!=null:await motion(destination.get_global_rect().get_center());await button(false)
		check("native drag binds original reference without cloning goods",destination!=null and P.reference_key(router.state().slots[6])=="item:"+item_id and Data.json_equal(paid,runtime.capture_checkpoint()) and ui.drag.is_empty() and ui.carry.is_empty())
	check("input Native save stays byte-identical",FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row):return row.ok) else 1)
