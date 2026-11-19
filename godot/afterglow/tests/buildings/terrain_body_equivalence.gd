extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Current=preload("res://scripts/buildings/building_space.gd")
const Door=preload("res://scripts/buildings/building_door_projection.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:checks.append({"name":label,"ok":ok})
func run()->void:
	var args:=OS.get_cmdline_user_args();var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[3]));var original:Script=load(config.reference_space)
	var rows:Array=[]
	var city:String=ProjectSettings.globalize_path(args[4])
	for input:String in [args[1],city]:
		var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input));var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
		check("exact Native input "+input,built.get("ok",false))
		if not built.get("ok",false):continue
		var rt:RefCounted=built.runtime;var b:RefCounted=built.services.buildings;var before:Dictionary=rt.capture_checkpoint()
		var q:=Current.new();var old:RefCounted=original.new();q.configure(built.world,b.structures(),b.geometry,b.permission);old.configure(built.world,b.structures(),b.geometry,b.permission)
		var points:Array=[]
		for actor:Dictionary in rt.facts().actors:points.append(G.location(actor))
		for region:Dictionary in built.world.regions():
			var plan:Variant=built.world.extension("generation:"+str(region.id))
			if not plan is Dictionary:continue
			for path:Dictionary in plan.get("paths",[]):
				var raw:Array=path.get("points",[])
				for i:int in range(0,raw.size(),maxi(1,raw.size()/8)):
					var at:Dictionary=G.location(raw[i]);at.regionId=region.id;points.append(at)
		for piece:Dictionary in q.pieces:
			if piece.get("hp",0)>0 and (piece.has("stairs") or q.geometry.definition(piece).get("surfaceY")!=null):
				var p:=G.location(piece);points.append(p)
				if points.size()>=160:break
		# Exact boundary/negative/unknown positions and terrain/radius variants.
		points.append({"regionId":built.world.regions()[0].id,"x":-0.5000001,"y":0.5,"z":-0.0000001})
		points.append({"regionId":built.world.regions()[0].id,"x":10000.0,"y":0.0,"z":-10000.0})
		var failures:Array=[];var probes:int=0
		for p:Dictionary in points:
			for radius:float in [0.0,0.26,0.5]:
				for offset:float in [-0.550001,-0.5,0.0,0.5,0.550001]:
					var at:Dictionary=p.duplicate(true);at.y=float(at.y)+offset
					var a:Dictionary=q.body_location(at,radius);var c:Dictionary=old.body_location(at,radius);probes+=1
					if not Data.json_equal(a,c):failures.append({"at":at,"radius":radius,"actual":a,"old":c})
		check("all precise nine-probe body/support results including unknown equal",failures.is_empty())
		for p:Dictionary in points.slice(0,30):check("standing blockers unchanged "+str(p),Data.json_equal(q.standing_point(p),old.standing_point(p)))
		var changed:Dictionary=b.structures()
		for piece:Dictionary in changed.instances:
			if not piece.has("door"):continue
			piece.door.open=not piece.door.open;piece.version+=1
			var child:RefCounted=Door.project(q,changed,piece,b.permission);var reference:RefCounted=original.new();reference.configure(built.world,changed,b.geometry,b.permission)
			check("door child does not inherit body proofs",child.body_cache.is_empty())
			for p:Dictionary in child.use_points(piece):check("changed leaf standing/blocker equals original",Data.json_equal(child.standing_point(p),reference.standing_point(p)))
			break
		check("query-only checks leave full authority untouched",Data.json_equal(before,rt.capture_checkpoint()))
		rows.append({"input":input,"probes":probes,"points":points.size(),"differences":failures});rt.retire()
	var result:Dictionary={"checks":checks,"rows":rows,"scope":"Exact original space differential: natural normal20 and retained actual old-city input; varied reference heights/radius plus unknown and changed-door query fixture; no authority/renderer edits."}
	FileAccess.open(args[0]+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));print(JSON.stringify({"checks":checks.size(),"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"rows":rows.map(func(r:Dictionary)->Dictionary:return {"probes":r.probes,"differences":r.differences.size()})}));quit(0 if checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
