extends RefCounted
## Compact actions from the existing public housing/water/life projections.
## Never turn architectural capacity, nearby scenery or a family name into a service.
const C=preload("res://scripts/ui/ui_composition.gd")
const F=preload("res://scripts/ui/factory_projection.gd")
const P=preload("res://scripts/ui/ui_projection.gd")
const Icons=preload("res://scripts/ui/ui_icons.gd")
const Identity=preload("res://scripts/ui/ui_identity.gd")
const Water=preload("res://scripts/ui/factory_water.gd")

static func render(ui,parent:Node,module:Dictionary,definition:Dictionary)->void:
	var family:=str(definition.get("mechanism",{}).get("family",definition.get("architecture",{}).get("family","")))
	var home:bool=family=="home" or definition.get("generation_role")=="home"
	if home:_home(ui,parent,module)
	if home or family=="canteen":_consumables(ui,parent,module)
	for source:Dictionary in linked_water(ui.factory,module):_water(ui,parent,module,source)
	if family=="guard":_guard(ui,parent,module)

static func _card(parent:Node,module:Dictionary,kind:String)->VBoxContainer:
	var body:=C.card(parent)
	body.set_meta("ui_building_life",str(module.get("id","")))
	body.set_meta("ui_building_life_kind",kind)
	return body

static func _home(ui,parent:Node,module:Dictionary)->void:
	var body:=_card(parent,module,"home")
	C.image_row(ui,body,Icons.status_texture("fatigue"),"床位与休息","",roundi(32*ui.text_scale))
	ui.housing_view.read(ui)
	var provider:Dictionary=ui.housing_view.projection
	var home:Dictionary=F.find(F.dictionaries(provider.get("homes",[])),str(module.get("id",""))) if provider.get("available")==true else {}
	if home.is_empty():
		C.caption(ui,"暂无可查看的床位",body);return
	var beds:Array=F.dictionaries(home.get("beds",[])).filter(func(bed:Dictionary):return bed.get("module_id")==module.get("id") and not str(bed.get("bed_id","")).is_empty())
	C.caption(ui,"床位 "+str(beds.size())+" · 可用 "+str(beds.filter(func(bed:Dictionary):return bed.get("available")==true).size()),body)
	if beds.is_empty():return
	var grid:=GridContainer.new();grid.columns=2;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_child(grid)
	var count:int=beds.size() if ui.factory_view.get("life:all-beds:"+str(module.id),false) else mini(4,beds.size())
	for index in count:_bed(ui,grid,module,beds[index],index)
	if beds.size()>4:
		var key:="life:all-beds:"+str(module.id)
		ui.add_button("收起床位" if count==beds.size() else "查看全部 "+str(beds.size())+" 个床位",func():ui.factory_view[key]=not ui.factory_view.get(key,false);ui.queue_refresh(),key,"",body)

static func _bed(ui,parent:Node,module:Dictionary,bed:Dictionary,index:int)->void:
	var body:=C.card(parent);var id:=str(bed.bed_id)
	body.set_meta("ui_building_life_bed",id)
	var title:="床位 "+str(index+1)
	var occupants:PackedStringArray=[]
	var icon:Texture2D=Icons.status_texture("fatigue")
	for actor_id:Variant in bed.get("occupant_ids",[]):
		var actor:Dictionary=P.find(ui.snapshot.get("actors",[]),str(actor_id))
		occupants.append(str(actor.get("name","有人使用")))
		if icon==null or occupants.size()==1:
			var portrait:=Identity.portrait(actor)
			if portrait!=null:icon=portrait
	C.image_row(ui,body,icon,title," · ".join(occupants) if not occupants.is_empty() else "空闲" if bed.get("available")==true else "暂不可用",roundi(30*ui.text_scale))
	var ready:Dictionary=ui.availability(ui.request("rest",id))
	var reason:="" if ready.get("ok",false) and bed.get("available")==true else P.action_feedback(ready,"rest") if not ready.get("ok",false) else P.reason_text(str(bed.get("reason","bed_unavailable")))
	var button:Button=ui.add_button("休息",func():ui.execute("rest",id,{},true),"building-life:rest:"+id,reason,body)
	button.tooltip_text=reason if not reason.is_empty() else "在此床位休息"
	if not reason.is_empty():
		var at:Dictionary=ui.housing_view._approach(bed)
		if bed.get("permitted")==true and bed.get("reachable")==true and not at.is_empty():
			var walk_ready:Dictionary=ui.availability(ui.request("walk","",{},at))
			if walk_ready.get("ok",false):
				ui.add_button("前往床位",func():ui.housing_view.walk_to(ui,str(module.id),id,at),"building-life:bed-walk:"+id,"",body)

static func _consumables(ui,parent:Node,module:Dictionary)->void:
	if not is_instance_valid(ui.runtime) or not ui.runtime.has_method("life_consumables"):return
	var body:=_card(parent,module,"consumables")
	C.heading(ui,"随身补给",body)
	var row:=HBoxContainer.new();body.add_child(row)
	for spec:Array in [["eat","进食","food","随身没有可用食物"],["drink","饮水","water","随身没有可用饮水"]]:
		var kind:=str(spec[0]);var choices:Variant=ui.runtime.call("life_consumables","player",kind)
		var chosen:Dictionary={}
		if choices is Array:
			for choice:Variant in choices:
				if choice is Dictionary and choice.get("kind")==kind and choice.get("item_id") is String and float(choice.get("free",0))>=1:
					chosen=choice;break
		var item:=str(chosen.get("item_id",spec[2]));var payload:Dictionary={"item_id":item}
		var ready:Dictionary=ui.availability(ui.request(kind,"",payload))
		var reason:=str(spec[3]) if chosen.is_empty() else "" if ready.get("ok",false) else P.action_feedback(ready,kind)
		var button:Button=ui.add_button(str(spec[1]),func():ui.execute(kind,"",payload,true),"building-life:consume:"+kind,reason,row)
		Icons.apply_button(button,{"reference":{"kind":"item","item_id":item}})
		button.tooltip_text=reason if not reason.is_empty() else "使用随身的"+str(chosen.get("name",P.item_name(item)))

static func linked_water(factory:Dictionary,module:Dictionary)->Array:
	var proof_ids:Array=[]
	for field:String in ["water_source_id","source_id"]:
		if module.get(field) is String and not str(module[field]).is_empty():proof_ids.append(str(module[field]))
	for member:Variant in module.get("members",[]):
		if member is Dictionary and member.get("id") is String:proof_ids.append(str(member.id))
	var result:Array=[]
	for source:Dictionary in F.rows(factory,"water","sources"):
		if source.get("discovered")!=true or str(source.get("id","")).is_empty():continue
		if proof_ids.has(str(source.id)) or (not str(module.get("id","")).is_empty() and source.get("module_id")==module.id):result.append(source)
	return result

static func _water(ui,parent:Node,module:Dictionary,source:Dictionary)->void:
	var body:=_card(parent,module,"water")
	var id:=str(source.id)
	var allowed:Variant=source.get("allowed_actions",[])
	var state:="待修复" if source.get("status")=="needs_repair" else "可取饮水" if allowed is Array and allowed.has("module.water.draw") else "作业中" if not str(source.get("project_id","")).is_empty() else "暂无可取饮水"
	C.image_row(ui,body,Icons.status_texture("thirst"),"储水装置",state,roundi(32*ui.text_scale))
	if allowed is Array and allowed.has("module.water.draw"):
		var pack:=P.player_stock(ui.snapshot);var payload:Dictionary={"output_id":str(pack.get("id",""))}
		var ready:Dictionary=ui.availability(ui.request("module.water.draw",id,payload))
		var reason:="" if ready.get("ok",false) else P.feedback_text(ready)
		C.primary(ui.add_button("取饮用水",func():ui.execute("module.water.draw",id,payload,true),"building-life:draw:"+id,reason,body))
		Water.approach(ui,body,source)
	ui.add_button("修复储水装置" if source.get("status")=="needs_repair" else "查看储水",func():ui.open_panel("water",id),"building-life:water:"+id,"",body)

static func _guard(ui,parent:Node,module:Dictionary)->void:
	var members:Array=[]
	for member:Variant in module.get("members",[]):
		if member is Dictionary:members.append(str(member.get("id","")))
	var targets:Array=[]
	for target:Dictionary in P.records(ui.snapshot.get("work_targets",[])):
		if target.get("job")=="guard" and members.has(str(target.get("actual_target_id",""))):targets.append(target)
	if targets.is_empty():return
	var body:=_card(parent,module,"guard")
	C.heading(ui,"安排守备",body)
	for actor:Dictionary in P.records(ui.snapshot.get("actors",[])):
		if actor.get("id")=="player" or float(actor.get("hp",0))<=0 or actor.get("relationship",{}).get("member")!=true or actor.get("relationship",{}).get("consent")!=true:continue
		var target:Dictionary=targets[0];var payload:Dictionary={"job":"guard","work_target_id":str(target.id)};var actor_id:=str(actor.id)
		var ready:Dictionary=ui.availability(ui.request("job",actor_id,payload))
		var button:Button=ui.add_button(str(actor.get("name","同伴"))+" · 守备",func():ui.execute("job",actor_id,payload,true),"building-life:guard:"+str(module.id)+":"+actor_id,"" if ready.get("ok",false) else P.feedback_text(ready),body)
		button.icon=Identity.portrait(actor);button.expand_icon=true;button.add_theme_constant_override("icon_max_width",28)
