extends RefCounted
## A saved mapgen input, not a second world or a mutable building catalogue.
const Data=preload("res://scripts/world/world_data.gd")
const BoundedLayout=preload("res://scripts/world/bounded_layout.gd")
const ORIGINAL_IDS=["homestead_l","homestead_wing","shed_lean","shed_through","shop_front","repair_court"]
const RESIDENTIAL_IDS=["homestead_l","homestead_wing","homestead_compact","homestead_courtyard"]
const PIN_FIELDS=["profile_ids","residential_selection","profile_input_sha256","landscape_model","dressing_contract_sha256","layout_policy"]

static func stamp(profiles:Array,complete:bool=false)->String:
	var rows:Array=[]
	var keys:Array=["id","version","footprint","foundation","entrance_ports","use_reservations"]
	if complete:keys.append_array(["npc_anchors","allowed_quarter_turns"])
	for profile:Dictionary in profiles:
		var row:Dictionary={}
		for key:String in keys:row[key]=profile.get(key)
		rows.append(row)
	rows.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return str(a.id)<str(b.id))
	return JSON.stringify(JSON.parse_string(JSON.stringify(rows)),"",true,true).sha256_text()

static func _select(catalog:Array,ids:Array)->Dictionary:
	var selected:Array=[];var seen:Dictionary={}
	for id:Variant in ids:
		if not id is String or seen.has(id):return Data.reject("INVALID_GENERATION_PROFILE_IDS")
		seen[id]=true
		var matches:Array=catalog.filter(func(p:Variant)->bool:return p is Dictionary and p.get("id")==id)
		if matches.size()!=1:return Data.reject("GENERATION_PROFILE_VERSION_MISMATCH",str(id))
		selected.append(matches[0].duplicate(true))
	return {"ok":true,"profiles":selected}

static func baseline(catalog:Array)->Array:
	# Explicit rural-2 stays on the six original families even after additions.
	# An incomplete/unrecognised catalogue still reaches the original validator;
	# never silently turn it into the no-profile planning fallback.
	var selected:=_select(catalog,ORIGINAL_IDS)
	if not selected.ok:return catalog
	var ids:Dictionary={}
	for id:String in ORIGINAL_IDS:ids[id]=true
	return catalog.filter(func(p:Variant)->bool:return p is Dictionary and ids.has(p.get("id")))

static func fresh(catalog:Array)->Dictionary:
	var ids:Array=[]
	if not catalog.is_empty():
		ids=ORIGINAL_IDS.duplicate()
		for id:String in RESIDENTIAL_IDS:
			if id not in ids and catalog.any(func(p:Variant)->bool:return p is Dictionary and p.get("id")==id):ids.append(id)
	ids.sort()
	var selected:=_select(catalog,ids)
	if not selected.ok:return selected
	var residential:Array=[]
	for id:String in RESIDENTIAL_IDS:
		if id in ids:residential.append(id)
	var contract:Dictionary={"profile_ids":ids,"residential_selection":{"version":2 if residential.size()>2 else 1,"ids":residential},"profile_contract_sha256":stamp(selected.profiles),"profile_input_sha256":stamp(selected.profiles,true),"landscape_model":"village-contours-v4"}
	return {"ok":true,"profiles":selected.profiles,"contract":contract}

static func resolve(configuration:Variant,catalog:Array)->Dictionary:
	if not configuration is Dictionary:return Data.reject("GENERATION_PROFILE_VERSION_MISMATCH")
	var expected:Variant=configuration.get("profile_contract_sha256")
	if configuration.has("profile_ids"):
		if not configuration.profile_ids is Array:return Data.reject("INVALID_GENERATION_PROFILE_IDS")
		var selected:=_select(catalog,configuration.profile_ids)
		if not selected.ok:return selected
		if stamp(selected.profiles)!=expected or stamp(selected.profiles,true)!=configuration.get("profile_input_sha256"):return Data.reject("GENERATION_PROFILE_VERSION_MISMATCH")
		var policy:Variant=configuration.get("residential_selection")
		# Native JSON restores integer-valued numbers as floats. Array membership
		# is type-sensitive, so validate integrality before comparing the version.
		if not policy is Dictionary or not Data.integer(policy.get("version")) or int(policy.version) not in [1,2] or not policy.get("ids") is Array:return Data.reject("GENERATION_POLICY_MISMATCH")
		var allowed:Array=[]
		for id:String in RESIDENTIAL_IDS:
			if id in configuration.profile_ids:allowed.append(id)
		if not Data.json_equal(policy.ids,allowed) or (policy.version==1 and allowed.size()>2) or (policy.version==2 and allowed.size()<=2):return Data.reject("GENERATION_POLICY_MISMATCH")
		if configuration.has("landscape_model") and configuration.landscape_model not in ["organic-local-v1","local-apron-v2","local-apron-v3","village-contours-v4","broad-terraces-v5","local-hills-v6","local-relief-v7","site-relief-v8"]:return Data.reject("GENERATION_POLICY_MISMATCH")
		if configuration.has("layout_policy") and not BoundedLayout.valid_policy(configuration.layout_policy):return Data.reject("GENERATION_POLICY_MISMATCH")
		var contract:Dictionary={}
		for key:String in PIN_FIELDS:
			if configuration.has(key):contract[key]=configuration[key].duplicate(true) if configuration[key] is Array or configuration[key] is Dictionary else configuration[key]
		contract.profile_contract_sha256=expected
		return {"ok":true,"profiles":selected.profiles,"contract":contract}
	# Pre-pinning saves keep their actual stamp and original selection rules.
	# Only an exact catalogue or exact original-six subset may satisfy it.
	for candidate:Array in [catalog,baseline(catalog)]:
		if candidate.all(func(p:Variant)->bool:return p is Dictionary) and stamp(candidate)==expected:
			var contract:Dictionary={"legacy":true,"profile_contract_sha256":expected}
			if configuration.has("dressing_contract_sha256"):contract.dressing_contract_sha256=configuration.dressing_contract_sha256
			return {"ok":true,"profiles":candidate.duplicate(true),"contract":contract}
	return Data.reject("GENERATION_PROFILE_VERSION_MISMATCH","Use the original saved geometry contract; never move a saved border/pad")

static func plan_matches(configuration:Dictionary,plan:Dictionary)->bool:
	for key:String in PIN_FIELDS:
		if configuration.has(key)!=plan.has(key):return false
		if configuration.has(key) and not Data.json_equal(configuration[key],plan[key]):return false
	return true
