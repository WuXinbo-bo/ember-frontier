extends RefCounted
## Immutable generation geometry lock, not a mutable second module catalogue.
const Data=preload("res://scripts/world/world_data.gd")
const Landscape=preload("res://scripts/world/factory_landscape.gd")
const SCHEMA="afterglow-factory-generation-v1"
const EXTENSION="generation:factory-r34"
const GEOMETRY_KEYS=["id","version","geometry_version","category","generation_role","footprint","foundation","ports","allowed_quarter_turns","visual_family","design_id"]

static func digest(value:Variant)->String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)),"",true,true).sha256_text()

static func geometry_profiles(catalog:Array)->Dictionary:
	var rows:Array=[];var seen:Dictionary={}
	for source:Variant in catalog:
		if not source is Dictionary or not Data.json_value(source) or not Data.valid_id(source.get("id")) or seen.has(source.id):return Data.reject("INVALID_MODULE_PROFILE_ID")
		seen[source.id]=true
		var row:Dictionary={}
		for key:String in GEOMETRY_KEYS:
			if source.has(key):row[key]=source[key].duplicate(true) if source[key] is Array or source[key] is Dictionary else source[key]
		if not Data.integer(row.get("version")) or row.version<1 or not Data.valid_id(row.get("geometry_version")):return Data.reject("INVALID_MODULE_PROFILE_VERSION",source.id)
		if row.has("visual_family") or row.has("design_id"):
			if row.get("visual_family") not in ["warehouse","home","roadside"] or not Data.valid_id(row.get("design_id")):return Data.reject("INVALID_MODULE_PROFILE_DESIGN",source.id)
		var f:Variant=row.get("footprint")
		if not f is Dictionary or not f.get("min") is Dictionary or not f.get("max") is Dictionary:return Data.reject("INVALID_MODULE_FOOTPRINT",source.id)
		var r:Array=[f.min.get("x"),f.min.get("z"),f.max.get("x"),f.max.get("z")]
		if not rect_valid(r):return Data.reject("INVALID_MODULE_FOOTPRINT",source.id)
		var foundation:Variant=row.get("foundation")
		if not foundation is Dictionary or foundation.get("top_offset",0)!=0 or not foundation.get("pad_rectangles",[]) is Array:return Data.reject("INVALID_MODULE_FOUNDATION",source.id)
		for pad:Variant in foundation.get("pad_rectangles",[]):
			if not rect_valid(pad):return Data.reject("INVALID_MODULE_FOUNDATION",source.id)
		if not row.get("allowed_quarter_turns",[0]) is Array or not row.get("allowed_quarter_turns",[0]).any(func(v:Variant)->bool:return Data.integer(v) and v==0):return Data.reject("UNSUPPORTED_MODULE_ORIENTATION",source.id)
		if not row.get("ports") is Array or row.ports.is_empty():return Data.reject("MISSING_MODULE_SERVICE_PORT",source.id)
		var port_ids:Dictionary={}
		for p:Variant in row.ports:
			if not p is Dictionary or not Data.valid_id(p.get("id")) or port_ids.has(p.id) or not vector_valid(p.get("position")):return Data.reject("INVALID_MODULE_SERVICE_PORT",source.id)
			port_ids[p.id]=true
			if p.position[1]!=0 or p.get("direction") not in ["north","south","west","east"] or not p.get("purpose") is String:return Data.reject("UNSUPPORTED_MODULE_SERVICE_PORT",source.id)
			if not p.get("use_points") is Array or p.use_points.is_empty() or not p.get("clearance") is Dictionary:return Data.reject("INVALID_MODULE_SERVICE_CLEARANCE",source.id)
			for use:Variant in p.use_points:
				if not vector_valid(use) or use[1]!=0:return Data.reject("UNSUPPORTED_MODULE_USE_POINT",source.id)
			var radius:Variant=p.clearance.get("radius");var height:Variant=p.clearance.get("height")
			if not (radius is int or radius is float) or not (height is int or height is float) or not is_finite(float(radius)) or not is_finite(float(height)) or radius<0.26 or radius>2.0 or height<1.8 or height>4.0:return Data.reject("INVALID_MODULE_SERVICE_CLEARANCE",source.id)
		rows.append(row)
	rows.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.id<b.id)
	return {"ok":true,"profiles":rows,"profile_sha256":digest(rows)}

static func vector_valid(v:Variant)->bool:
	return v is Array and v.size()==3 and v.all(func(n:Variant)->bool:return (n is int or n is float) and is_finite(float(n)) and absf(float(n))<=28.0)

static func rect_valid(r:Variant)->bool:
	return r is Array and r.size()==4 and r.all(func(n:Variant)->bool:return (n is int or n is float) and is_finite(float(n)) and absf(float(n))<=28.0) and r[0]<r[2] and r[1]<r[3] and r[2]-r[0]<=24 and r[3]-r[1]<=24

static func fresh(catalog:Array,content_version:int=2,story_clue_version:int=0)->Dictionary:
	if content_version not in [1,2,3,4,5,6]:return Data.reject("UNSUPPORTED_FACTORY_CONTENT_VERSION")
	if story_clue_version not in [0,1] or (story_clue_version==1 and content_version<3):return Data.reject("UNSUPPORTED_FACTORY_STORY_CLUE_VERSION")
	var input:Dictionary=geometry_profiles(catalog)
	if not input.ok:return input
	if content_version>=4:
		for profile:Dictionary in input.profiles:
			var seen:Dictionary={}
			for turn:Variant in profile.get("allowed_quarter_turns",[0]):
				if not Data.integer(turn) or int(turn) not in [0,1,2,3] or seen.has(int(turn)):return Data.reject("UNSUPPORTED_MODULE_ORIENTATION",profile.id)
				seen[int(turn)]=true
			for port:Dictionary in profile.ports:
				var normal:Variant=port.get("normal")
				var expected:Array={"north":[0,0,-1],"east":[1,0,0],"south":[0,0,1],"west":[-1,0,0]}[port.direction]
				if not vector_valid(normal) or normal[0]!=expected[0] or normal[1]!=expected[1] or normal[2]!=expected[2]:return Data.reject("INVALID_MODULE_SERVICE_NORMAL",profile.id+":"+str(port.id))
	var contract:Dictionary={"schema":SCHEMA,"version":1,"scenario":Landscape.SCENARIO,"generator_version":Landscape.VERSION,"terrain_algorithm":"site-relief-v8","stream_version":1,"max_regions":Landscape.MAX_REGIONS,"coord_limit":Landscape.COORD_LIMIT,"profile_sha256":input.profile_sha256,"profile_input":input.profiles.duplicate(true)}
	# Historical v1 had no field; keep that exact shape/hash on recovery.
	if content_version>=2:contract.content_version=content_version
	# Only explicit v4 new worlds adopt road/court-facing complete parcels.
	# Missing/changed policy on a saved v4 lock is rejected by resolve.
	if content_version>=4:contract.parcel_orientation="road-court-v1"
	# Only explicit MT01 new worlds adopt the finite recovery source policy.
	# resolve compares the complete pinned shape; old locks stay byte-identical.
	if content_version>=5:contract.tool_recovery_policy="mt01-v1"
	if content_version==6:contract.water_recovery_policy="wt01-v1"
	# Opt in only for explicit new worlds. Missing keeps every existing
	# content1/2/3 lock, explored plan and unexplored selection unchanged.
	if story_clue_version==1:contract.story_clue_version=story_clue_version
	return {"ok":true,"profiles":input.profiles,"contract":contract}

static func resolve(configuration:Variant,catalog:Array)->Dictionary:
	if not configuration is Dictionary or not Data.json_value(configuration):return Data.reject("INVALID_FACTORY_GENERATION_CONTRACT")
	var content:Variant=configuration.get("content_version",1)
	if not Data.integer(content):return Data.reject("UNSUPPORTED_FACTORY_CONTENT_VERSION")
	var story:Variant=configuration.get("story_clue_version",0)
	if not Data.integer(story):return Data.reject("UNSUPPORTED_FACTORY_STORY_CLUE_VERSION")
	var pinned:Dictionary=fresh(configuration.get("profile_input",[]),int(content),int(story))
	if not pinned.ok or not Data.json_equal(configuration,pinned.contract):return Data.reject("FACTORY_GENERATION_POLICY_MISMATCH")
	var current:Dictionary=geometry_profiles(catalog)
	if not current.ok:return current
	# Additive definitions cannot invalidate an old lock. Every saved ID must
	# still resolve to precisely its pinned geometry/ports/selection metadata;
	# unexplored regions continue using only that saved input, never new IDs.
	var by_id:Dictionary={}
	for row:Dictionary in current.profiles:by_id[row.id]=row
	for row:Dictionary in pinned.profiles:
		if not by_id.has(row.id) or not Data.json_equal(row,by_id[row.id]):return Data.reject("MODULE_PROFILE_VERSION_MISMATCH",row.id)
	return {"ok":true,"profiles":pinned.profiles,"contract":configuration.duplicate(true)}
