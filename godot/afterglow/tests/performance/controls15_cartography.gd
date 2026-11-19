extends SceneTree
const World=preload("res://scripts/world/world_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Survey=preload("res://scripts/runtime/known_cartography.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"name":label,"ok":ok})
	if not ok:push_error(label)
func run()->void:
	var state:Dictionary={"worldId":"survey-fixture","seed":1,"generatorVersion":"factory-country-1","revision":1,"config":Data.DEFAULT_CONFIG.duplicate(true),"chunks":{},"regions":{},"extensions":{}}
	for cy:int in range(-1,3):
		var cells:=PackedInt32Array();cells.resize(4096)
		if cy==0:
			for z:int in 16:
				for x:int in 16:cells[x+16*z]=1
		state.chunks[Data.key(Vector3i(0,cy,0))]={"revision":1,"generated":true,"resident":true,"cells":cells}
	state.extensions["generation:known"]={"paths":[{"width":2.0,"points":[{"x":-8,"z":2},{"x":12,"z":2}]}],"water_sources":[{"id":"hidden","position":{"x":2,"z":2}}]}
	var world:=World.new(state)
	var map:Dictionary={"tile_metres":4.0,"explored_tiles":[{"region_id":"known","x":0,"z":0}]}
	var modules:Dictionary={"instances":[{"id":"known-house","definition_id":"narrow","quarter_turn":1,"location":{"x":2,"z":2,"regionId":"known"}}],"definitions":[{"id":"narrow","footprint":{"min":{"x":-0.5,"z":-1.0},"max":{"x":0.5,"z":1.0}}}]}
	var survey:=Survey.new();var value:Dictionary=survey.build(world,map,modules)
	check("only explored tile projects",value.cells.size()==1 and value.regions.size()==1)
	check("terrain material and elevation come from actual voxels",value.cells[0].terrain=="grass" and value.cells[0].elevation==0.5 and value.cells[0].known)
	check("known road clipped at explored tile boundaries",value.roads.size()==1 and value.roads[0].points==[{"x":0.0,"z":2.0},{"x":4.0,"z":2.0}])
	check("generated source cannot bypass live discovery",value.water.is_empty())
	check("physical building footprint projects",value.buildings.size()==1 and value.buildings[0].polygon.size()==4)
	var xs:Array=[];var zs:Array=[]
	for point:Dictionary in value.buildings[0].polygon:xs.append(float(point.x));zs.append(float(point.z))
	check("quarter-turn footprint follows building geometry",is_equal_approx(xs.max()-xs.min(),2.0) and is_equal_approx(zs.max()-zs.min(),1.0))
	var copy:Dictionary=survey.build(world,map,modules);copy.cells.clear()
	check("cached survey remains detached",survey.build(world,map,modules).cells.size()==1)
	var disclosed:Dictionary={"sources":[{"id":"known-source","location":{"x":2,"z":2,"regionId":"known"}},{"id":"unexplored-source","location":{"x":7,"z":2,"regionId":"known"}}]}
	check("only disclosed source inside explored ground publishes",survey.build(world,map,modules,disclosed).water.size()==1)
	state.chunks["0,0,0"].cells[4+16*4]=3;state.chunks["0,0,0"].revision+=1;state.revision+=1
	check("actual terrain edit invalidates cached material",survey.build(world,map,modules).cells[0].terrain=="stone")
	state.chunks["0,1,0"].generated=false;state.chunks["0,1,0"].revision+=1;state.revision+=1
	check("unknown column is never invented ground",not survey.build(world,map,modules).cells[0].known)
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var output:String=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"Explicit voxel/known-map fixture; no authority edits, map reveal or FPS claim"},"\t"))
	print("CONTROLS15_SURVEY "+JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
