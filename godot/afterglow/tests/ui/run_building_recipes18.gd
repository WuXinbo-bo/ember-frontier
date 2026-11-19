extends SceneTree
const Recipes=preload("res://scripts/ui/building_recipe_actions.gd")
class Facade extends RefCounted:
	var factory:Dictionary={"production":{"available":true,"recipes":[{"id":"saw_timber","mode":"machine","inputs":{"log":1},"outputs":{"timber":4},"seconds":10,"fuel_item":"log"}],"orders":[]}}
	var snapshot:Dictionary={"player":{"id":"player","stock_id":"pack:player"},"stocks":[{"id":"pack:player","owner":"player","searched":true,"items":{"log":2},"tool_ids":["saw","axe","reserved"]}],"tools":[{"id":"saw","kind":"hand_saw","holderId":"pack:player","durability":10},{"id":"axe","kind":"salvaged_axe","holderId":"pack:player","durability":0},{"id":"reserved","kind":"hammer","holderId":"pack:player","durability":10,"reserved":true},{"id":"far","kind":"salvaged_axe","holderId":"elsewhere","durability":1}],"catalog":{"tool_definitions":{"hand_saw":{"name":"锯子"},"salvaged_axe":{"name":"斧头"},"hammer":{"name":"锤子"}}}}
	var factory_view:Dictionary={}
	var text_scale:float=1.0
	var carry:Dictionary={}
	var handbook_jumps:Array[String]=[]
	var probes:Array=[]
	var calls:Array=[]
	var ready:bool=true
	var refreshes:int=0
	func paragraph(text:String,parent:Node)->Label:
		var node:=Label.new();node.text=text;parent.add_child(node);return node
	func add_button(text:String,callback:Callable,key:String,reason:String,parent:Node)->Button:
		var node:=Button.new();node.text=text;node.disabled=not reason.is_empty();node.tooltip_text=reason;node.set_meta("key",key);node.pressed.connect(callback);parent.add_child(node);return node
	func request(kind:String,target:String,payload:Dictionary={})->Dictionary:return {"kind":kind,"target_id":target,"payload":payload}
	func availability(command:Dictionary)->Dictionary:
		probes.append(command.duplicate(true));return {"ok":ready,"code":"OK" if ready else "NO_TOOL","reason":null if ready else "缺少可用锯子"}
	func execute(kind:String,target:String,payload:Dictionary={},resume:bool=false)->Dictionary:
		calls.append({"kind":kind,"target":target,"payload":payload.duplicate(true),"resume":resume});return {"ok":true}
	func queue_refresh()->void:refreshes+=1
	func open_handbook(id:String)->void:handbook_jumps.append(id)

var checks:Array=[]
var recipe:Dictionary={"id":"make-boards","name":"锯木板","inputs":{"log":1},"outputs":{"timber":4},"seconds":10}
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool)->void:checks.append({"name":name,"ok":ok})
func buttons(node:Node,prefix:String)->Array:
	var result:Array=[]
	for child:Node in node.get_children():
		if child is Button and str(child.get_meta("key","")).begins_with(prefix):result.append(child)
		result.append_array(buttons(child,prefix))
	return result
func selected_count(node:Node)->int:
	var count:int=1 if node.has_meta("ui_building_selected_recipe") else 0
	for child:Node in node.get_children():count+=selected_count(child)
	return count
func run()->void:
	var ui:=Facade.new();var module:Dictionary={"id":"workshop","status":"operational","recipe_management":{"recipes":[recipe.duplicate(true)]}}
	var definition:Dictionary={"shape":"workshop","recipe_modes":["manual","labor"]}
	var source:Dictionary=module.duplicate(true)
	var choices:Array=Recipes.choices(module,definition,ui.factory,ui.snapshot)
	check("manual building shows only its published module recipes",choices.size()==1 and choices[0].recipe.id==recipe.id and choices[0].mode=="craft")
	check("recipe lookup does not modify source DTO",module==source)
	check("storage building cannot inherit global machine recipes",Recipes.choices({"id":"store"},{"shape":"warehouse","recipe_modes":[]},ui.factory,ui.snapshot).is_empty())
	check("machine flag without correct building capability does not expose machine action",Recipes.choices({"id":"other"},{"shape":"workshop","recipe_modes":["machine"]},ui.factory,ui.snapshot).is_empty())
	var machines:Array=Recipes.choices({"id":"sawmill"},{"shape":"woodshop","recipe_modes":["machine"]},ui.factory,ui.snapshot)
	check("actual woodshop machine capability exposes exact production recipe",machines.size()==1 and machines[0].target=="sawmill" and machines[0].recipe.id=="saw_timber")
	var body:=VBoxContainer.new();Recipes.render(ui,body,module,definition)
	var sources:=buttons(body,"fold:building-recipe-resources:")
	check("resource help starts collapsed alongside the direct action",sources.size()==1 and buttons(body,"factory:handbook:link:").is_empty())
	if not sources.is_empty():sources[0].pressed.emit()
	body.free();body=VBoxContainer.new();ui.probes.clear()
	Recipes.render(ui,body,module,definition)
	var links:=buttons(body,"factory:handbook:link:building-recipe-resources:")
	for link:Button in links:link.pressed.emit()
	check("source and use links target real item handbook entries without executing work",ui.handbook_jumps==["item:log","item:timber"] and ui.calls.is_empty())
	check("default building page exposes recipe icon choices",buttons(body,"building:recipe:").size()==1)
	check("only selected recipe expands its settings",selected_count(body)==1)
	check("one selected recipe requires one admission probe",ui.probes.size()==1)
	var craft:Array=buttons(body,"building:craft:")
	check("manual recipe has direct one-batch action",craft.size()==1 and not craft[0].disabled)
	if not craft.is_empty():craft[0].pressed.emit()
	check("manual action submits original craft to actual module",ui.calls.size()==1 and ui.calls[0].kind=="craft" and ui.calls[0].target=="workshop")
	check("manual action resumes real work without another UI confirmation",ui.calls.size()==1 and ui.calls[0].resume)
	check("manual materials and outputs reference actual backpack",ui.calls.size()==1 and ui.calls[0].payload.source_id=="pack:player" and ui.calls[0].payload.output_id=="pack:player")
	check("reserved tools excluded from craft payload",ui.calls.size()==1 and not ui.calls[0].payload.tool_ids.has("reserved"))
	body.free();body=VBoxContainer.new();ui.snapshot.stocks[0].items.log=0;ui.probes.clear()
	Recipes.render(ui,body,module,definition);craft=buttons(body,"building:craft:")
	check("visible material shortage disables craft even if walk admission would pass",craft.size()==1 and craft[0].disabled and craft[0].tooltip_text.contains("缺少") and ui.probes.is_empty())
	ui.snapshot.stocks[0].items.log=2
	body.free();body=VBoxContainer.new();ui.ready=false;ui.probes.clear()
	Recipes.render(ui,body,module,definition);craft=buttons(body,"building:craft:")
	check("authority refusal keeps direct craft disabled",craft.size()==1 and craft[0].disabled and craft[0].tooltip_text.contains("锯子"))
	body.free();body=VBoxContainer.new();ui.ready=true;ui.probes.clear();module.state_code="needs_restoration"
	Recipes.render(ui,body,module,definition)
	check("unrestored building exposes no runnable crafting action",buttons(body,"building:craft:").is_empty() and ui.probes.is_empty())
	module.erase("state_code");var repair:Dictionary={"id":"repair-axe","name":"维修斧头","inputs":{"scrap":1},"outputs":{},"seconds":10,"repairTool":{"kind":"salvaged_axe"}}
	var repairable:Array=Recipes.repair_tools(ui.snapshot,repair)
	check("repair picker uses actual matching held tool only",repairable.size()==1 and repairable[0].id=="axe")
	var repair_payload:=Recipes.craft_payload(ui.snapshot,repair,"axe")
	check("repair target is not also allocated as the working tool",repair_payload.repair_tool_id=="axe" and not repair_payload.tool_ids.has("axe") and repair_payload.tool_ids.has("saw"))
	check("repair picker icon identifies real tool kind",Recipes.icon_entry(repair).definition_id=="salvaged_axe")
	body.free();body=VBoxContainer.new();ui.factory_view.clear();ui.calls.clear();ui.probes.clear()
	Recipes.render(ui,body,{"id":"sawmill","status":"operational"},{"shape":"woodshop","recipe_modes":["machine"]})
	var start:Array=buttons(body,"building:machine:")
	check("machine page offers production action",start.size()==1 and not start[0].disabled)
	if not start.is_empty():start[0].pressed.emit()
	check("machine action uses original configure and exact batch count",ui.calls.size()==1 and ui.calls[0].kind=="factory.configure" and ui.calls[0].target=="sawmill" and ui.calls[0].payload=={"recipe_id":"saw_timber","batches":1})
	body.free();body=VBoxContainer.new();ui.probes.clear();ui.factory_view={"building-recipe:workshop":"craft:deleted"}
	module.recipe_management.recipes.append({"id":"braces","inputs":{"timber":2},"outputs":{"brace":1},"seconds":12})
	Recipes.render(ui,body,module,definition)
	check("stale recipe preference falls back to current published recipe",ui.factory_view["building-recipe:workshop"]=="craft:make-boards")
	check("multiple choices still run one selected admission check",buttons(body,"building:recipe:").size()==2 and ui.probes.size()==1 and selected_count(body)==1)
	var picks:Array=buttons(body,"building:recipe:")
	if picks.size()==2:picks[1].pressed.emit()
	check("recipe selection updates view preference only",ui.factory_view["building-recipe:workshop"]=="craft:braces" and ui.refreshes>0)
	check("tool repair and safe-water recipes have distinct groups",Recipes.category({"recipe":repair})=="tools" and Recipes.category({"recipe":{"outputs":{"water":2}}})=="life" and Recipes.category({"recipe":recipe})=="woodwork")
	body.free()
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(args[0]);var file:=FileAccess.open(args[0]+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"UI facade tests of published recipe filtering, compact controls and unchanged command payloads. Does not claim physical-world, GPU or runtime authority integration coverage."},"\t",true,true));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
