extends SceneTree
## C boundary review of B's explicit v1; does not replace B construction safety.
const Data=preload("res://scripts/world/world_data.gd")
const Contract=preload("res://scripts/world/generation_contract.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Before3=preload("res://tests/world/fixtures/landscape_generator_before_housing.gd")
const State=preload("res://scripts/world/world_state.gd")
const Codec=preload("res://scripts/world/world_codec.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const OLD_CATALOG="res://tests/world/fixtures/foundation_before_catalog.json"
const OLD_PROFILES="res://tests/world/fixtures/foundation_before_generation_profiles.json"
const CATALOG="res://data/buildings/catalog.json"
const PROFILES="res://data/buildings/generation_profiles.json"
const HISTORY="res://data/buildings/geometry_history_v1.json"
var checks:Array=[]
var native_numeric_projection:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func differences(a:Variant,b:Variant,path:String="",out:Array=[])->Array:
	if out.size()>=12 or Data.json_equal(a,b):return out
	if a is Dictionary and b is Dictionary:
		for key:Variant in a:
			if not b.has(key):out.append({"path":path+"/"+str(key),"before":a[key],"after":"MISSING"})
			else:differences(a[key],b[key],path+"/"+str(key),out)
	elif a is Array and b is Array and a.size()==b.size():
		for i in a.size():differences(a[i],b[i],path+"/"+str(i),out)
	else:out.append({"path":path,"before":a,"after":b})
	return out
func run()->void:
	var old_catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OLD_CATALOG))
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	var history:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(HISTORY))
	var old_profiles:Array=JSON.parse_string(FileAccess.get_file_as_string(OLD_PROFILES)).profiles
	var profiles:Array=Building.generation_profiles()
	check("actual B generation profiles unchanged from 21:28 backup",Data.json_equal(profiles,old_profiles))
	check("catalog declares v1 and all 38 definitions have explicit history",catalog.get("geometryVersion")==1 and history.get("geometryVersion")==1 and history.definitions.size()==old_catalog.structure_definitions.size())
	var geometry_exact:=true
	for id:String in old_catalog.structure_definitions:
		var old:Dictionary=old_catalog.structure_definitions[id];var saved:Dictionary=history.definitions.get(id,{})
		for key:String in Geometry.GEOMETRY_KEYS:
			if old.has(key)!=saved.has(key) or (old.has(key) and not Data.json_equal(old[key],saved[key])):geometry_exact=false
	check("v1 geometric fields exactly preserve archived pre-production definitions",geometry_exact)
	check("actual C normal and complete content stamps unchanged",Contract.stamp(profiles)==Contract.stamp(old_profiles) and Contract.stamp(profiles,true)==Contract.stamp(old_profiles,true))
	var service:=Building.new();service.geometry.configure(catalog)
	var fresh:Dictionary=service.make_instance("floor","fixture:geometry-v1",{"x":8.0,"y":0.0,"z":8.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var legacy:Dictionary=fresh.duplicate(true);legacy.erase("geometryVersion");legacy.id="fixture:geometry-legacy";legacy.position.x=12.0
	check("B new instance explicitly v1 and missing old field resolves same definition",fresh.get("geometryVersion")==1 and Data.json_equal(service.geometry.definition(fresh),service.geometry.definition(legacy)))
	var unknown:Dictionary=fresh.duplicate(true);unknown.geometryVersion=2
	check("unknown building geometry still rejected by B resolver",service.geometry.definition(unknown).is_empty())
	var original_six:Array=Contract.baseline(old_profiles)
	for version:String in ["rural-1","rural-2","rural-3"]:
		var snapshot:Dictionary=Rural.generate(713) if version=="rural-1" else Rural.generate_settlement(713,original_six,"rural-2") if version=="rural-2" else Before3.generate(713,original_six)
		var world:=State.new();var loaded:Dictionary=world.load_snapshot(snapshot)
		check(version+" actual historical generator snapshot still loads",loaded.ok)
		if not loaded.ok:continue
		# Compare B metadata against the SAME old snapshot's native roundtrip.
		# The unchanged native JSON codec has pre-existing sub-ULP/ULP decimal
		# projection on decorative doubles; report that instead of claiming all
		# source double bits survive JSON or loosening any physical tolerance.
		var baseline_encoded:Dictionary=Codec.encode_checkpoint(world.snapshot(),{},"geometry-baseline:"+version)
		var baseline_decoded:Dictionary=Codec.decode_checkpoint(baseline_encoded.envelope) if baseline_encoded.ok else baseline_encoded
		if baseline_decoded.ok:native_numeric_projection[version]=differences(snapshot.extensions,baseline_decoded.state.extensions)
		# Deliberate codec fixture, not a player build: B safety/placement remains
		# B's separate qualification. Extension and entity share exact same DTO.
		var structure_data:Dictionary={"schemaVersion":1,"instances":[fresh,legacy],"storeys":[]}
		var changes:Array=[{"op":"extension.set","id":"r3:structures","before_exists":false,"before":null,"after":structure_data}]
		for instance:Dictionary in [fresh,legacy]:changes.append({"op":"entity.put","id":instance.id,"before_exists":false,"before":null,"after":service.geometry.entity(instance)})
		var prepared:Dictionary=world.prepare_changes(changes,world.get_revision())
		if prepared.ok:world.commit_prepared(prepared.capability)
		var live_extensions:Dictionary=world.snapshot().extensions;live_extensions.erase("r3:structures")
		check(version+" sole world accepts B v1 without changing any old in-memory plan",prepared.ok and Data.json_equal(live_extensions,snapshot.extensions))
		var encoded:Dictionary=Codec.encode_checkpoint(world.snapshot(),{},"geometry-lock:"+version)
		var decoded:Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
		var decoded_extensions:Dictionary=decoded.state.extensions.duplicate(true) if decoded.ok else {};decoded_extensions.erase("r3:structures")
		check(version+" codec preserves B explicit/missing fields and same native baseline plan",decoded.ok and baseline_decoded.ok and Data.json_equal(decoded.state.extensions.get("r3:structures"),structure_data) and Data.json_equal(decoded_extensions,baseline_decoded.state.extensions) and decoded.state.worldId==snapshot.worldId and decoded.state.generatorVersion==version,{"code":decoded.get("code"),"pre_existing_numeric_projection":native_numeric_projection.get(version,[])})
		if decoded.ok:
			var restored:=State.new();restored.load_snapshot(decoded.state)
			var before:Dictionary=restored.snapshot()
			if version=="rural-1":
				check("rural1 remains original finite world rather than auto-migrated",not Rural.region_generation_input(restored,profiles).ok and Data.json_equal(before,restored.snapshot()))
			else:
				var captured:Dictionary=Rural.region_generation_input(restored,profiles)
				var draft:Dictionary=Rural.draft_region_request(captured,Vector2i(1,0)) if captured.ok else captured
				var expansion:Dictionary=Rural.prepare_region_draft(restored,draft,restored.get_revision()) if draft.ok else draft
				check(version+" restored saved content permits actual adjacent prepare after B field/history addition",expansion.ok and Data.json_equal(before,restored.snapshot()),expansion.get("code"))
				var changed:Array=profiles.duplicate(true);changed[0].foundation.elevation_offset=12345
				check(version+" used profile geometry change is still rejected",not Rural.region_generation_input(restored,changed).ok)
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"native_numeric_projection":native_numeric_projection,"scope":"C codec/content-lock boundary using actual B v1 and preproduction source; native JSON decorative double projection disclosed, not B full safety, OS/app or whole acceptance"}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify(report));quit(1 if failed else 0)
