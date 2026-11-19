extends "res://tests/buildings/domain_suite.gd"
## Geometry-version/history dependencies of the disposable room projection.
## Derived definition variations below never modify catalog/history or world.
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
const Space=preload("res://scripts/buildings/building_space.gd")
const Data=preload("res://scripts/world/world_data.gd")

func query(data:Dictionary,geo:RefCounted)->RefCounted:
	var q:=Space.new();q.configure(world,data,geo,func(_a:String,_b:String,_c:String,_d:Dictionary)->Variant:return null)
	return q

func run()->void:
	var started:int=Time.get_ticks_msec()
	expect("retained actual rural source loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var seeded:Dictionary=building.seed_rural(world)
	var draft:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("actual B geometry seed commits",draft.ok and world.commit_prepared(draft.capability).ok)
	var q:RefCounted=building.current_space();var policy:=Policy.new();policy.configure(q)
	var before:Dictionary=runtime.capture_checkpoint();var key:String=policy._structure_key(q)
	var legacy:Dictionary=q.state.duplicate(true)
	for piece:Dictionary in legacy.instances:piece.erase("geometryVersion")
	var old:RefCounted=query(legacy,building.geometry)
	expect("missing version means same archived legacy geometry one",policy._structure_key(old)==key and Geometry.GEOMETRY_VERSION==1)
	var unsupported:Dictionary=legacy.duplicate(true);unsupported.instances[0].geometryVersion=999
	# Key computation is read-only; do not configure an invalid Space instance.
	old.pieces=unsupported.instances
	expect("unknown geometry version cannot reuse prior topology identity",policy._structure_key(old)!=key and building.geometry.definition(unsupported.instances[0]).is_empty())
	var rooms:Dictionary={}
	for roof:Dictionary in policy._rooms.roofs:
		var at:Dictionary=q.standing_point(policy._rooms.room_point(roof))
		if at.is_empty() or at.buildingId!="rural:v1:RH-HOME:old-house":continue
		rooms[policy._rooms.component_at(at)]=at
	expect("actual closed structural rooms supply pending transition",rooms.size()>1)
	if rooms.size()<2:finish_local(started);return
	var first:Dictionary=rooms.values()[0];var other:Dictionary=rooms.values()[1]
	policy.sample(first,0);policy._observed=other.duplicate(true);policy.sample(other,100)
	var signature:String=policy.signature();var version:int=policy.statistics().topology_rebuilds
	var catalog:Dictionary=building.source_catalog.duplicate(true)
	var definition_id:String=q.pieces[0].definitionId
	catalog.structure_definitions[definition_id].material="ddd:explicit-material-only-variation"
	# Attempted catalog physical edits must resolve back to archived v1.
	catalog.structure_definitions[definition_id].size={"x":999,"y":999,"z":999}
	var material_geo:=Geometry.new();material_geo.configure(catalog)
	var material_query:RefCounted=query(q.state,material_geo)
	expect("actual history resolves catalog physical edit without changing topology",policy._structure_key(material_query)==key and material_geo.definitions[definition_id].size==building.geometry.definitions[definition_id].size)
	policy.configure(material_query)
	expect("pure live material replacement retains pending room confirmation",policy.signature()==signature and policy.statistics().pending and policy.statistics().topology_rebuilds==version)
	var geometric_geo:=Geometry.new();geometric_geo.configure(building.source_catalog)
	geometric_geo.definitions[definition_id].size.y=float(geometric_geo.definitions[definition_id].size.y)+0.05
	var geometry_query:RefCounted=query(q.state,geometric_geo)
	expect("resolved historical geometric field is a real topology dependency",policy._structure_key(geometry_query)!=key)
	policy.configure(geometry_query)
	expect("actual resolved geometry change rebuilds derived room projection",policy.statistics().topology_rebuilds>version and not policy.statistics().pending)
	expect("dependency checks never modify saved facts or archived definitions",Data.json_equal(before,runtime.capture_checkpoint()) and building.geometry.definitions[definition_id].size!=geometric_geo.definitions[definition_id].size)
	finish_local(started)

func finish_local(started:int)->void:
	var result:Dictionary={"scope":"actual B geometry-history v1 and D derived topology; isolated definition variation; no OS/VA","checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_TOPOLOGY "+JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
