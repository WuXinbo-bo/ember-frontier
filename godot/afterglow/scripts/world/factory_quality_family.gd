extends RefCounted
## Explicit content9 selection policy, not another module catalogue/permission.
const POLICY="three-families-quality-v1"
const WORKYARD_POLICY="empty-workyard-advice-v1"
const IDS={
	"home":["r34.module.home_court_v3","r34.module.home_roadside_v3"],
	"storage":["r34.module.warehouse_court_v3","r34.module.warehouse_long_v3"],
	"machine":["r34.module.woodshop_long_v3","r34.module.woodshop_yard_v3"]}

static func is_quality(id:String)->bool:
	for family:Array in IDS.values():
		if id in family:return true
	return false

static func validate(profiles:Array)->Dictionary:
	var summary:Dictionary={}
	for family:String in IDS:
		var rows:Array=[]
		for id:String in IDS[family]:
			var matching:Array=profiles.filter(func(p:Dictionary)->bool:return p.id==id)
			if matching.size()!=1:return {"ok":false,"code":"MISSING_QUALITY_FAMILY_PROFILE","reason":id}
			var p:Dictionary=matching[0]
			if p.get("generation_role")!=family or p.geometry_version!=id+".geometry-v2":return {"ok":false,"code":"QUALITY_FAMILY_PROFILE_MISMATCH","reason":id}
			rows.append({"definition_id":id,"definition_version":p.version,"geometry_version":p.geometry_version})
		summary[family]=rows
	return {"ok":true,"summary":summary}

static func candidates(profiles:Array,role:String)->Array:
	return profiles.filter(func(p:Dictionary)->bool:return p.id in IDS.get(role,[]))

static func workyard(parcel:Dictionary,profiles:Array)->Dictionary:
	# Both approved machine variants have the same footprint/services. Each
	# descriptor still carries its own immutable definition/geometry identity.
	var choices:Array=[]
	for profile:Dictionary in candidates(profiles,"machine"):
		choices.append({"definition_id":profile.id,"definition_version":profile.version,"geometry_version":profile.geometry_version,"position":parcel.origin.duplicate(true),"quarter_turn":parcel.quarter_turn})
	return {"id":parcel.id,"policy":WORKYARD_POLICY,"status":"unbuilt-space-suggestion","position":parcel.origin.duplicate(true),"quarter_turn":parcel.quarter_turn,"pad":parcel.pad.duplicate(true),"service_points":parcel.entrance_ports.duplicate(true),"candidate_definitions":choices,"access_path_ids":parcel.entrance_ports.map(func(p:Dictionary)->String:return "access:"+str(parcel.id)+":"+str(p.id)),"semantics":"No module, stock, tools, task, ownership or permanent reservation. B must recheck live terrain, bodies, tools, materials and permissions at preview/plan/work."}
