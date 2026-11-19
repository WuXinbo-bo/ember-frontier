extends SceneTree
const Data=preload("res://scripts/world/world_data.gd")
const Queries=preload("res://scripts/terrain/terrain_queries.gd")
const State=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
var checks:Array=[]
class Probe extends RefCounted:
	var cells:Dictionary={}
	var missing:Dictionary={}
	var cold:Dictionary={}
	func config()->Dictionary:return Data.DEFAULT_CONFIG
	func get_revision()->int:return 19
	func cell_at(x:int,y:int,z:int)->int:return cells.get(Vector3i(x,y,z),0)
	func is_cell_known(x:int,y:int,z:int)->bool:return not missing.has(Vector3i(x,y,z))
	func is_cell_resident(x:int,y:int,z:int)->bool:return not cold.has(Vector3i(x,y,z))
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func at(x:float,z:float)->Dictionary:return {"x":x,"y":5.0,"z":z,"regionId":"RH-HOME" if z>=0 else "RH-VILLAGE","buildingId":null,"storeyId":null}
func run()->void:
	var p:=Probe.new()
	for material:int in Data.MATERIALS:
		var caps:Dictionary=Data.material_capabilities(material)
		check("material "+str(material)+" current five purposes exact",["body","sight","contact","support","selection"].all(func(k:String)->bool:return caps[k]==(material!=0)))
	check("unknown material fails closed",Data.material_blocks(99,"sight") and not Data.material_capabilities(99).known)
	p.cells[Vector3i(1,0,0)]=3;p.cells[Vector3i(3,0,0)]=2
	var a:=Vector3(0.25,0.25,0.25);var b:=Vector3(2.25,0.25,0.25)
	var hit:Dictionary=Queries.segment(p,a,b,{"purpose":"sight"})
	check("nearest half metre stone wins over further soil",hit.get("target_id")=="terrain:1:0:0" and hit.distance==0.25 and hit.normal==Vector3.LEFT,hit)
	check("start inside solid hits zero",Queries.segment(p,Vector3(0.75,0.25,0.25),b).distance==0)
	check("closed end includes half open endpoint owner",not Queries.segment(p,a,Vector3(0.5,0.25,0.25)).is_empty())
	check("open end excludes exact target boundary",Queries.segment(p,a,Vector3(0.5,0.25,0.25),{"include_end":false}).is_empty())
	check("closed start boundary uses floor owner",Queries.segment(p,Vector3(0.5,0.25,0.25),a).get("material")==3)
	check("open start moving away does not hit cell behind",Queries.segment(p,Vector3(0.5,0.25,0.25),a,{"include_start":false}).is_empty())
	check("point segment included hits; open point is empty",Queries.segment(p,Vector3(0.75,0.25,0.25),Vector3(0.75,0.25,0.25)).distance==0 and Queries.segment(p,a,a,{"include_end":false}).is_empty())
	p.cells.clear();p.cells[Vector3i(1,0,0)]=2
	check("corner-only side graze is not interior intersection",Queries.segment(p,a,Vector3(1.25,1.25,0.25)).is_empty())
	p.cells[Vector3i(1,1,0)]=3
	hit=Queries.segment(p,a,Vector3(1.25,1.25,0.25))
	check("corner tie selects actual entered cell and deterministic single face",hit.get("target_id")=="terrain:1:1:0" and hit.normal==Vector3.LEFT,hit)
	p.cells.clear();p.cells[Vector3i(1,-1,0)]=3
	check("coplanar floor ray does not graze negative half open side",Queries.segment(p,Vector3(0.25,0,0.25),Vector3(1.25,0,0.25)).is_empty())
	p.cells[Vector3i(1,0,0)]=2
	check("coplanar positive owner blocks",not Queries.segment(p,Vector3(0.25,0,0.25),Vector3(1.25,0,0.25)).is_empty())
	p.missing[Vector3i(0,0,0)]=true
	check("nearest unknown before solid is retained",Queries.segment(p,a,b).get("unknown",false))
	p.missing.clear();p.cold[Vector3i(0,0,0)]=true
	check("generated only offline and resident runtime remain distinct",not Queries.segment(p,a,b).get("unknown",false) and Queries.segment(p,a,b,{"require_resident":true}).get("code")=="UNLOADED_CELL")
	check("bounded traversal rejects exhaustion",Queries.segment(p,a,b,{"max_cells":1}).get("code")=="RAY_BUDGET")
	check("nonfinite and invalid purpose reject",Queries.segment(p,Vector3(NAN,0,0),b).get("code")=="INVALID_SEGMENT" and Queries.segment(p,a,b,{"purpose":"magic"}).get("code")=="INVALID_SEGMENT")
	var source:Dictionary=Rural.generate(713)
	var legacy:=State.new();legacy.load_snapshot(source)
	source.generatorVersion="rural-2"
	for c:Dictionary in source.chunks.values():c.generatorVersion="rural-2"
	var world:=State.new();var loaded:Dictionary=world.load_snapshot(source)
	check("actual finite authority fixture loads",loaded.ok)
	var neighbors:Array=world.continuous_outdoor_neighbors("RH-HOME")
	check("real shared face publishes exact opposite region and varying extents",neighbors.size()==1 and neighbors[0].to_region_id=="RH-VILLAGE" and neighbors[0].face.axis=="z" and neighbors[0].face.coordinate==0.0 and neighbors[0].face.min.x<neighbors[0].face.max.x and neighbors[0].face.min.y<neighbors[0].face.max.y)
	check("legacy portal world and absent region have no invented outdoor adjacency",legacy.continuous_outdoor_neighbors("RH-HOME").is_empty() and world.continuous_outdoor_neighbors("missing").is_empty())
	neighbors[0].face.min.x=999
	check("neighbor DTO is detached from authority",world.continuous_outdoor_neighbors("RH-HOME")[0].face.min.x==0.0)
	for meters:float in [7.0,12.0]:
		check(str(meters)+"m continuous data proof independent of hand reach",world.continuous_outdoor_segment(at(8.25,3),at(8.25,3-meters),meters).ok)
		check(str(meters)+"m old city/rural1 does not bypass portal",not legacy.continuous_outdoor_segment(at(8.25,3),at(8.25,3-meters),meters).ok)
	check("contact still rejects seven metre reach",world.continuous_outdoor_contact(at(8.25,3),at(8.25,-4)).code=="SEGMENT_TOO_LONG")
	check("caller limit remains enforced",world.continuous_outdoor_segment(at(8.25,3),at(8.25,-9),7).code=="SEGMENT_TOO_LONG")
	check("infinite and excessive limits rejected",not world.continuous_outdoor_segment(at(8.25,3),at(8.25,-4),INF).ok and not world.continuous_outdoor_segment(at(8.25,3),at(8.25,-4),257).ok)
	var hole:Dictionary=source.duplicate(true);hole.chunks.erase("1,0,-1")
	var incomplete:=State.new();incomplete.load_snapshot(hole)
	check("actual traversed missing chunk blocks 12m",not incomplete.continuous_outdoor_segment(at(8.25,3),at(8.25,-9),12).ok)
	hole=source.duplicate(true);hole.chunks.erase("0,0,-1");incomplete.load_snapshot(hole)
	check("off-segment rectangle hole does not invent wall",incomplete.continuous_outdoor_segment(at(4.25,4.25),at(12.25,-3.75),12).ok)
	var cold:Dictionary=world.prepare_changes([{"op":"chunk.residency","id":"1,0,-1","before":true,"after":false}],world.get_revision())
	if cold.ok:world.commit_prepared(cold.capability)
	check("runtime cold blocks but explicit offline coverage remains valid",not world.continuous_outdoor_segment(at(8.25,3),at(8.25,-9),12).ok and world.continuous_outdoor_segment(at(8.25,3),at(8.25,-9),12,false).ok)
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"scope":"C exact segment/material/real generated partition coverage; no B entity LOS, no OS/performance qualification"}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify(report));quit(1 if failed else 0)
