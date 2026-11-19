extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Nav=preload("res://scripts/buildings/building_navigation.gd")
const Space=preload("res://scripts/buildings/building_space.gd")
const Door=preload("res://scripts/buildings/building_door_projection.gd")
var checks:Array=[]
var rows:Array=[]
var reference:Script
var allowed:bool=true
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail});if not ok:print("FAIL ",label," ",detail)
func pair(q:RefCounted,id:String,from:Dictionary,to:Dictionary,label:String,grid:bool=false)->void:
	var a:RefCounted=Nav.new();var b:RefCounted=reference.new();var got:Dictionary;var expected:Dictionary
	if grid:
		for n:RefCounted in [a,b]:n.space=q;n.actor_id=id;n.nodes=[from,to]
		got=a.grid_plan(from,to);expected=b.grid_plan(from,to)
	else:got=a.plan(q,id,from,to);expected=b.plan(q,id,from,to)
	check(label,Data.json_equal(got,expected),{"actual":got,"reference":expected} if not Data.json_equal(got,expected) else null)
	rows.append({"case":label,"ok":got.get("ok",false),"visited":got.get("visited"),"steps":got.get("steps",[]).size()})
func run()->void:
	var args:=OS.get_cmdline_user_args();var cfg:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[3]));reference=load(cfg.reference_navigation)
	for input:String in [args[1],args[4]]:
		var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input));var h:=Native.new();var built:Dictionary=h._assemble(decoded.capture);h.free()
		check("unchanged actual Native input "+input,built.get("ok",false))
		if not built.get("ok",false):continue
		var rt:RefCounted=built.runtime;var b:RefCounted=built.services.buildings;var w:RefCounted=built.world;var before:Dictionary=rt.capture_checkpoint()
		if input==args[1]:
			var evidence:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[2]));var s:Dictionary=evidence.rows[0].profile.actions.route.slow[0]
			var q:RefCounted=b.space()
			pair(q,s.actor_id,s.from,s.to,"actual original normal route cold")
			pair(q,s.actor_id,s.from,s.to,"same-query warm full topology")
			for dy:float in [0.0,0.007,-0.007,0.024999,0.5]:
				var start:Dictionary=s.from.duplicate(true);start.y=float(start.y)+dy
				pair(q,s.actor_id,start,s.to,"explicit grid reference-height counterexample "+str(dy),true)
			var near:Dictionary=s.to.duplicate(true);near.x=float(near.x)+0.007
			pair(q,s.actor_id,s.from,near,"moved endpoint exact topology")
			var unknown:Dictionary=s.from.duplicate(true);unknown.x=-0.500001;unknown.z=-0.000001
			pair(q,s.actor_id,unknown,s.to,"negative/unknown rejects equally")
		else:
			var indoor:=0
			for actor:Dictionary in rt.facts().actors:
				var from:=G.location(actor)
				if from.get("buildingId")==null:continue
				for slot:Dictionary in w.extension("generation:"+str(from.regionId)).get("slots",[]):
					if slot.get("kind")!="entrance" or slot.get("buildingId")!=from.buildingId:continue
					var to:=G.location(slot);to.buildingId=null;to.storeyId=null;var ground:Variant=w.surface_height(to.x,to.z)
					if ground!=null:to.y=float(ground)
					var q:=Space.new();allowed=true;var permit:Callable=func(_a:String,_t:String,_k:String,_v:Dictionary)->Variant:return null if allowed else "withdrawn current permission"
					q.configure(w,b.structures(),b.geometry,permit)
					for mode:String in ["cold","warm","denied","restored"]:
						allowed=mode!="denied";pair(q,actor.id,from,to,"actual city "+actor.id+mode)
					var structures:Dictionary=b.structures()
					for piece:Dictionary in structures.instances:
						if not piece.has("door") or piece.get("buildingId")!=from.buildingId:continue
						piece.door.open=not piece.door.open;piece.version+=1
						pair(Door.project(q,structures,piece,permit),actor.id,from,to,"explicit changed real leaf "+actor.id);break
					indoor+=1
			check("all four old multi-floor indoor actors covered",indoor==4,indoor)
		check("route probes preserve all authority "+input,Data.json_equal(before,rt.capture_checkpoint()));rt.retire()
	var result:Dictionary={"checks":checks,"rows":rows,"scope":"Exact previous Navigation versus current on retained normal20/oldcity; forced grid height/permission/door cases are explicit counterexamples, not natural story evidence."}
	FileAccess.open(args[0]+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));quit(0 if checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
