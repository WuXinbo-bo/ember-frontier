extends RefCounted
const Data=preload("res://scripts/world/world_data.gd")
const PATH:="res://data/modules/catalog_v1.json"
const MECHANISMS_PATH:="res://data/modules/mechanisms_v2.json"
const OPENING15_PATH:="res://data/modules/opening_v15.json"
const OPENING15_WORKSHOP:="r35.module.village_workshop.opening-v15"
const Compact=preload("res://scripts/modules/compact_catalog.gd")
const Families=preload("res://scripts/modules/village_family_catalog.gd")
const RegionalArt=preload("res://scripts/modules/village_regional_catalog.gd")
const Chapter=preload("res://scripts/modules/village_chapter_catalog.gd")

static var _mutex:Mutex=Mutex.new()
static var _loaded:bool=false
static var _definitions:Array=[]
static var _by_id:Dictionary={}
static var _views:Dictionary={}
static var _reads:int=0
static func _ensure()->void:
	_mutex.lock()
	if not _loaded:
		var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH));_reads+=1
		if value is Dictionary and value.get("schema")=="afterglow-modules-v1" and value.get("version")==1:
			_definitions=value.get("definitions",[]).duplicate(true)
			var mechanisms:Variant=JSON.parse_string(FileAccess.get_file_as_string(MECHANISMS_PATH))
			if mechanisms is Dictionary and mechanisms.get("schema")=="afterglow-module-mechanisms-v2" and mechanisms.get("version")==2:_definitions.append_array(mechanisms.get("definitions",[]).duplicate(true))
			var opening:Variant=JSON.parse_string(FileAccess.get_file_as_string(OPENING15_PATH))
			if opening is Dictionary and opening.get("schema")=="afterglow-opening-modules-v15" and opening.get("version")==15:
				for overlay:Dictionary in opening.get("definitions",[]):
					for base:Dictionary in _definitions.duplicate():
						if base.id!=overlay.get("inherits"):continue
						var derived:Dictionary=base.duplicate(true);derived.merge(overlay.duplicate(true),true)
						derived.erase("inherits");_definitions.append(derived);break
			_definitions.append_array(Compact.derive(_definitions))
			_definitions.append_array(Families.derive(_definitions))
			_definitions.append_array(RegionalArt.derive(_definitions))
			_definitions.append_array(Chapter.derive(_definitions))
			for d:Dictionary in _definitions:
				_by_id[str(d.id)]=d
				var view:Dictionary=d.duplicate(true);_freeze(view);_views[str(d.id)]=view
		_loaded=true
	_mutex.unlock()
static func definitions()->Array:
	_ensure();return _definitions.duplicate(true)
static func definition(id:String)->Dictionary:
	_ensure();return _by_id.get(id,{}).duplicate(true)
static func definition_view(id:String)->Dictionary:
	# Internal validators read the same process-pinned immutable definition.
	# Public editable DTOs still use definition()/definitions(), never this view.
	_ensure();return _views.get(id,{})
static func _freeze(value:Variant)->void:
	if value is Dictionary:
		for child:Variant in value.values():_freeze(child)
		value.make_read_only()
	elif value is Array:
		for child:Variant in value:_freeze(child)
		value.make_read_only()
static func statistics()->Dictionary:
	_ensure();return {"file_reads":_reads,"definitions":_definitions.size(),"immutable_process_catalog":true}

static func build_definition_ids(content_version:int=16)->Array:
	# One authoritative catalog: historical definitions remain readable. The
	# build menu receives explicit current choices rather than historical duplicates.
	if content_version>=20:return Families.CHOICES.map(func(id:String)->String:return Chapter.id_for(id))
	if content_version>=18:return Families.CHOICES.duplicate()
	var current:Array=[]
	for d:Dictionary in definitions():
		if d.has("village_family_art"):continue
		if d.has("compact_kind"):continue
		if d.get("opening_only",false):continue
		if content_version>=17 and d.get("mechanism",{}).get("family") in ["home","warehouse","sawmill","water","canteen","artisan"]:continue
		if d.get("mechanism",{}).get("version")==2 or (not d.has("architecture") and (d.get("geometry_family_version",1)==2 or d.id in ["r34.module.hand_workshop","r34.module.supply_roadside_v2","r34.module.supply_rear_v3"])):current.append(d.id)
	return Compact.CHOICES + current if content_version>=17 else current

static func profiles(include_quality:bool=false)->Array:
	# Compatibility API: content1--8 uses12, content9 uses18 forever.
	return _profiles(include_quality,false)

static func profiles_for_content(content_version:int)->Array:
	if content_version>=20:
		var rows:=_profiles(true,true,true,true,false,true,true)
		for row:Dictionary in rows:
			if not str(row.id).begins_with(Families.PREFIX):continue
			var d:=definition(Chapter.id_for(str(row.id)))
			row.merge({"id":d.id,"design_id":d.design_id,"geometry_version":d.geometry_version},true)
		return rows
	if content_version in [18,19]:return _profiles(true,true,true,true,false,true,content_version==19)
	if content_version==17:return _profiles(true,true,true,true,true)
	if content_version>=1 and content_version<=8:return profiles(false)
	if content_version==9:return profiles(true)
	if content_version in [10,12,13,14,15,16]:return _profiles(true,true,content_version in [13,14,15,16],content_version in [15,16])
	return []

static func _profiles(include_quality:bool,include_repair:bool,village:bool=false,opening15:bool=false,compact:bool=false,families:bool=false,regional:bool=false)->Array:
	var rows:Array=[]
	for definition:Dictionary in definitions():
		if definition.get("chapter_geometry",false):continue
		if definition.get("regional_art",false) and not regional:continue
		if definition.has("village_family_art"):
			if not families or definition.id not in [Families.HOME,Families.WORKSHOP,Families.WAREHOUSE]:continue
		elif definition.has("compact_kind") and (not compact or definition.id not in [Compact.WORKSHOP,Compact.WAREHOUSE]):continue
		if families and definition.id in ["r35.module.village_home","r35.module.village_warehouse",OPENING15_WORKSHOP]:continue
		if compact and definition.id in [OPENING15_WORKSHOP,"r35.module.village_warehouse"]:continue
		if definition.id==OPENING15_WORKSHOP and not opening15:continue
		if definition.id=="r35.module.village_workshop" and opening15:continue
		if definition.has("village_geometry") and (not village or str(definition.id).ends_with("_expanded") or definition.shape=="woodshop"):continue
		# Additive paid architecture is never retrofitted into pinned content1--10.
		if definition.get("architecture",{}).get("set")=="r34-architecture-30-v1":continue
		if definition.id=="r34.module.repair_shed_v3" and not include_repair:continue
		# New geometry cannot enter fresh historical content1--8 by accident.
		# C explicitly opts in for the separately pinned content9 contract.
		if not include_quality and definition.get("geometry_family_version",1)==2:continue
		var p:Dictionary={}
		for key:String in ["id","version","geometry_version","category","generation_role","footprint","foundation","ports","allowed_quarter_turns"]:p[key]=definition[key]
		for key:String in ["visual_family","design_id","story_front_point"]:
			if definition.has(key):p[key]=definition[key]
		# C consumes the true working apron as well as the main footprint.
		for port:Dictionary in definition.ports:
			var x:float=port.position[0];var z:float=port.position[2]
			p.foundation.pad_rectangles.append([x-1.0,z-1.0,x+1.0,z+1.0])
		rows.append(p)
	return rows

static func validate()->Dictionary:
	var rows:=definitions();var seen:Dictionary={}
	if rows.is_empty():return Data.reject("INVALID_MODULE_CATALOG")
	for d:Dictionary in rows:
		if not Data.valid_id(d.get("id")) or seen.has(d.id) or d.get("version")!=1 or not Data.valid_id(d.get("geometry_version")) or not Data.bounds(d.get("footprint")):return Data.reject("INVALID_MODULE_DEFINITION")
		seen[d.id]=true
		if d.has("architecture"):
			var a:Variant=d.architecture
			if not a is Dictionary or a.get("set")!="r34-architecture-30-v1" or a.get("family") not in ["home","sawmill","warehouse","canteen","artisan","water","repair","guard"]:return Data.reject("INVALID_MODULE_ARCHITECTURE")
			if a.get("tier") not in (["small","medium","large"] if a.family=="home" else ["low","mid","high"]):return Data.reject("INVALID_MODULE_ARCHITECTURE")
			for field:String in ["variant","variant_label","description"]:
				if not a.get(field) is String or a[field].is_empty():return Data.reject("INVALID_MODULE_ARCHITECTURE")
			if (a.family=="home" and (not Data.integer(a.get("design_capacity")) or a.design_capacity<=0)) or (a.family!="home" and a.has("design_capacity")):return Data.reject("INVALID_MODULE_ARCHITECTURE")
			var source_id:String=str(d.get("geometry_source_id",d.id))
			if d.get("geometry_family_version")!=3 or d.geometry_version!=source_id+(".geometry-v2" if d.get("mechanism",{}).get("family")=="home" else ".geometry-v1") or (a.family=="home" and (d.shape!="home" or a.design_capacity<=0)):return Data.reject("INVALID_MODULE_ARCHITECTURE")
			if source_id!=d.id:
				var source:Dictionary=definition_view(source_id)
				if source.is_empty() or source.has("geometry_source_id") or source.footprint!=d.footprint or source.ports!=d.ports or d.get("mechanism",{}).get("version")!=2:return Data.reject("INVALID_MODULE_GEOMETRY_REUSE")
		if not d.get("ports") is Array or d.ports.is_empty() or not d.get("buffer_specs") is Array or not d.get("build_cost") is Dictionary:return Data.reject("INVALID_MODULE_DEFINITION")
		var ports:Dictionary={}
		for p:Dictionary in d.ports:
			if not Data.valid_id(p.get("id")) or ports.has(p.id) or not p.get("position") is Array or p.position.size()!=3 or not p.get("use_points") is Array or p.use_points.is_empty():return Data.reject("INVALID_MODULE_PORT")
			ports[p.id]=true
		var buffers:Dictionary={}
		for b:Dictionary in d.buffer_specs:
			if not Data.valid_id(b.get("id")) or buffers.has(b.id) or not b.get("limits") is Dictionary or not ports.has(b.get("port_id")):return Data.reject("INVALID_MODULE_BUFFER")
			buffers[b.id]=true
	return {"ok":true,"code":"OK"}
