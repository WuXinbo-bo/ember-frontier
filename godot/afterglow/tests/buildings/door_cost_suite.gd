extends "res://tests/buildings/legacy_suite.gd"
## Actual preserved city/checkpoint, full prepare_door, moving all five actors.
## Explicit supported stance fixture only; no UI, preview, FPS or budget pass.
const DOOR := "world:713:region:0:0:convenience-store:piece:34"

func new_building()->RefCounted:return Building.new()
func sample_metrics(_building:RefCounted)->Dictionary:return {}

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var raw:=FileAccess.get_file_as_string(args[0])
	var decoded:=Codec.decode_checkpoint(raw)
	expect("preserved ordinary v5 decodes",decoded.ok)
	if not decoded.ok:quit(1);return
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	expect("ordinary source tools migrate without regenerating world",imported.ok)
	var groups:Array=[]
	for side in 2:
		for cold:bool in [false,true]:
			var world:=World.new();world.load_snapshot(imported.world)
			var building:RefCounted=new_building();var runtime:=Runtime.new()
			var services:Dictionary={"buildings":building,"actions":Actions.new(),"production":Production.new()}
			expect("same complete runtime configures side %d cold %s"%[side,cold],runtime.configure({"world":world,"facts":imported.facts,"services":services}).ok)
			# This separate read-only query prepares explicit fixture positions;
			# reset the service below before timing the actual cold entry point.
			var fixture:RefCounted=building.space()
			var door:Dictionary=fixture.by_id.get(DOOR,{})
			var points:Array=fixture.use_points(door)
			var stance:Dictionary=fixture.standing_point(points[side]) if points.size()>side else {}
			expect("actual ordinary door side has supported stance %d cold %s"%[side,cold],not stance.is_empty())
			if stance.is_empty():continue
			var staged:Dictionary=runtime.facts()
			for a:Dictionary in staged.actors:
				if a.id=="player":a.merge(stance,true);a.intent=null
			var before_world:=world.snapshot();var before_facts:=runtime.facts()
			var samples:Array=[]
			for sample in 8:
				if cold or sample==0:
					expect("fresh service caches configure %d/%s/%d"%[side,cold,sample],runtime.configure({"world":world,"facts":imported.facts,"services":services}).ok)
				var moved:Array=[]
				for a:Dictionary in staged.actors:
					for delta:Vector2 in [Vector2(0.007,0),Vector2(-0.007,0),Vector2(0,0.007),Vector2(0,-0.007)]:
						var desired:=Geometry.location(a)
						var direction:float=1.0 if sample%2 else -1.0
						desired.x=float(desired.x)+delta.x*direction;desired.z=float(desired.z)+delta.y*direction
						var feet:Dictionary=fixture.standing_point(desired)
						if not feet.is_empty() and absf(float(feet.y)-float(a.y))<0.025 and feet.get("storeyId")==a.get("storeyId") and feet.get("buildingId")==a.get("buildingId"):
							a.merge(feet,true);moved.append(a.id);break
				sample_metrics(building) # Discard untimed fixture/configuration hooks.
				var started:=Time.get_ticks_usec()
				var result:Dictionary=building.prepare_door({"actor_id":"player","kind":"door","target_id":DOOR,"payload":{"operation":"close" if door.door.open else "open"}},{},staged)
				var elapsed_ms:float=float(Time.get_ticks_usec()-started)/1000.0
				var row:Dictionary={"index":sample,"ms":elapsed_ms,"ok":result.ok,"reason":result.get("reason"),"moved":moved}
				var meters:=sample_metrics(building)
				if not meters.is_empty():row.diagnostic=meters
				samples.append(row)
				expect("full door safety succeeds with all five actors moved %d/%s/%d"%[side,cold,sample],result.ok and staged.actors.size()==5 and moved.size()==5,row)
			expect("preflight preserves complete authoritative source %d/%s"%[side,cold],world.snapshot()==before_world and runtime.facts()==before_facts)
			var times:Array=[]
			for row:Dictionary in samples:times.append(float(row.ms))
			times.sort()
			groups.append({"side":side,"fresh_services_each_sample":cold,"first_ms":samples[0].ms,"median_ms":(float(times[3])+float(times[4]))/2,"max_ms":times[-1],"samples":samples})
	print(JSON.stringify({"ok":not failed,"checks":checks,"scope":"B native headless full door CPU diagnostic; supported stance fixture, exact movement of all five source actors; not browser FPS, official app response or budget acceptance","source_sha256":raw.sha256_text(),"door_id":DOOR,"groups":groups}))
	quit(1 if failed else 0)
