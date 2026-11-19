extends SceneTree
const State=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const Terrain=preload("res://scripts/terrain/terrain_service.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Actions=preload("res://scripts/actions/action_service.gd")
const Codec=preload("res://scripts/world/world_codec.gd")
const Data=preload("res://scripts/world/world_data.gd")
const CATALOG="res://data/buildings/generation_profiles.json"
var world:=State.new()
var runtime:=Runtime.new()
var terrain:=Terrain.new()
var checks:Array=[]
var details:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func commit(operations:Array)->Dictionary:
	var draft:Dictionary=world.prepare_changes(operations,world.get_revision())
	return world.commit_prepared(draft.capability) if draft.ok else draft
func locate(x:float,z:float)->void:
	var actor:Dictionary={"id":"player","name":"test","x":x,"y":world.surface_height(x,z),"z":z,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"pack":{"soil_m3":2.0},"intent":null,"relationship":{"consent":true}}
	var state:Dictionary=Production.empty_state();state.tools=[{"id":"fixture:shovel","kind":"shovel","holderId":"pack:player","durability":100.0,"qualities":{"shovel":1,"pickaxe":1}}]
	var p:Dictionary=commit([{"op":"extension.set","id":"r3:production","before_exists":world.has_extension("r3:production"),"before":world.extension("r3:production"),"after":state}])
	var configured:Dictionary=runtime.configure({"world":world,"facts":{"actors":[actor],"stocks":Rural.empty_resource_stocks(world),"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":{"buildings":Building.new(),"production":Production.new(),"actions":Actions.new(),"terrain":terrain}})
	if not p.ok or not configured.ok:push_error("fixture configure "+str(configured))
func request(cell:Dictionary,id:String="contact:preview")->Dictionary:
	return {"command_id":id,"kind":"terrain","actor_id":"player","target_id":"terrain:%d:%d:%d"%[cell.x,cell.y,cell.z],"payload":{"tool_id":"fixture:shovel","held":true,"edit":{"operation":"dig","cells":[cell]}}}
func set_cells(cells:Array,after:int)->void:
	var ops:Array=[]
	for c:Vector3i in cells:ops.append({"op":"voxel.set","cell":{"x":c.x,"y":c.y,"z":c.z},"before":world.cell_at(c.x,c.y,c.z),"after":after})
	var result:Dictionary=commit(ops)
	if not result.ok:push_error(str(result))
func run()->void:
	check("controlled old flat fixture loads without a new world authority",world.load_snapshot(Rural.generate()).ok)
	# A supported 1.5m bank is closer to the hand than its buried centre is to
	# the feet. This directly distinguishes the new rule from centre reach.
	set_cells([Vector3i(59,0,60),Vector3i(59,1,60),Vector3i(59,2,60)],2)
	locate(27.2,30.25)
	var cell:Dictionary={"x":59,"y":2,"z":60};var req:Dictionary=request(cell,"contact:actual-dig")
	var preview:Dictionary=runtime.availability(req)
	details.near_face_preview=preview
	var actual:Dictionary=preview.get("contacts",[{}])[0]
	check("real exposed side is reachable even when foot to voxel centre exceeds range",preview.ok and Vector3(27.2,0,30.25).distance_to(Vector3(29.75,1.25,30.25))>2.5,preview)
	check("preview reports exact side point normal distance and stable cell identity",preview.ok and is_equal_approx(actual.point.x,29.5) and actual.normal.x==-1 and is_equal_approx(actual.distance,2.3) and actual.target_id=="terrain:59:2:60",actual)
	var started:Dictionary=runtime.command(req)
	check("same production command accepts preview without early mutation",started.ok and world.cell_at(59,2,60)==2 and runtime.actor("player").pack.soil_m3==2.0,started)
	if started.ok:
		for i in 16:runtime.tick(0.1)
	check("real A clock commits surface dig once with original material and wear",world.cell_at(59,2,60)==0 and runtime.actor("player").pack.soil_m3==2.125 and is_equal_approx(runtime.tool("fixture:shovel").durability,99.9))
	set_cells([Vector3i(59,2,60)],2)
	locate(27.3,30.25)
	var ground:Dictionary={"x":59,"y":-1,"z":60}
	var denied:Dictionary=runtime.availability(request(ground))
	check("low ground beyond actual hand reach is rejected despite close foot centre",not denied.ok and denied.code=="UNREACHABLE",denied)
	locate(27.2,30.25)
	var barrier:Array=[]
	for y in 5:
		for z in range(59,62):barrier.append(Vector3i(57,y,z))
	set_cells(barrier,2)
	denied=runtime.availability(request(cell))
	check("near visible-face rule never sees through unselected real voxel wall",not denied.ok and denied.code=="OCCLUDED",denied)
	set_cells(barrier,0)
	var cold_key:="3,0,3"
	var cold:Dictionary=commit([{"op":"chunk.residency","id":cold_key,"before":true,"after":false}])
	denied=runtime.availability(request(cell))
	check("cold target is not treated as known usable terrain",cold.ok and not denied.ok and denied.code=="UNLOADED_CELL",denied)
	commit([{"op":"chunk.residency","id":cold_key,"before":false,"after":true}])
	locate(8.25,0.35)
	denied=runtime.availability(request({"x":16,"y":-1,"z":-1}))
	check("legacy rural1 terrain cannot bypass its original region rule",not denied.ok and denied.code=="WRONG_REGION",denied)
	var profiles:Array=JSON.parse_string(FileAccess.get_file_as_string(CATALOG)).profiles
	check("actual nonflat rural3 source loads for cross-partition interaction",world.load_snapshot(Landscape.generate(713,profiles)).ok)
	var crossing_x:float=world.extension("generation:RH-HOME").road_ports.filter(func(port:Dictionary)->bool:return port.direction=="north")[0].position.x+0.25
	locate(crossing_x,0.35)
	var cy:int=roundi(world.surface_height(crossing_x,-1.25)*2)-1
	var across:Dictionary={"x":floori(crossing_x*2),"y":cy,"z":-3}
	details.cross_partition_input={"actor":runtime.actor("player"),"cell":across,"surface_y":(cy+1)*0.5,"rationale":"real graded public road; separate shared-space test covers non-exit edge"}
	var ready:Dictionary=runtime.availability(request(across,"contact:cross-real"))
	details.cross_partition_preview=ready
	check("actual loaded adjacent rural surface ignores arbitrary region ID boundary",ready.ok and ready.contacts[0].to_region_id=="RH-VILLAGE" and ready.contacts[0].from_region_id=="RH-HOME",ready)
	var source_y:float=world.surface_height(crossing_x,-0.65)
	var entity:Dictionary={"id":"fixture:cross-obstruction","kind":"object","regionId":"RH-VILLAGE","position":{"x":crossing_x,"y":source_y,"z":-0.65},"bounds":{"min":{"x":crossing_x-0.5,"y":source_y,"z":-0.8},"max":{"x":crossing_x+0.5,"y":source_y+3.0,"z":-0.5}},"revision":0,"blocksTerrain":false,"data":{"solid":true,"opaque":true}}
	var placed:Dictionary=commit([{"op":"entity.put","id":entity.id,"before_exists":false,"before":null,"after":entity}])
	denied=runtime.availability(request(across))
	check("sibling region solid entity remains real LOS obstruction",placed.ok and not denied.ok and denied.code=="OCCLUDED",denied)
	commit([{"op":"entity.remove","id":entity.id,"before":world.entity(entity.id)}])
	var target_key:String=Data.key(Data.cell_chunk(Vector3i(across.x,across.y,across.z),16))
	cold=commit([{"op":"chunk.residency","id":target_key,"before":true,"after":false}]);denied=runtime.availability(request(across))
	check("cross-region contact never opens unloaded terrain",cold.ok and not denied.ok and denied.code=="UNLOADED_CELL",denied)
	commit([{"op":"chunk.residency","id":target_key,"before":false,"after":true}])
	var target_material:int=world.cell_at(across.x,across.y,across.z)
	var yield_item:String=Data.MATERIALS[target_material].item
	var quantity_before:float=runtime.actor("player").pack.get(yield_item,0.0)
	var valid:Dictionary=runtime.command(request(across,"contact:cross-commit"))
	if valid.ok:
		for i in 16:runtime.tick(0.1)
	check("same real runtime commits cross-boundary terrain after its full recheck",valid.ok and world.cell_at(across.x,across.y,across.z)==0,valid)
	var encoded:Dictionary=Codec.encode_checkpoint(world.snapshot(),{"runtime":runtime.facts()},"test:surface-contact")
	var decoded:Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
	var restored:=State.new();var loaded:Dictionary=restored.load_snapshot(decoded.state) if decoded.ok else decoded
	var saved_pack:Dictionary=decoded.extensions.runtime.actors[0].pack if decoded.ok else {}
	var material_fact:Dictionary={"material":target_material,"yield_item":yield_item,"quantity_before":quantity_before,"runtime_pack":runtime.actor("player").pack,"saved_pack":saved_pack,"encoded_ok":encoded.ok,"decoded_ok":decoded.ok,"loaded_ok":loaded.ok}
	details.cross_partition_material=material_fact
	check("actual native codec preserves cross-boundary edit and material fact",loaded.ok and restored.cell_at(across.x,across.y,across.z)==0 and is_equal_approx(saved_pack.get(yield_item,-1.0),quantity_before+0.125) and saved_pack==runtime.actor("player").pack,material_fact)
	finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"details":details,"scope":"same actual C service/A runtime/B LOS and codec, controlled old geometry then actual new landscape; no formal app/OS/VA"}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify(report));quit(1 if failed else 0)
