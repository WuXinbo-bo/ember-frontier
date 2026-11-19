extends SceneTree
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const State=preload("res://scripts/world/world_state.gd")
const Mesher=preload("res://scripts/terrain/terrain_mesher.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func faces(data:Dictionary)->Dictionary:
	var out:Dictionary={};var count:=0
	for group:Dictionary in data.groups.values():
		for i in range(0,group.vertices.size(),4):
			var lo:Vector3=group.vertices[i];var hi:=lo
			for j in 4:lo=lo.min(group.vertices[i+j]);hi=hi.max(group.vertices[i+j])
			var normal:Vector3=group.normals[i];var axis:int=normal.abs().max_axis_index();var u:int=(axis+1)%3;var v:int=(axis+2)%3
			var plane:int=roundi(lo[axis]*2)
			for y in range(roundi(lo[v]*2),roundi(hi[v]*2)):
				for x in range(roundi(lo[u]*2),roundi(hi[u]*2)):
					var id:String="%d:%d:%d:%d:%d:%d"%[axis,int(normal[axis]),plane,x,y,int(group.material)]
					out[id]=true;count+=1
	return {"cells":out,"unique":out.size()==count}
func run()->void:
	var profiles:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/generation_profiles.json")).profiles
	var source:Dictionary=Landscape.generate(973339546,profiles);var world:=State.new()
	check("actual ninth seed v4 source loads",world.load_snapshot(source).ok and world.extension("generation:rural2").landscape_model=="village-contours-v4")
	var exact:=true;var unique:=true;var chunks:=0;var faces_count:=0
	var start:=Time.get_ticks_usec()
	for key:String in world.chunk_keys():
		var merged:Dictionary=faces(Mesher.build(world,key,true));var unit:Dictionary=faces(Mesher.build(world,key,false))
		exact=exact and merged.cells==unit.cells;unique=unique and merged.unique and unit.unique;chunks+=1;faces_count+=unit.cells.size()
	check("all real seed greedy coverage equals one face per exposed half metre cell",exact,{"chunks":chunks,"half_metre_faces":faces_count})
	check("no duplicated coplanar face exists inside a terrain chunk",unique)
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"elapsed_ms":(Time.get_ticks_usec()-start)/1000.0,"scope":"CPU topology diagnostic of ninth seed regenerated explicit v4, not current saved world or actual PCK/Metal image; cannot isolate shader/shadow/overlay depth without A normal render diagnostics"}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify(report));quit(1 if failed else 0)
