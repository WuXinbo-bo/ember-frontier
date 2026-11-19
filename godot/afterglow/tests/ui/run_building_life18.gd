extends SceneTree
const Life=preload("res://scripts/ui/building_life_actions.gd")
const Housing=preload("res://scripts/ui/housing_panel.gd")

class Owner extends RefCounted:
	var homes:Dictionary={"available":true,"homes":[]}
	var food:Array=[]
	var drink:Array=[]
	func housing_projection(_actor:String)->Dictionary:return homes.duplicate(true)
	func life_consumables(_actor:String,kind:String)->Array:return (food if kind=="eat" else drink).duplicate(true)

class Facade extends RefCounted:
	var runtime:=Owner.new()
	var housing_view:=Housing.new()
	var text_scale:float=1.0
	var factory_view:Dictionary={}
	var factory:Dictionary={"water":{"available":true,"sources":[]}}
	var snapshot:Dictionary={"player":{"id":"player","stock_id":"pack:player"},"actors":[],"stocks":[{"id":"pack:player","owner":"player","searched":true,"items":{}}],"work_targets":[]}
	var denied:Array=[]
	var calls:Array=[]
	var pages:Array=[]
	var notices:Array=[]
	func request(kind:String,id:String,payload:Dictionary={},destination:Dictionary={})->Dictionary:return {"kind":kind,"target_id":id,"payload":payload,"destination":destination}
	func availability(command:Dictionary)->Dictionary:return {"ok":not denied.has(command.kind),"code":"FORBIDDEN" if denied.has(command.kind) else "OK","reason":"当前无权操作" if denied.has(command.kind) else ""}
	func paragraph(text:String,parent:Node)->Label:
		var node:=Label.new();node.text=text;parent.add_child(node);return node
	func add_button(text:String,callback:Callable,key:String,reason:String,parent:Node)->Button:
		var node:=Button.new();node.text=text;node.disabled=not reason.is_empty();node.set_meta("key",key);node.pressed.connect(callback);parent.add_child(node);return node
	func execute(kind:String,id:String,payload:Dictionary={},resume:bool=false,_worker:String="",destination:Dictionary={})->Dictionary:
		var command:=request(kind,id,payload,destination)
		if not availability(command).ok:return {"ok":false}
		calls.append(command.merged({"resume":resume}));return {"ok":true}
	func open_panel(page:String,id:String="")->void:pages.append({"page":page,"id":id})
	func queue_refresh()->void:pass
	func notify(message:String,_error:bool=false)->void:notices.append(message)

var checks:Array=[]
func check(name:String,ok:bool)->void:checks.append({"name":name,"ok":ok})
func _initialize()->void:call_deferred("run")
func find_button(parent:Node,key:String)->Button:
	for child:Node in parent.get_children():
		if child is Button and child.get_meta("key","")==key:return child
		var nested:=find_button(child,key)
		if nested!=null:return nested
	return null
func life_cards(parent:Node,kind:String)->Array:
	var result:Array=[]
	for child:Node in parent.get_children():
		if child.get_meta("ui_building_life_kind","")==kind:result.append(child)
		result.append_array(life_cards(child,kind))
	return result
func bed(id:String="bed")->Dictionary:return {"bed_id":id,"module_id":"home","available":true,"occupied":false,"occupant_ids":[],"permitted":true,"reachable":true,"prepared":true,"approach":{"regionId":"known","x":1,"y":0,"z":2}}
func run()->void:
	var ui:=Facade.new();var module:Dictionary={"id":"home","members":[]};var definition:Dictionary={"generation_role":"home"}
	ui.runtime.homes.homes=[{"id":"other","bed_count":99,"beds":[bed("other-bed")]},{"id":"home","design_capacity":15,"beds":[bed()]}]
	var body:=VBoxContainer.new();Life.render(ui,body,module,definition)
	check("home card uses real public bed rather than design capacity",find_button(body,"building-life:rest:bed")!=null and find_button(body,"building-life:rest:other-bed")==null)
	# C.card adds a native PanelContainer and returns its inner VBoxContainer;
	# identity belongs to the returned content node, not its decorative wrapper.
	var homes:Array=life_cards(body,"home")
	check("home body publishes machine-checkable card identity",homes.size()==1 and homes[0] is VBoxContainer and homes[0].get_meta("ui_building_life","")=="home")
	var rest:=find_button(body,"building-life:rest:bed")
	check("available exact bed permits original rest",rest!=null and not rest.disabled)
	if rest!=null:rest.pressed.emit()
	check("rest dispatch preserves original target and resumes world",ui.calls.size()==1 and ui.calls[0].kind=="rest" and ui.calls[0].target_id=="bed" and ui.calls[0].resume)
	body.free();body=VBoxContainer.new();ui.denied=["rest"];ui.housing_view.invalidate();Life.render(ui,body,module,definition)
	check("authority refusal leaves rest disabled",find_button(body,"building-life:rest:bed").disabled)
	check("refused rest can still offer exact proved walk",find_button(body,"building-life:bed-walk:bed")!=null)
	ui.runtime.homes.homes[1].beds[0].approach.x=8
	var walk:=find_button(body,"building-life:bed-walk:bed")
	if walk!=null:walk.pressed.emit()
	check("bed walk revalidates and rejects changed public approach",ui.calls.size()==1 and not ui.notices.is_empty())
	body.free();body=VBoxContainer.new();ui.denied=[];ui.housing_view.invalidate();ui.runtime.homes.homes[1].beds=[];Life.render(ui,body,module,definition)
	check("architectural capacity never creates synthetic rest actions",find_button(body,"building-life:rest:bed")==null)
	check("missing consumables stay explicit disabled actions",find_button(body,"building-life:consume:eat").disabled and find_button(body,"building-life:consume:drink").disabled)
	body.free();body=VBoxContainer.new();ui.runtime.food=[{"kind":"eat","item_id":"r34:meal_simple","name":"简餐","free":2}];ui.runtime.drink=[{"kind":"drink","item_id":"water","free":1}];Life.render(ui,body,module,{"mechanism":{"family":"canteen"}})
	find_button(body,"building-life:consume:eat").pressed.emit()
	check("canteen eating uses actual selected carried food",ui.calls.size()==2 and ui.calls[1].kind=="eat" and ui.calls[1].payload=={"item_id":"r34:meal_simple"})
	body.free();body=VBoxContainer.new();ui.runtime.drink=[{"kind":"drink","item_id":"r34:raw_water","free":0}];Life.render(ui,body,module,definition)
	check("unavailable raw stock is not offered as a drink",find_button(body,"building-life:consume:drink").disabled)
	body.free()
	ui.factory.water.sources=[{"id":"linked","discovered":true,"module_id":"home","status":"ready","allowed_actions":["module.water.draw"]},{"id":"nearby-unlinked","discovered":true,"region":"known"},{"id":"hidden","discovered":false,"module_id":"home"}]
	check("water cards require exact public link and discovery",Life.linked_water(ui.factory,module).size()==1 and Life.linked_water(ui.factory,module)[0].id=="linked")
	body=VBoxContainer.new();Life.render(ui,body,module,{"generation_role":"supply"})
	var draw:=find_button(body,"building-life:draw:linked")
	if draw!=null:draw.pressed.emit()
	check("linked water draw uses original source and player pack",ui.calls.size()==3 and ui.calls[2].kind=="module.water.draw" and ui.calls[2].target_id=="linked" and ui.calls[2].payload.output_id=="pack:player")
	body.free();body=VBoxContainer.new();ui.factory.water.sources=[];Life.render(ui,body,module,{"mechanism":{"family":"guard"}})
	check("guard family alone creates no invented assignment",body.get_child_count()==0)
	body.free();body=VBoxContainer.new();module.members=[{"id":"real-door"}];ui.snapshot.work_targets=[{"id":"guard-target","job":"guard","actual_target_id":"real-door"}];ui.snapshot.actors=[{"id":"friend","hp":100,"name":"同伴","relationship":{"member":true,"consent":true}}];Life.render(ui,body,module,{"mechanism":{"family":"guard"}})
	var guard:=find_button(body,"building-life:guard:home:friend")
	if guard!=null:guard.pressed.emit()
	check("guard dispatch is bound to published member target and consenting actor",ui.calls.size()==4 and ui.calls[3].kind=="job" and ui.calls[3].target_id=="friend" and ui.calls[3].payload.work_target_id=="guard-target")
	body.free()
	var failed:=checks.filter(func(row:Dictionary):return not row.ok).size()
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(args[0]);var output:=FileAccess.open(args[0]+"/results.json",FileAccess.WRITE)
		output.store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"Public-projection UI boundary tests using real housing proof handler and original command shapes; no live-world, GPU or throughput claim."},"\t",true,true));output.close()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
