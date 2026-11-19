extends SceneTree
const Access18=preload("res://scripts/ui/factory_service_access.gd")
const UI18=preload("res://scripts/ui/game_ui.gd")
const Water18=preload("res://scripts/ui/factory_water.gd")
const P18=preload("res://scripts/ui/ui_projection.gd")
class FacadeUI extends RefCounted:
	var runtime:Variant=null
	var factory:Dictionary={"world_id":"probe","modules":{"available":true,"instances":[{"id":"building","stock_refs":{"tools":"stock"}}]}}
	var snapshot:Dictionary={"player":{"id":"player","intent":null}}
	var factory_view:Dictionary={}
	var provider:Dictionary={"available":true,"module_id":"building","approaches":[{"id":"tools","stock_ref":"stock","label":"工具","available":true,"at_service":false,"command":{"kind":"walk","target_id":"","payload":{},"destination":{"regionId":"known","x":1,"y":0,"z":2}}}]}
	var calls:Array=[]
	var notices:Array=[]
	var ready:bool=true
	func request(kind:String,id:String,payload:Dictionary={},destination:Dictionary={})->Dictionary:return {"kind":kind,"target_id":id,"payload":payload,"destination":destination}
	func availability(_command:Dictionary)->Dictionary:return {"ok":ready,"code":"FORBIDDEN" if not ready else "OK"}
	func paragraph(text:String,parent:Node)->Label:
		var label:=Label.new();label.text=text;parent.add_child(label);return label
	func add_button(text:String,callback:Callable,key:String,reason:String,parent:Node)->Button:
		var button:=Button.new();button.text=text;button.disabled=not reason.is_empty();button.set_meta("key",key);button.pressed.connect(callback);parent.add_child(button);return button
	func read_service_approaches(_id:String,_force:bool=false)->Dictionary:return provider.duplicate(true)
	func execute(kind:String,id:String,payload:Dictionary={},resume:bool=false,worker:String="",destination:Dictionary={})->Dictionary:
		calls.append({"kind":kind,"target":id,"payload":payload,"resume":resume,"worker":worker,"destination":destination});return {"ok":true}
	func notify(text:String,_failure:bool=false)->void:notices.append(text)
	func queue_refresh()->void:pass
class WaterOwner extends RefCounted:
	var row:Dictionary={}
	func water_snapshot(_actor:String,_id:String)->Dictionary:return {"available":true,"sources":[row.duplicate(true)]}

var checks:Array=[]
func check(name:String,ok:bool)->void:checks.append({"name":name,"ok":ok})
func _initialize()->void:call_deferred("run")
func button(parent:Node)->Button:
	for child:Node in parent.get_children():
		if child is Button:return child
	return null
func run()->void:
	var facade:=FacadeUI.new();var body:=VBoxContainer.new()
	var module:Dictionary=facade.factory.modules.instances[0]
	Access18.nearby(facade,body,module,facade.provider)
	var walk:Button=button(body)
	check("far known building exposes one-click public approach",walk!=null and not walk.disabled)
	if walk!=null:walk.pressed.emit()
	check("approach submits original walk only",facade.calls.size()==1 and facade.calls[0].kind=="walk" and facade.calls[0].destination==facade.provider.approaches[0].command.destination)
	facade.provider.approaches[0].command.destination.x=3
	if walk!=null:walk.pressed.emit()
	check("click rejects changed proof without substituting a destination",facade.calls.size()==1)
	body.free();body=VBoxContainer.new();facade.provider.approaches[0].at_service=true
	Access18.nearby(facade,body,module,facade.provider)
	check("nearby building does not demand a special approach point",button(body)==null)
	Access18.guide(facade,body,module,"stock",facade.provider,false)
	var search:Button=button(body)
	check("nearby unknown cache offers original search",search!=null and not search.disabled)
	if search!=null:search.pressed.emit()
	check("nearby search targets exact stock through existing action",facade.calls.size()==2 and facade.calls[1].kind=="search" and facade.calls[1].target=="stock")
	body.free();body=VBoxContainer.new();facade.ready=false
	Access18.guide(facade,body,module,"stock",facade.provider,false)
	check("original authority refusal keeps nearby action disabled",button(body)!=null and button(body).disabled)
	body.free();body=VBoxContainer.new();facade.provider.approaches[0].at_service=false
	Access18.nearby(facade,body,module,facade.provider)
	check("rejected walk is never advertised as available",button(body)==null)
	check("distance explanations request proximity without a fixed port",not P18.reason_text("MODULE_DISCOVER_REQUIRES_CONTACT").contains("口") and P18.reason_text("operator_not_at_water").contains("距离"))
	body.free()
	body=VBoxContainer.new();facade.ready=true
	var water_owner:=WaterOwner.new();water_owner.row={"id":"water","discovered":true,"approach":facade.provider.approaches[0].command.duplicate(true)};facade.runtime=water_owner
	Water18.approach(facade,body,water_owner.row)
	var water_walk:Button=button(body)
	check("published water approach creates one-click walk",water_walk!=null)
	if water_walk!=null:water_walk.pressed.emit()
	check("water approach only walks, never draws or changes stock",facade.calls.size()==3 and facade.calls[2].kind=="walk")
	water_owner.row.approach.destination.z=7
	if water_walk!=null:water_walk.pressed.emit()
	check("water click refreshes public proof and rejects changed destination",facade.calls.size()==3)
	body.free()
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(args[0]);var out:=FileAccess.open(args[0]+"/results.json",FileAccess.WRITE)
		out.store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"Headless UI facade boundary probes, public approach proof and unchanged command targets; no actual world proximity/GPU claim."},"\t",true,true));out.close()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
