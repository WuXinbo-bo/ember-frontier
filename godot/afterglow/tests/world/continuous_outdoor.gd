extends SceneTree
const State=preload("res://scripts/world/world_state.gd")
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Data=preload("res://scripts/world/world_data.gd")
const CATALOG="res://data/buildings/generation_profiles.json"
var checks:Array=[]
var costs:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func at(x:float,y:float,z:float,region:String)->Dictionary:return {"x":x,"y":y,"z":z,"regionId":region,"buildingId":null,"storeyId":null}
func run()->void:
	var catalog:Array=JSON.parse_string(FileAccess.get_file_as_string(CATALOG)).profiles
	var source:Dictionary=Landscape.generate(713,catalog)
	var world:=State.new();check("actual new local-apron rural3 source loads",world.load_snapshot(source).ok)
	var a:Dictionary=at(8.25,world.surface_height(8.25,0.35),0.35,"RH-HOME")
	var b:Dictionary=at(8.25,world.surface_height(8.25,-0.35),-0.35,"RH-VILLAGE")
	var before:Dictionary=world.snapshot();var proof:Dictionary=world.continuous_outdoor_step(a,b)
	check("loaded physical rural edge works far from selected exit",proof.ok and absf(a.x-source.extensions["generation:RH-HOME"].road_ports[0].position.x)>8,{"a":a,"b":b,"proof":proof})
	check("same boundary is bidirectional",world.continuous_outdoor_step(b,a).ok)
	var hand_a:=a.duplicate();hand_a.y+=1.2;var hand_b:=b.duplicate();hand_b.y+=1.2
	check("contact qualification uses actual chest heights and zero body envelope",world.continuous_outdoor_contact(hand_a,hand_b).ok)
	check("proof leaves every authoritative fact unchanged",Data.json_equal(before,world.snapshot()))
	var wrong:=b.duplicate();wrong.regionId="RH-HOME"
	check("forged region tag is rejected",world.continuous_outdoor_step(a,wrong).get("code")=="REGION_MISMATCH")
	var invalid:=a.duplicate();invalid.x=NAN
	check("nonfinite positions fail closed",world.continuous_outdoor_step(invalid,b).get("code")=="INVALID_LOCATION")
	var indoors:=a.duplicate();indoors.buildingId="existing-home"
	check("building labels do not grant outdoor bypass",not world.continuous_outdoor_step(indoors,b).ok)
	indoors=a.duplicate();indoors.storeyId="existing-storey"
	check("storey-only indoor locations remain excluded",not world.continuous_outdoor_step(indoors,b).ok)
	var far:=b.duplicate();far.z=-1.5
	check("space proof remains bounded independently of movement budget",world.continuous_outdoor_step(a,far).get("code")=="SEGMENT_TOO_LONG")
	check("ungenerated next region remains closed",not world.continuous_outdoor_step(at(63.7,1,32,"RH-HOME"),at(64.3,1,32,"R2:1:0")).ok)
	var cold_key:=Data.key(Data.cell_chunk(Vector3i(floori(b.x*2),0,-1),16))
	check("loaded region and exact contact prime independent residency proofs",world.region_is_resident("RH-VILLAGE") and world.continuous_outdoor_contact(hand_a,hand_b).ok)
	var cold:Dictionary=world.prepare_changes([{"op":"chunk.residency","id":cold_key,"before":true,"after":false}],world.get_revision())
	check("prepared immutable view uses same residency query before commit",cold.ok and cold.view.continuous_outdoor_step(a,b).get("code")=="UNLOADED_CELL" and world.continuous_outdoor_step(a,b).ok)
	if cold.ok:world.commit_prepared(cold.capability)
	check("cold head/body space rejects both directions",world.continuous_outdoor_step(a,b).get("code")=="UNLOADED_CELL" and world.continuous_outdoor_step(b,a).get("code")=="UNLOADED_CELL")
	check("cold actual contact segment is also closed",world.continuous_outdoor_contact(hand_a,hand_b).get("code")=="UNLOADED_CELL")
	check("cold commit invalidates previous region residency proof",not world.region_is_resident("RH-VILLAGE"))
	var warm:Dictionary=world.prepare_changes([{"op":"chunk.residency","id":cold_key,"before":false,"after":true}],world.get_revision())
	if warm.ok:world.commit_prepared(warm.capability)
	check("warming exact facts immediately restores proof with current revision",warm.ok and world.continuous_outdoor_step(a,b).ok and world.continuous_outdoor_step(a,b).world_revision==2)
	check("warm commit invalidates a negative proof",world.region_is_resident("RH-VILLAGE") and world.continuous_outdoor_contact(hand_a,hand_b).ok)
	var missing:Dictionary=source.duplicate(true);missing.chunks.erase(cold_key)
	var incomplete:=State.new();var loaded:Dictionary=incomplete.load_snapshot(missing)
	check("known regions cannot hide a missing required chunk",loaded.ok and incomplete.continuous_outdoor_step(a,b).get("code")=="UNKNOWN_CELL")
	var gap:Dictionary=source.duplicate(true);gap.regions["RH-VILLAGE"].bounds.max.z=-0.0001
	var separated:=State.new();loaded=separated.load_snapshot(gap)
	check("submillimetre region gap is not approximate adjacency",loaded.ok and separated.continuous_outdoor_step(a,b).get("code")=="NOT_ADJACENT")
	var corner:Dictionary=source.duplicate(true);corner.entities={}
	corner.regions["RH-VILLAGE"].bounds.min.x=-64;corner.regions["RH-VILLAGE"].bounds.max.x=0
	var diagonal:=State.new();loaded=diagonal.load_snapshot(corner)
	check("corner-only region contact is not a shared walkable edge",loaded.ok and diagonal.continuous_outdoor_step(at(0.3,1,0.3,"RH-HOME"),at(-0.3,1,-0.3,"RH-VILLAGE")).get("code")=="NOT_ADJACENT")
	check("body near unproved third corner cannot use a two-region proof",not world.continuous_outdoor_step(at(0.1,1,0.35,"RH-HOME"),at(0.1,1,-0.35,"RH-VILLAGE")).ok)
	var legacy:=State.new();legacy.load_snapshot(Rural.generate())
	check("legacy rural1 portals are never silently opened",not legacy.continuous_outdoor_step(a,b).ok)
	var started:=Time.get_ticks_usec()
	for i in 1000:world.continuous_outdoor_step(a,b)
	costs={"1000_current_pair_queries_ms":(Time.get_ticks_usec()-started)/1000.0,"scope":"headless CPU geometry/residency only; no body/permission/FPS qualification"}
	finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"costs":costs,"failed":failed,"scope":"actual same world state and prepared view; partition and resident envelope proof only; B owns physical sweep/permission"}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify(report));quit(1 if failed else 0)
