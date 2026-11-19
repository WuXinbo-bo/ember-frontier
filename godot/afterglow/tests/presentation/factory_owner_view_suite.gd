extends SceneTree
## Actual C/B/E assembly and A facade -> D nodes, no renderer, file store or tick.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const View=preload("res://scripts/presentation/factory_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Stock=preload("res://scripts/presentation/factory_stock_view.gd")
var checks:Array=[]
var failures:Array=[]
var metrics:Array=[]
var access_evidence:Dictionary={}
static func row_ids(rows:Array)->Array:
	var ids:Array=[]
	for row:Dictionary in rows:ids.append(str(row.get("id","")))
	ids.sort();return ids
func expect(label:String,ok:bool,evidence:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"evidence":evidence})
	if not ok:failures.append(label);print("FAIL ",label," ",JSON.stringify(evidence))
func _initialize()->void:call_deferred("run")
func run()->void:
	var profiles:Dictionary=Assembly.generation_profiles()
	expect("real B generation profiles resolve",profiles.ok,profiles.get("reason"))
	if not profiles.ok:return finish()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	expect("real C B E finite-source assembly succeeds",prepared.ok,prepared.get("reason"))
	if not prepared.ok:return finish()
	var native:=Native.new();var built:Dictionary=native._assemble(prepared.capture);native.free()
	expect("real A offscreen service configuration succeeds",built.ok,built.get("reason"))
	if not built.ok:return finish()
	var runtime:RefCounted=built.runtime
	var before:Dictionary=runtime.capture_checkpoint()
	var dto:Dictionary=runtime.factory_snapshot()
	# Exact public fixture oracle, independent of the projection implementation.
	# Read raw world only to prove that hidden entities exist, not to publish them.
	var expected_ids:Array=["r34:generated:RH-HOME:home","r34:generated:RH-HOME:woodwork"]
	var hidden_ids:Array=["r34:generated:RH-VILLAGE:neighbor","r34:generated:RH-VILLAGE:store"]
	var raw_state:Dictionary=runtime.world.extension("r34:modules")
	var by_id:Dictionary={}
	for record:Dictionary in raw_state.get("instances",[]):by_id[str(record.id)]=record
	var home:Dictionary=by_id.get(expected_ids[0],{})
	expect("source home is discovered and granted to player's household",home.get("discovered")==true and home.get("region")=="RH-HOME" and home.get("owner")=="home-residents" and runtime.actor("player").get("householdId")=="home-residents",home)
	var woodwork:Dictionary=by_id.get(expected_ids[1],{})
	expect("source woodwork is independently discovered and granted to player's household",woodwork.get("discovered")==true and woodwork.get("region")=="RH-HOME" and woodwork.get("owner")=="home-residents" and woodwork.get("source_key")=="r34:713:RH-HOME:woodwork" and runtime.actor("player").get("householdId")=="home-residents",{"id":woodwork.get("id"),"definition_id":woodwork.get("definition_id"),"region":woodwork.get("region"),"discovered":woodwork.get("discovered"),"owner":woodwork.get("owner"),"source_key":woodwork.get("source_key")})
	var home_plan:Dictionary=runtime.world.extension("generation:RH-HOME")
	var home_seeds:Array=home_plan.get("module_seeds",[])
	var seed_semantics:bool=home_plan.get("generation_content_version")==4 and row_ids(home_seeds)==expected_ids
	for seed:Dictionary in home_seeds:
		var expected_purpose:String="home" if seed.get("id")==expected_ids[0] else "woodwork"
		var registered:Dictionary=by_id.get(str(seed.get("id","")),{})
		seed_semantics=seed_semantics and seed.get("purpose")==expected_purpose and seed.get("region")=="RH-HOME" and seed.get("source_key")=="r34:713:RH-HOME:"+expected_purpose and seed.get("definition_id")==registered.get("definition_id") and registered.get("source_key")==seed.get("source_key")
	expect("frozen content4 plan independently seeds exactly home and woodwork",seed_semantics,{"content_version":home_plan.get("generation_content_version"),"seed_ids":row_ids(home_seeds),"expected_ids":expected_ids})
	var hidden_ready:bool=true
	for id:String in hidden_ids:
		var hidden:Dictionary=by_id.get(id,{})
		hidden_ready=hidden_ready and hidden.get("region")=="RH-VILLAGE" and hidden.get("discovered")==false
	expect("both actual village modules exist but have not been discovered",hidden_ready,{"expected_hidden_ids":hidden_ids,"source_ids":by_id.keys()})
	expect("actual public facade exposes exactly discovered authorized home and woodwork",dto.available and dto.modules.available and row_ids(dto.modules.instances)==expected_ids,{"expected_ids":expected_ids,"actual_ids":row_ids(dto.modules.instances)})
	var unknown_markers:Array=[]
	for marker:Dictionary in dto.get("map",{}).get("markers",[]):
		if hidden_ids.has(str(marker.get("id",""))):unknown_markers.append(marker.id)
	expect("undiscovered village modules leak into neither public instances nor map markers",not dto.modules.instances.any(func(row:Dictionary)->bool:return hidden_ids.has(str(row.id))) and unknown_markers.is_empty(),{"hidden_ids":hidden_ids,"leaked_markers":unknown_markers})
	var outsider:Dictionary=runtime.actor("repair-resident")
	expect("real unjoined NPC fixture has no home household or consent grant",not outsider.is_empty() and outsider.get("householdId")=="repair-resident" and outsider.get("relationship",{}).get("member")==false and outsider.get("relationship",{}).get("consent")==false,outsider.get("relationship",{}))
	var denied:Dictionary=runtime.factory_snapshot("repair-resident")
	expect("known unjoined NPC cannot inspect discovered home or woodwork or undiscovered village",denied.available and denied.modules.available and denied.modules.instances.is_empty() and denied.modules.projects.is_empty(),{"actual_ids":row_ids(denied.modules.instances),"projects":denied.modules.projects})
	var absent:Dictionary=runtime.factory_snapshot("fixture:unknown-observer")
	expect("unknown observer gets unavailable empty module projection",not absent.available and not absent.modules.available and absent.modules.instances.is_empty() and absent.modules.projects.is_empty())
	access_evidence={"expected_public_ids":expected_ids,"actual_public_ids":row_ids(dto.modules.instances),"actual_hidden_ids":hidden_ids,"hidden_fixture_valid":hidden_ready,"unjoined_actor_public_ids":row_ids(denied.modules.instances),"unknown_actor_available":absent.available,"raw_woodwork":{"id":woodwork.get("id"),"definition_id":woodwork.get("definition_id"),"region":woodwork.get("region"),"discovered":woodwork.get("discovered"),"owner":woodwork.get("owner"),"source_key":woodwork.get("source_key")},"generation_seed_ids":row_ids(home_seeds),"generation_content_version":home_plan.get("generation_content_version")}
	if not dto.available or not dto.modules.available or dto.modules.instances.is_empty():return finish()
	var host:=Node3D.new();root.add_child(host);host.position=Vector3(50,3,-90);host.rotation.y=0.4
	var view:=View.new();host.add_child(view);view.set_process(false);view.configure(runtime)
	expect("actual owner nested DTO creates all discovered permitted module roots",view._roots.size()==dto.modules.instances.size() and view.statistics().required_errors.is_empty(),view.statistics().required_errors)
	var public_root_ids:Array=view._roots.keys();public_root_ids.sort()
	expect("actual consumer roots contain exactly home and woodwork with no undiscovered village",public_root_ids==expected_ids,{"expected_ids":expected_ids,"actual_root_ids":public_root_ids})
	var all_actual:bool=true;var all_zero:bool=true;var world_once:bool=true;var quantities:Array=[];var collisions:Array=[]
	for module:Dictionary in dto.modules.instances:
		var bounds:Array=[]
		for row:Dictionary in module.visuals.buffers:
			if not view._buffers.get(module.id,{}).has(row.id):all_actual=false;continue
			var stock:Node3D=view._buffers[module.id][row.id]
			var source:Dictionary=runtime.stock(row.stock_ref)
			var actual:float=float(source.get("items",{}).get(row.item_id,0))
			all_actual=all_actual and stock.get_meta("actual")==actual and stock.get_meta("unit")==row.unit and stock.statistics().band==Stock.band(actual,float(row.capacity))
			all_zero=all_zero and (actual>0 or stock.statistics().visible_parts==0)
			var anchor:Array=module.visuals.anchors[row.anchor_id].position
			world_once=world_once and stock.global_position.is_equal_approx(Vector3(anchor[0],anchor[1],anchor[2]))
			quantities.append({"module_id":module.id,"item_id":row.item_id,"unit":row.unit,"actual":actual,"reserved":row.reserved,"visible_parts":stock.statistics().visible_parts})
			var extent:=Vector3(row.extent[0],row.extent[1],row.extent[2])
			var box:=AABB(Vector3(-extent.x/2,0,-extent.z/2),extent)
			var world_box:AABB=stock.global_transform*box
			for other:Dictionary in bounds:
				if world_box.intersects(other.box):collisions.append({"module":module.id,"first":other.id,"second":row.id})
			bounds.append({"id":row.id,"box":world_box})
	expect("all actual owner stock values and units match real runtime stocks",all_actual,quantities)
	expect("zero real stocks never show collectible proxy parts",all_zero)
	expect("actual B world anchors apply once under transformed D host",world_once)
	expect("actual B distinct item bays do not overlap proxy extents",collisions.is_empty(),collisions)
	for definition:Dictionary in dto.modules.definitions:
		metrics.append({"definition_id":definition.id,"footprint":definition.footprint,"ports":definition.ports,"state_assets":definition.state_assets,"dimensions_status":definition.get("dimensions_status"),"visual_status":"numeric source candidate only; normal-camera VA pending"})
	var node_id:int=view._roots[dto.modules.instances[0].id].get_instance_id();var updates:int=view.statistics().updates
	view.sync();view.sync()
	expect("unchanged actual facade does not rebuild D nodes",view.statistics().updates==updates)
	expect("D public queries and node updates preserve entire authority",Data.json_equal(before,runtime.capture_checkpoint()))
	native=Native.new();var cold:Dictionary=native._assemble(before);native.free()
	expect("real checkpoint cold reassembles same content",cold.ok,cold.get("reason"))
	if cold.ok:
		var cold_dto:Dictionary=cold.runtime.factory_snapshot()
		expect("cold checkpoint preserves exact discovered home-and-woodwork public set",cold_dto.available and cold_dto.modules.available and row_ids(cold_dto.modules.instances)==expected_ids,{"expected_ids":expected_ids,"actual_ids":row_ids(cold_dto.modules.instances)})
		view.configure(cold.runtime)
		var cold_root_ids:Array=view._roots.keys();cold_root_ids.sort()
		expect("cold remount keeps both undiscovered village consumers absent",cold_root_ids==expected_ids,{"expected_ids":expected_ids,"actual_root_ids":cold_root_ids})
		expect("actual cold same-ID world retires old presentation references",view._roots.size()==dto.modules.instances.size() and view._roots[dto.modules.instances[0].id].get_instance_id()!=node_id and view.statistics().required_errors.is_empty(),view.statistics().required_errors)
	host.free();await process_frame
	finish()
func finish()->void:
	var result:Dictionary={"scope":"actual copied C/B/E assembly A public facade D node/material integration, no simulated time/store/render/import/export/OS/VA/performance approval","checks":checks,"failures":failures,"g0_numeric_module_candidates":metrics,"discovery_permission_evidence":access_evidence}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_FACTORY_OWNER ",JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
