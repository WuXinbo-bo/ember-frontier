extends "res://tests/buildings/door_cost_suite.gd"
## Frozen complete pre-optimization service vs production, same actual source.
const ReferenceBuilding=preload("res://tests/buildings/cold_reference/building_service.gd")

func reference_building()->RefCounted:return ReferenceBuilding.new()

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var raw:=FileAccess.get_file_as_string(args[0]);var decoded:=Codec.decode_checkpoint(raw)
	expect("original v5 source decodes",decoded.ok)
	if not decoded.ok:quit(1);return
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	expect("original source tools migrate",imported.ok)
	var all_rows:Array=[]
	for iteration in 2:
		for side in 2:
			for cold:bool in [false,true]:
				var world:=World.new();world.load_snapshot(imported.world)
				var services:Dictionary={};var runtimes:Dictionary={}
				for name in ["reference","production"]:
					var b:RefCounted=reference_building() if name=="reference" else Building.new()
					var r:=Runtime.new();services[name]=b;runtimes[name]=r
					expect("complete actual runtime configures %d/%d/%s/%s"%[iteration,side,cold,name],r.configure({"world":world,"facts":imported.facts,"services":{"buildings":b,"actions":Actions.new(),"production":Production.new()}}).ok)
				var fixture:RefCounted=services.reference.space()
				var door:Dictionary=fixture.by_id[DOOR]
				var stance:Dictionary=fixture.standing_point(fixture.use_points(door)[side])
				expect("actual supported side %d/%d/%s"%[iteration,side,cold],not stance.is_empty())
				var staged:Dictionary=imported.facts.duplicate(true)
				for a:Dictionary in staged.actors:
					if a.id=="player":a.merge(stance,true);a.intent=null
				var original:=world.snapshot();var samples:Array=[]
				for n in 8:
					var moved:Array=[]
					for a:Dictionary in staged.actors:
						for delta:Vector2 in [Vector2(0.007,0),Vector2(-0.007,0),Vector2(0,0.007),Vector2(0,-0.007)]:
							var desired:=Geometry.location(a);var sign:float=1 if n%2 else -1
							desired.x=float(desired.x)+delta.x*sign;desired.z=float(desired.z)+delta.y*sign
							var feet:Dictionary=fixture.standing_point(desired)
							if not feet.is_empty() and absf(float(feet.y)-float(a.y))<0.025 and feet.get("storeyId")==a.get("storeyId") and feet.get("buildingId")==a.get("buildingId"):
								a.merge(feet,true);moved.append(a.id);break
					var results:Dictionary={};var times:Dictionary={}
					for name in (["reference","production"] if (iteration+n)%2==0 else ["production","reference"]):
						var b:RefCounted=services[name]
						if cold or n==0:
							var r:RefCounted=runtimes[name]
							expect("cold service configures %d/%d/%s/%d/%s"%[iteration,side,cold,n,name],r.configure({"world":world,"facts":imported.facts,"services":{"buildings":b,"actions":Actions.new(),"production":Production.new()}}).ok)
						var t:=Time.get_ticks_usec()
						results[name]=b.prepare_door({"actor_id":"player","kind":"door","target_id":DOOR,"payload":{"operation":"close" if door.door.open else "open"}},{},staged)
						times[name]=float(Time.get_ticks_usec()-t)/1000.0
					expect("complete cold/moving response equals frozen original %d/%d/%s/%d"%[iteration,side,cold,n],results.reference==results.production and results.production.ok and moved.size()==5,{"times":times,"moved":moved,"reason":results.production.get("reason")})
					samples.append({"index":n,"first_variant":"reference" if (iteration+n)%2==0 else "production","ms":times,"moved":moved,"result_sha256":JSON.stringify(results.production,"",true,true).sha256_text()})
				expect("world and all runtime facts remain authoritative %d/%d/%s"%[iteration,side,cold],world.snapshot()==original and runtimes.reference.facts()==imported.facts and runtimes.production.facts()==imported.facts)
				all_rows.append({"iteration":iteration,"side":side,"cold_each_sample":cold,"samples":samples})
	print(JSON.stringify({"ok":not failed,"checks":checks,"source_sha256":raw.sha256_text(),"door_id":DOOR,"groups":all_rows,"scope":"alternating same-process complete prepare_door CPU comparison; frozen service/space/navigation oracle; all five actors move; no FPS, official app or budget claim"}))
	quit(1 if failed else 0)
