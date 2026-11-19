extends RefCounted
## Versioned content12 porch attachment, installed explicitly on existing saves.
## It adds an unprepared bed, never stock, paid cloth, people or a second clock.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Housing=preload("res://scripts/modules/module_housing.gd")
const KEY="r34:modules"
static func key(v:Dictionary)->String:return str(v.source_key)+":opening-bed-attachment:v1"
static func receipt(v:Dictionary)->Dictionary:
	return {"source_key":key(v),"module_id":v.id,"stock_ids":[],"attachment_version":1,"geometry_id":"opening-porch:v1","home_source_key":v.source_key}
static func eligible(view:RefCounted,v:Dictionary,d:Dictionary)->bool:
	var config_fields:Array[String]=["content_version"];var seed_fields:Array[String]=["module_seeds"]
	var generation:Variant=view.extension_fields("generation:factory-r34",config_fields)
	if not generation is Dictionary or generation.get("content_version")!=12 or v.get("player_built",true) or v.get("region")!="RH-HOME" or d.id not in ["r34.module.home_roadside_v3","r34.module.home_court_v3"]:return false
	var plan:Variant=view.extension_fields("generation:"+str(v.region),seed_fields)
	if not plan is Dictionary:return false
	return plan.get("module_seeds",[]).any(func(s:Dictionary)->bool:return s.get("purpose")=="home" and s.id==v.id and s.source_key==v.source_key and s.definition_id==d.id and s.geometry_version==v.geometry_version and Data.json_equal(s.position,v.position) and s.quarter_turn==v.quarter_turn)
static func validate(view:RefCounted,state:Dictionary,v:Dictionary,d:Dictionary)->Dictionary:
	if not v.get("config",{}) is Dictionary:return Data.reject("INVALID_MODULE_CONFIG")
	if not v.config.has("opening_bed_v1"):return {"ok":true}
	if not Data.integer(v.config.opening_bed_v1) or v.config.opening_bed_v1!=1 or not eligible(view,v,d) or not Data.json_equal(state.source_receipts.get(key(v)),receipt(v)):return Data.reject("INVALID_OPENING_BED_ATTACHMENT")
	return {"ok":true}
static func prepare(host:RefCounted,request:Dictionary)->Dictionary:
	var tx:=Draft.new(host.context);var a:Dictionary=tx.actor(str(request.get("actor_id","")))
	var state:Dictionary=tx.extension(KEY,host.initial());var v:=Draft.find(state.instances,str(request.get("target_id","")))
	if a.is_empty() or float(a.get("hp",0))<=0 or not host.permitted(a,v.get("owner")):return Data.reject("MODULE_PERMISSION")
	if a.get("intent")!=null:return Data.reject("ACTOR_BUSY")
	if v.is_empty():return Data.reject("MODULE_NOT_FOUND")
	var d:=Catalog.definition_view(str(v.definition_id))
	if not eligible(host.context.world,v,d):return Data.reject("OPENING_BED_CONTENT_MISMATCH")
	if state.source_receipts.has(key(v)) or v.config.has("opening_bed_v1"):return Data.reject("OPENING_BED_ALREADY_INSTALLED")
	if not v.get("discovered",false) or v.status!="operational" or float(v.hp)!=float(d.hp):return Data.reject("MODULE_NOT_OPERATIONAL")
	if host.context.get("region_is_detailed") is Callable and not host.context.region_is_detailed.call(str(v.region)):return Data.reject("REGION_PAUSED")
	var at:=G.location(a);var query:RefCounted=host.context.spatial.current_space();var reachable:=false
	for port:Dictionary in Shape.ports(v,d):
		for p:Dictionary in port.use_points:
			if G.point(at).distance_to(G.point(p))<=.9 and query.contact_clear(at,port.location,str(v.id)):reachable=true
	if not reachable:return Data.reject("OPENING_BED_REQUIRES_CONTACT")
	v.config.opening_bed_v1=1;state.source_receipts[key(v)]=receipt(v)
	var expected:Dictionary={}
	for e:Dictionary in Shape.entities(v,d):
		expected[e.id]=true
		var old:Dictionary=host.context.world.entity(str(e.id));var before:Dictionary=old.duplicate(true);var after:Dictionary=e.duplicate(true)
		before.erase("revision");after.erase("revision")
		if Data.json_equal(before,after):continue
		if old.is_empty() and host.context.world.retired_entity_ids().has(e.id):return Data.reject("OPENING_BED_MEMBER_RETIRED")
		e.revision=int(old.get("revision",-1))+1
		tx.extra.append({"op":"entity.put","id":e.id,"before_exists":not old.is_empty(),"before":null if old.is_empty() else old,"after":e})
		if Draft.find(v.members,str(e.id)).is_empty():v.members.append({"id":e.id,"kind":"entity"})
	for member:Dictionary in v.members.duplicate():
		if not str(member.id).begins_with(str(v.id)+":part:road-entry-porch:") or expected.has(member.id):continue
		var old:Dictionary=host.context.world.entity(str(member.id))
		if not old.is_empty():tx.extra.append({"op":"entity.remove","id":member.id,"before_exists":true,"before":old,"after":null})
		v.members.erase(member)
	var result:Dictionary=tx.result();var projected:Dictionary=host.context.world.prepare_changes(result.world_changes,host.context.world.get_revision())
	if not projected.ok:return projected
	var safe:Dictionary=host.context.spatial.validate_world_draft(projected.view,tx.staged,result.world_changes)
	if not safe.ok:return safe
	result.events.append({"kind":"opening-bed-attachment-installed","actor_id":a.id,"module_id":v.id,"attachment_version":1})
	return result
