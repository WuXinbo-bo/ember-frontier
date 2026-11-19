extends SceneTree
const Codec=preload("res://scripts/world/world_codec.gd")
const World=preload("res://scripts/world/world_state.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
var checks:Array=[]
class FlatTerrain extends RefCounted:
	# Explicit flat geometry fixture. Real unmodified source terrain is exercised
	# separately by legacy_suite; rotating just a house cannot rotate its city.
	func config()->Dictionary:return {"cellSize":0.5,"chunkCells":16,"minCellY":-8,"maxCellY":40}
	func entities()->Array:return []
	func chunk(key:String)->Dictionary:
		var cells:=PackedInt32Array();cells.resize(4096)
		if int(key.split(",")[1])<0:cells.fill(1)
		return {"generated":true,"cells":cells}
func expect(label:String,ok:bool,evidence:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"evidence":evidence})
	if not ok:print("FAIL ",label," ",JSON.stringify(evidence))
func _initialize()->void:call_deferred("run")
func sample(stair:Dictionary,run:float,fraction:float,y:float,storey:Variant)->Dictionary:
	var p:=Geometry.json_point(Geometry.transform(Vector3(0,0,-0.6+fraction*(run+1.2)),stair))
	p.merge({"y":y,"regionId":stair.regionId,"buildingId":stair.buildingId,"storeyId":storey},true)
	return p
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var decoded:Dictionary=Codec.decode_checkpoint(FileAccess.get_file_as_string(args[0]))
	var imported:Dictionary=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var world:=World.new();world.load_snapshot(imported.world)
	var building:=Building.new();var runtime:=Runtime.new()
	runtime.configure({"world":world,"facts":imported.facts,"services":{"buildings":building}})
	var original:Dictionary=building.structures()
	var source:Dictionary=original.instances.filter(func(v:Dictionary)->bool:return v.has("stairs") and str(v.buildingId).ends_with(":home"))[0]
	var pivot:=Vector3(16,0,13)
	var flat:=FlatTerrain.new()
	# Rotation is an isolated geometry fixture, not a rotated live city: retain
	# the entire actual home, exclude unrelated buildings from this fixture.
	original.instances=original.instances.filter(func(v:Dictionary)->bool:return v.get("buildingId")==source.buildingId)
	original.storeys=original.storeys.filter(func(v:Dictionary)->bool:return v.get("buildingId")==source.buildingId)
	for rotation in range(4):
		var data:Dictionary=original.duplicate(true)
		for v in data.instances:
			if v.get("buildingId")!=source.buildingId:continue
			v.position=Geometry.json_point(pivot+Geometry.rotate(Geometry.point(v.position)-pivot,rotation))
			v.quarterTurn=posmod(int(v.quarterTurn)+rotation,4)
		var stair:Dictionary=data.instances.filter(func(v:Dictionary)->bool:return v.id==source.id)[0]
		var query:RefCounted=building.space(flat,data)
		var d:Dictionary=building.geometry.definition(stair).stairs
		var clear:=bool(query.stair_clear(stair))
		var obstructions:Array=[]
		if not clear:
			for end in [Vector3(0,0,-0.6),Vector3(0,d.rise,float(d.run)+0.6)]:
				var at:=Geometry.transform(end,stair)
				var body:=AABB(at+Vector3(-0.26,0.05,-0.26),Vector3(0.52,1.8,0.52))
				for e in query.solid_entities:
					if Geometry.overlap(Geometry.aabb(e.bounds),body):obstructions.append(e.id)
		expect("rotated original floor/flight clear q"+str(rotation),clear,obstructions)
		var current:=sample(stair,float(d.run),0,float(stair.position.y),stair.stairs.fromStoreyId)
		var ok:=true;var problem:Dictionary={}
		for n in range(1,63):
			var moved:Dictionary=query.direct_move("player",current,sample(stair,float(d.run),float(n)/62,float(current.y),current.storeyId))
			if not moved.ok:ok=false;problem={"phase":"up","n":n,"result":moved};break
			current=moved.location
			if n==25:
				var pause:Dictionary=query.direct_move("player",current,current)
				expect("midflight stationary position stable q"+str(rotation),pause.ok and Geometry.point(pause.location).distance_to(Geometry.point(current))<0.001,pause)
				var reversed:Dictionary=query.direct_move("player",current,sample(stair,float(d.run),24.0/62,float(current.y),current.storeyId))
				expect("midflight reverse accepted q"+str(rotation),reversed.ok,reversed)
				if reversed.ok:
					var resumed:Dictionary=query.direct_move("player",reversed.location,sample(stair,float(d.run),25.0/62,float(reversed.location.y),reversed.location.storeyId))
					expect("midflight resume accepted q"+str(rotation),resumed.ok,resumed)
		expect("full ascent all orientations q"+str(rotation),ok and current.storeyId==stair.stairs.toStoreyId,problem)
		if ok:
			for n in range(61,-1,-1):
				var moved:Dictionary=query.direct_move("player",current,sample(stair,float(d.run),float(n)/62,float(current.y),current.storeyId))
				if not moved.ok:ok=false;problem={"phase":"down","n":n,"result":moved};break
				current=moved.location
			expect("full descent all orientations q"+str(rotation),ok and current.storeyId==stair.stairs.fromStoreyId and absf(float(current.y)-float(stair.position.y))<0.025,problem)
	print(JSON.stringify({"scope":"BBB original-home rotation fixtures, actual Godot spatial predicates; not source-world or app acceptance","ok":checks.all(func(v:Dictionary)->bool:return v.ok),"checks":checks}))
	quit(0 if checks.all(func(v:Dictionary)->bool:return v.ok) else 1)
