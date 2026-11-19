extends SceneTree
## Pure contract/boundary fixtures. No terrain, stock or runtime is fabricated.
## Run unchanged against recorded old/new sources for semantic comparison.
const Zones=preload("res://scripts/planning/zone_service.gd")
const Def=preload("res://scripts/planning/zone_definitions.gd")
var checks:Array=[]
var observations:Array=[]
func _initialize()->void:call_deferred("run")
func check(name:String,actual:Variant,expected:Variant)->void:
	var ok:bool=actual==expected
	checks.append({"name":name,"ok":ok,"actual":actual,"expected":expected})
	observations.append({"name":name,"actual":actual})
	if not ok:print("FAIL "+name+" actual="+str(actual)+" expected="+str(expected))
func state_with(cells:Array=[{"x":0,"y":0,"z":0}])->Dictionary:
	return {"version":1,"revision":1,"zones":[{"id":"schema:field","kind":"farm","region_id":"RH-HOME","enabled":true,"revision":1,"name":"边界夹具","station_id":"","bounds":{"x0":-2,"z0":-2,"x1":2,"z1":2},"policy":{"crop_id":"potato","priority":2},"cells":cells.duplicate(true)}]}
func schema(name:String,state:Variant,ok:bool)->void:
	check(name,Zones.validate_state(state).get("ok",false),ok)
func run()->void:
	var scalar_cases:Array=[
		["zero",0,true,true],["negative",-1,true,true],["fraction",.25,false,false],
		["json zero",0.0,true,true],["json negative",-1.0,true,true],
		["positive bound",1048576,true,true],["negative bound",-1048576,true,true],
		["json bound",1048576.0,true,true],["overbound",1048577,true,false],
		["underbound",-1048577,true,false],["json overbound",1048577.0,true,false],
		["true",true,false,false],["false",false,false,false],["numeric string","0",false,false],
		["null",null,false,false],["array",[],false,false],["dictionary",{},false,false],
		["nan",NAN,false,false],["positive infinity",INF,false,false],["negative infinity",-INF,false,false],
		["max int",9223372036854775807,true,false],["min int",-9223372036854775807-1,true,false],
		["large finite integral",1e30,true,false]]
	for row:Array in scalar_cases:
		check("integer "+row[0],Def.integer(row[1]),row[2])
		for axis:String in ["x","y","z"]:
			var cell:Dictionary={"x":0,"y":0,"z":0};cell[axis]=row[1]
			check("cell "+axis+" "+row[0],Def.valid_cell(cell),row[3])
	for malformed:Variant in [null,[],"cell",{}, {"x":0,"z":0},{"x":0,"y":0}]:
		check("malformed cell "+str(malformed),Def.valid_cell(malformed),false)
	check("extra metadata remains allowed",Def.valid_cell({"x":0,"y":0,"z":0,"meta":"legacy"}),true)
	schema("empty versioned state",Zones.initial(),true)
	schema("one int cell",state_with(),true)
	var original:Dictionary=state_with();var json_state:Dictionary=JSON.parse_string(JSON.stringify(original))
	schema("actual JSON int-to-float round trip",json_state,true)
	check("JSON fixture preserves source dictionary",original.zones[0].cells[0].x is int,true)
	schema("mixed numeric duplicate",state_with([{"x":0,"y":0,"z":0},{"x":0.0,"y":0.0,"z":0.0}]),false)
	schema("different height remains distinct",state_with([{"x":0,"y":0,"z":0},{"x":0,"y":1,"z":0}]),true)
	schema("adjacent distinct cells",state_with([{"x":0,"y":0,"z":0},{"x":1,"y":0,"z":0}]),true)
	for axis:String in ["x","z"]:
		for value:int in [-3,-2,1,2]:
			var cell:Dictionary={"x":0,"y":0,"z":0};cell[axis]=value
			schema("half-open "+axis+" "+str(value),state_with([cell]),value>=-2 and value<2)
	var off:Dictionary=state_with([]);off.zones[0].enabled=false
	schema("cancelled empty plan remains legal",off,true)
	off.zones[0].enabled=true;schema("enabled empty plan rejects",off,false)
	for field:String in ["id","kind","region_id","enabled","revision","bounds","policy","cells"]:
		var bad:Dictionary=state_with();bad.zones[0].erase(field);schema("missing zone "+field,bad,false)
	var duplicate:Dictionary=state_with();duplicate.zones.append(duplicate.zones[0].duplicate(true));schema("duplicate zone identity rejects",duplicate,false)
	for revision:Variant in [-1,.5,true,"1",NAN,INF]:
		var bad:Dictionary=state_with();bad.revision=revision;schema("bad state revision "+str(revision),bad,false)
	for policy:Dictionary in [{"free_food":4},{"priority":true},{"priority":6},{"reserve_seed":-1},{"worker_ids":[1]},{"replant":1},{"fill_material":1}]:
		var bad:Dictionary=state_with();bad.zones[0].policy=policy;schema("bad policy "+str(policy),bad,false)
	for policy:Dictionary in [{},{"priority":0.0},{"priority":5},{"reserve_seed":1.0},{"worker_ids":["player"]},{"replant":true},{"fill_material":2.0}]:
		var good:Dictionary=state_with();good.zones[0].policy=policy;schema("valid policy "+str(policy),good,true)
	for extreme:int in [-9223372036854775807-1,9223372036854775807]:
		check("extreme bound "+str(extreme),Def.bounds_check({"x0":extreme,"z0":0,"x1":extreme+1 if extreme<0 else extreme,"z1":1}).get("ok",false),false)
	# Exercising maximum area ensures vector duplicate keys do not collapse rows.
	var maximum:Dictionary=state_with();var cells:Array=[]
	for z:int in 32:
		for x:int in 32:cells.append({"x":x,"y":0,"z":z})
	maximum.zones[0].bounds={"x0":0,"z0":0,"x1":32,"z1":32};maximum.zones[0].cells=cells
	schema("all 1024 distinct native cell keys",maximum,true)
	schema("all 1024 distinct JSON cell keys",JSON.parse_string(JSON.stringify(maximum)),true)
	maximum.zones[0].cells[1023]={"x":0.0,"y":0.0,"z":0.0};schema("last JSON numeric duplicate still rejects",maximum,false)
	finish()
func finish()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();var output:String=args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var ok:bool=checks.all(func(row:Dictionary)->bool:return row.ok)
	var file:=FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":ok,"checks":checks,"observations":observations,"scope":"pure schema fixtures; no gameplay, JSON save authority, OS, visuals or performance qualification"},"\t"));file.close()
	print("ZONE_SCHEMA "+str(checks.filter(func(row:Dictionary)->bool:return row.ok).size())+"/"+str(checks.size()))
	quit(0 if ok else 1)
