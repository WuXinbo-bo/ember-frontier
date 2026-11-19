extends "res://tests/buildings/suffix_exit_probe.gd"
const Candidate=preload("res://tests/buildings/navigation_template_candidate.gd")
class TemplateSpace extends "res://scripts/buildings/building_space.gd":
	var route_templates:Dictionary={}
	var template_hits:=0
	func route(id:String,from:Dictionary,to:Dictionary)->Dictionary:
		return Candidate.new().plan(self,id,from,to)
class TemplateBuilding extends "res://scripts/buildings/building_service.gd":
	var metrics:Dictionary={"template_hits":0}
	func space(view:RefCounted=null,proposed:Dictionary={},staged:Dictionary={})->RefCounted:
		var w:RefCounted=context.world if view==null else view
		var data:Dictionary=structures(w) if proposed.is_empty() else proposed
		var query:=TemplateSpace.new();var owner_ref:WeakRef=weakref(self)
		query.configure(w,data,geometry,func(a:String,t:String,k:String,p:Dictionary)->Variant:return owner_ref.get_ref().permission(a,t,k,p,staged) if owner_ref.get_ref()!=null else "closed")
		return query
	func validation_space(view:RefCounted,data:Dictionary,staged:Dictionary)->RefCounted:
		var q:RefCounted=super.validation_space(view,data,staged)
		if q is TemplateSpace:return q
		var replaced:=TemplateSpace.new()
		for property:Dictionary in q.get_script().get_script_property_list():
			if property.name in ["script"]:continue
			replaced.set(property.name,q.get(property.name))
		_validation_space=replaced
		return replaced
	func exit_reachable(q:RefCounted,id:String,from:Dictionary,to:Dictionary)->bool:
		var before:int=q.template_hits
		var result:bool=super.exit_reachable(q,id,from,to)
		metrics.template_hits+=q.template_hits-before
		return result

func configure_case(imported:Dictionary,side:int,reference:bool)->Dictionary:
	var w:=World.new();w.load_snapshot(imported.world)
	var b:RefCounted=Building.new() if reference else TemplateBuilding.new();last_model=b
	var r:=Runtime.new();var services:Dictionary={"buildings":b,"actions":Actions.new(),"production":Production.new()}
	var configured:Dictionary=r.configure({"world":w,"facts":imported.facts,"services":services})
	expect("same actual baseline runtime configures",configured.ok,configured)
	var fixture:RefCounted=b.space();var door:Dictionary=fixture.by_id[DOOR]
	var stance:Dictionary=fixture.standing_point(fixture.use_points(door)[side]);var f:=r.facts()
	for a:Dictionary in f.actors:
		if a.id=="player":a.merge(stance,true);a.intent=null
	configured=r.configure({"world":w,"facts":f,"services":services})
	expect("same explicit supported stance and five original actors",not stance.is_empty() and configured.ok and r.facts().actors.size()==5)
	return {"world":w,"building":b,"runtime":r,"services":services,"fixture":fixture}
