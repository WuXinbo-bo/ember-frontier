extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Current=preload("res://scripts/buildings/building_space.gd")
const Original=preload("res://tests/buildings/saved_route_reference/building_space.gd")
const Door=preload("res://scripts/buildings/building_door_projection.gd")
var allowed:bool=true
var checks:Array=[]
func check(label:String,ok:bool)->void:checks.append({"name":label,"ok":ok})
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args();var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture);native.free()
	check("actual city v5 Store migration and Native assembly",built.get("ok",false))
	if not built.get("ok",false):print(JSON.stringify({"checks":checks}));quit(1);return
	var rt:RefCounted=built.runtime;var b:RefCounted=built.services.buildings;var w:RefCounted=built.world
	var before:Dictionary=rt.capture_checkpoint();var actors:int=0;var stairs:int=0;var doors:int=0
	for a:Dictionary in rt.facts().actors:
		var from:=G.location(a)
		if from.buildingId==null:continue
		for slot:Dictionary in w.extension("generation:"+str(from.regionId)).get("slots",[]):
			if slot.get("kind")!="entrance" or slot.get("buildingId")!=from.buildingId:continue
			var to:=G.location(slot);to.buildingId=null;to.storeyId=null;var ground:Variant=w.surface_height(to.x,to.z)
			if ground!=null:to.y=float(ground)
			var q:=Current.new();var old:=Original.new();allowed=true
			var permit:Callable=func(_id:String,_target:String,_kind:String,_piece:Dictionary)->Variant:return null if allowed else "explicit query-only denied"
			q.configure(w,b.structures(),b.geometry,permit);old.configure(w,b.structures(),b.geometry,permit)
			for state:String in ["cold","hot","denied","restored"]:
				allowed=state!="denied"
				check(str(a.id)+" exact complete route "+state,Data.json_equal(q.route(a.id,from,to),old.route(a.id,from,to)))
			for piece:Dictionary in q.stair_pieces:
				check("old multi-floor exact stair flight "+piece.id,q.stair_clear(piece)==old.stair_clear(old.by_id[piece.id]));stairs+=1
			var structures:Dictionary=b.structures()
			for piece:Dictionary in structures.instances:
				if not piece.has("door") or piece.get("buildingId")!=from.buildingId:continue
				piece.door.open=not piece.door.open;piece.version+=1
				var child:RefCounted=Door.project(q,structures,piece,permit)
				var reference:=Original.new();reference.configure(w,structures,b.geometry,permit)
				check("changed door child starts without column cache "+a.id,child.ground_columns.is_empty())
				check("changed leaf retains exact route "+a.id,Data.json_equal(child.route(a.id,from,to),reference.route(a.id,from,to)));doors+=1;break
			actors+=1
	check("actual old indoor actors stairs and changed leaves covered",actors==4 and stairs>0 and doors==4)
	check("all authority unchanged",Data.json_equal(before,rt.capture_checkpoint()))
	var report:Dictionary={"checks":checks,"actors":actors,"stairs":stairs,"doors":doors,"scope":"actual retained old-city-v5 routes plus query-only permission/door counterexamples, frozen original space exact oracle; no OS/VA/FPS claim"}
	FileAccess.open(args[0]+"/detail.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify(report));rt.retire();quit(0 if checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
