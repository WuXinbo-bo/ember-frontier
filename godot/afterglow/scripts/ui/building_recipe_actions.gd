extends RefCounted
## Compact recipe picker. Recipes and admission come from existing public owners.
const F=preload("res://scripts/ui/factory_projection.gd")
const P=preload("res://scripts/ui/ui_projection.gd")
const C=preload("res://scripts/ui/ui_composition.gd")
const Icons=preload("res://scripts/ui/ui_icons.gd")
const Ops=preload("res://scripts/ui/factory_operations.gd")
const Panels=preload("res://scripts/ui/ui_panels.gd")
const Handbook=preload("res://scripts/ui/factory_handbook.gd")

static func choices(module:Dictionary,definition:Dictionary,factory:Dictionary,_snapshot:Dictionary={})->Array:
	var result:Array=[]
	# Same exact capability test as Factory.machine_module; a generic machine
	# flag or a recipe belonging to another building must not create an action.
	if definition.get("shape")=="woodshop" and definition.get("recipe_modes",[]).has("machine"):
		for recipe:Dictionary in F.rows(factory,"production","recipes"):
			if recipe.get("mode")!="machine":continue
			result.append({"key":"machine:"+str(recipe.get("id","")),"mode":"machine","target":str(module.get("id","")),"recipe":recipe})
	for recipe:Dictionary in F.dictionaries(module.get("recipe_management",{}).get("recipes",[])):
		var id:=str(recipe.get("id",recipe.get("recipe_id","")))
		if id.is_empty():continue
		result.append({"key":"craft:"+id,"mode":"craft","target":str(module.get("id","")),"recipe":recipe})
	return result

static func icon_entry(recipe:Dictionary)->Dictionary:
	for field:String in ["createTool","repairTool"]:
		if recipe.get(field) is Dictionary:return {"reference":{"kind":"tool"},"definition_id":str(recipe[field].get("kind",""))}
	var outputs:Dictionary=recipe.get("outputs",{})
	if not outputs.is_empty():return {"reference":{"kind":"item","item_id":str(outputs.keys()[0])}}
	return {}

static func title(recipe:Dictionary,snapshot:Dictionary)->String:
	for field:String in ["createTool","repairTool"]:
		if not recipe.get(field) is Dictionary:continue
		var kind:=str(recipe[field].get("kind",""))
		var tool:Dictionary=snapshot.get("catalog",{}).get("tool_definitions",{}).get(kind,{})
		return ("修理" if field=="repairTool" else "制作")+str(tool.get("name","工具"))
	var outputs:Dictionary=recipe.get("outputs",{})
	if not outputs.is_empty():return P.item_name(str(outputs.keys()[0]))+("等" if outputs.size()>1 else "")
	return str(recipe.get("name","制作"))

static func action_title(recipe:Dictionary,snapshot:Dictionary,machine:bool=false)->String:
	if recipe.get("repairTool") is Dictionary:return "开始修理"
	var outputs:Dictionary=recipe.get("outputs",{})
	if outputs.size()==1:
		var item:=str(outputs.keys()[0])
		return ("生产" if machine else "制作")+P.item_name(item)+" × "+P.number(outputs[item])
	return title(recipe,snapshot) if recipe.get("createTool") is Dictionary else "制作这批物品"

static func category(choice:Dictionary)->String:
	var recipe:Dictionary=choice.get("recipe",{})
	if recipe.get("createTool") is Dictionary or recipe.get("repairTool") is Dictionary:return "tools"
	for item:String in recipe.get("outputs",{}):
		if item in ["tool_handle","axe_head","r34:water_bucket"]:return "tools"
		if item in ["food","water","medicine","r34:raw_water","r34:filtered_water","r34:meal_simple","r34:meal_hearty","r34:dry_ration","r34:compost","r34:crop_residue","r34:rice"]:return "life"
	return "woodwork"

static func material_problem(snapshot:Dictionary,recipe:Dictionary)->String:
	var pack:=P.player_stock(snapshot);var missing:PackedStringArray=[]
	for item:String in recipe.get("inputs",{}):
		var need:=float(recipe.inputs[item]);var entry:=P.entry(pack,snapshot,{"kind":"item","item_id":item})
		var have:=float(entry.get("available",0))
		if have+.000001<need:missing.append(P.item_name(item)+" × "+P.number(need-have))
	return "背包缺少："+"、".join(missing) if not missing.is_empty() else ""

static func render(ui,parent:Node,module:Dictionary,definition:Dictionary)->void:
	var recipes:=choices(module,definition,ui.factory,ui.snapshot)
	if recipes.is_empty():return
	C.heading(ui,"可以制作",parent)
	var key:="building-recipe:"+str(module.id)
	var selected:=str(ui.factory_view.get(key,""))
	if not recipes.any(func(row:Dictionary)->bool:return row.key==selected):selected=str(recipes[0].key)
	ui.factory_view[key]=selected
	var group:="woodwork";var groups:Dictionary={}
	for row:Dictionary in recipes:
		var id:=category(row);groups[id]=int(groups.get(id,0))+1
		if row.key==selected:group=id
	if groups.size()>1:
		var tabs:=HBoxContainer.new();parent.add_child(tabs)
		for id:String in ["woodwork","tools","life"]:
			if not groups.has(id):continue
			var first_key:=""
			for row:Dictionary in recipes:
				if category(row)==id:first_key=str(row.key);break
			var tab:Button=ui.add_button(str({"woodwork":"木工","tools":"工具","life":"生活"}[id])+" ("+str(groups[id])+")",func():ui.factory_view[key]=first_key;ui.queue_refresh(),"building:recipe-group:"+str(module.id)+":"+id,"",tabs)
			tab.toggle_mode=true;tab.set_pressed_no_signal(id==group);tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var grid:=GridContainer.new();grid.columns=2;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",8);grid.add_theme_constant_override("v_separation",8);parent.add_child(grid)
	for row:Dictionary in recipes:
		if category(row)!=group:continue
		var recipe:Dictionary=row.recipe
		var name:=title(recipe,ui.snapshot)
		var label:="机器 · " if row.mode=="machine" else "修理 · " if recipe.get("repairTool") is Dictionary else "制作 · "
		if recipe.get("repairTool") is Dictionary or recipe.get("createTool") is Dictionary:label=""
		var button:Button=ui.add_button(label+name,func():ui.factory_view[key]=str(row.key);ui.queue_refresh(),"building:recipe:"+str(module.id)+":"+str(row.key),"",grid)
		button.custom_minimum_size=Vector2(140,64);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode=true;button.set_pressed_no_signal(row.key==selected)
		button.theme_type_variation="PrimaryButton" if row.key==selected else "QuietButton"
		Icons.apply_button(button,icon_entry(recipe));button.add_theme_constant_override("icon_max_width",36)
		button.set_meta("ui_building_recipe",str(row.key));button.set_meta("ui_recipe_id",str(recipe.get("id","")))
		button.tooltip_text=str(recipe.get("name",name))
	var chosen:Dictionary={}
	for row:Dictionary in recipes:
		if row.key==selected:chosen=row;break
	if chosen.is_empty():return
	var panel:=C.card(parent,true);panel.set_meta("ui_building_selected_recipe",selected)
	var recipe:Dictionary=chosen.recipe
	C.heading(ui,title(recipe,ui.snapshot),panel)
	C.production_flow(ui,panel,recipe.get("inputs",{}),recipe.get("outputs",{}),recipe.get("seconds",0))
	if chosen.mode=="machine":_machine(ui,panel,module,chosen)
	else:
		_craft(ui,panel,module,chosen)
		if str(recipe.get("id", "")) == "r34:saw_timber_v2" and module.get("recipe_management", {}).get("recipes", []).has(recipe.id):
			_board_stock(ui, panel, module, recipe)
	_resource_links(ui,panel,module,chosen)

static func _board_stock(ui, parent: Node, module: Dictionary, recipe: Dictionary) -> void:
	var id: String = str(module.id) + ":board-stock"
	var orders: Array = module.get("recipe_management", {}).get("orders", [])
	var running: bool = orders.any(func(order: Dictionary) -> bool: return order.id == id and not order.get("paused", false))
	if running:
		C.caption(ui, "同伴会把作坊出料口补到 4 块板材。", parent)
		ui.add_button("暂停补板", func(): ui.execute("module.recipe.pause", str(module.id), {"order_id":id}), "building:board-stock:pause:"+id, "", parent)
		return
	var payload := {"recipe_id":str(recipe.id),"order_id":id,"mode":"target","target_item":"timber","target_quantity":4}
	ui.add_button("让同伴保持 4 块板材", func(): ui.execute("module.recipe.configure", str(module.id), payload), "building:board-stock:"+id, "", parent)

static func _resource_links(ui,parent:Node,module:Dictionary,chosen:Dictionary)->void:
	var recipe:Dictionary=chosen.recipe
	var inputs:Dictionary=recipe.get("inputs",{})
	var outputs:Dictionary=recipe.get("outputs",{})
	var fuel:=str(recipe.get("fuel_item","")) if chosen.mode=="machine" else ""
	if inputs.is_empty() and outputs.is_empty() and fuel.is_empty():return
	var key:="building-recipe-resources:"+str(module.id)
	var details:=C.fold(ui,parent,key,"原料来源与成品用途")
	if details==null:return
	var links:=HFlowContainer.new();details.add_child(links)
	for item:String in inputs:
		Handbook.shortcut(ui,links,"item:"+item,key+":input:"+item,P.item_name(item)+" · 来源")
	if not fuel.is_empty() and not inputs.has(fuel):
		Handbook.shortcut(ui,links,"item:"+fuel,key+":fuel:"+fuel,P.item_name(fuel)+" · 燃料来源")
	for item:String in outputs:
		Handbook.shortcut(ui,links,"item:"+item,key+":output:"+item,P.item_name(item)+" · 用途")

static func craft_payload(snapshot:Dictionary,recipe:Dictionary,repair_tool_id:String="")->Dictionary:
	var pack:=P.player_stock(snapshot)
	var payload:Dictionary={"recipe_id":str(recipe.get("id",recipe.get("recipe_id",""))),"source_id":str(pack.get("id","")),"output_id":str(pack.get("id","")),"tool_ids":Panels._tool_ids(pack,snapshot,repair_tool_id)}
	if not repair_tool_id.is_empty():payload.repair_tool_id=repair_tool_id
	return payload

static func repair_tools(snapshot:Dictionary,recipe:Dictionary)->Array:
	var rows:Array=[];var kind:=str(recipe.get("repairTool",{}).get("kind",""));var pack:=P.player_stock(snapshot)
	for tool:Dictionary in P.records(snapshot.get("tools",[])):
		if tool.get("kind")!=kind or str(tool.get("holder_id",tool.get("holderId","")))!=str(pack.get("id","")):continue
		var entry:=P.entry(pack,snapshot,{"kind":"tool","tool_id":str(tool.get("id",""))})
		rows.append({"id":str(tool.get("id","")),"name":str(entry.get("name","工具"))+" · 耐久 "+P.number(tool.get("durability",0))})
	return rows

static func _craft(ui,parent:Node,module:Dictionary,chosen:Dictionary)->void:
	var recipe:Dictionary=chosen.recipe
	C.caption(ui,"材料从背包取用，成品放回背包",parent)
	if module.get("state_code")=="needs_restoration" or module.get("status") in ["ruined","dismantled"]:
		C.reason(ui,parent,"先修复建筑，再开始制作");return
	var tool:=""
	if recipe.get("repairTool") is Dictionary:
		var tools:=repair_tools(ui.snapshot,recipe)
		if tools.is_empty():C.reason(ui,parent,"背包里没有可修理的这类工具");return
		tool=Ops._choice(ui,parent,"building-repair:"+str(module.id)+":"+str(recipe.id),"选择工具",tools)
	var payload:=craft_payload(ui.snapshot,recipe,tool)
	# The original far-action gate may only admit walking. Show definite local
	# material shortages before advertising a craft, then retain real admission.
	var reason:=material_problem(ui.snapshot,recipe)
	if reason.is_empty():
		var command:Dictionary=ui.request("craft",str(chosen.target),payload)
		var ready:Dictionary=ui.availability(command)
		reason="" if ready.get("ok",false) else P.action_feedback(ready,"craft")
	C.primary(ui.add_button(action_title(recipe,ui.snapshot),func():ui.execute("craft",str(chosen.target),payload,true),"building:craft:"+str(module.id)+":"+str(recipe.id),reason,parent))

static func _machine(ui,parent:Node,module:Dictionary,chosen:Dictionary)->void:
	var recipe:Dictionary=chosen.recipe
	C.caption(ui,"使用本建筑的原料、燃料和成品箱",parent)
	var fuel:=str(recipe.get("fuel_item",""))
	if not fuel.is_empty():
		var row:=HBoxContainer.new();parent.add_child(row)
		var texture:=Icons.texture({"reference":{"kind":"item","item_id":fuel}})
		if texture!=null:row.add_child(Icons.image(texture,24))
		C.caption(ui,"燃料："+P.item_name(fuel),row)
	var order:=F.find(F.rows(ui.factory,"production","orders"),str(module.id),"module_id")
	if not order.is_empty():
		var status:="已暂停" if order.get("paused",false) else "持续生产" if int(order.get("remaining",0))<0 else "本轮完成" if int(order.get("remaining",0))==0 else "生产中"
		C.caption(ui,status+" · 已完成 "+P.number(order.get("completed",0))+" 批",parent)
		Ops.action(ui,parent,"继续生产" if order.get("paused",false) else "暂停生产","factory.resume" if order.get("paused",false) else "factory.pause",str(module.id))
	var payload:Dictionary={"recipe_id":str(recipe.id),"batches":1}
	var ready:Dictionary=ui.availability(ui.request("factory.configure",str(module.id),payload))
	var reason:="" if ready.get("ok",false) else P.action_feedback(ready,"factory.configure")
	C.primary(ui.add_button(action_title(recipe,ui.snapshot,true),func():ui.execute("factory.configure",str(module.id),payload,true),"building:machine:"+str(module.id)+":"+str(recipe.id),reason,parent))
	if str(module.get("definition_id","")).begins_with("r38.module.") and (order.is_empty() or int(order.get("remaining",0))>=0):
		var continuous:Dictionary={"recipe_id":str(recipe.id),"batches":-1}
		ui.add_button("持续生产",func():ui.execute("factory.configure",str(module.id),continuous,true),"building:machine-repeat:"+str(module.id),reason,parent)
