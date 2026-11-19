extends "res://tests/integration/run_resident_life.gd"
## Actual generated actors, persisted public entrances/roads and B door steps.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
var observations:Array=[]

func run()->void:
	host=Client.new()
	for seed_value:int in [713,2026]:
		var generated:Dictionary=Assembly.prepare(Assembly.generate(seed_value,Building.generation_profiles()))
		check("generated observation opening "+str(seed_value),generated.ok,generated.get("reason"))
		if not generated.ok or not mount(generated.capture):continue
		var baseline:Dictionary=runtime.capture_checkpoint()
		var neighbor:Dictionary=runtime.actor("village-resident")
		check("new opening familiar person is genuinely outdoors near home "+str(seed_value),neighbor.regionId=="RH-HOME" and neighbor.get("buildingId")==null and Geometry.point(neighbor).distance_to(Geometry.point(runtime.actor("player")))>=2.2 and Geometry.point(neighbor).distance_to(Geometry.point(runtime.actor("player")))<=14,Geometry.location(neighbor))
		check("new opening familiar person is in B actual LOS "+str(seed_value),"village-resident" in runtime.actor_presentation().visible_actor_ids)
		var outside:Dictionary={"village-resident":0,"repair-resident":0}
		var visible:Dictionary={"village-resident":0,"repair-resident":0}
		var travelled:Dictionary={"village-resident":0.0,"repair-resident":0.0}
		var bad_steps:Array=[];var tracks:Array=[]
		for i:int in 750:
			var before:Dictionary={}
			for id:String in outside:before[id]=Geometry.point(runtime.actor(id))
			runtime.tick(0.1)
			for id:String in outside:
				var a:Dictionary=runtime.actor(id);var delta:Vector3=Geometry.point(a)-before[id]
				travelled[id]+=Vector2(delta.x,delta.z).length()
				if Vector2(delta.x,delta.z).length()>Movement.WALK_SPEED*0.1+0.001 or absf(delta.y)>0.501:bad_steps.append({"id":id,"at":Geometry.location(a)})
				if a.get("buildingId")==null:outside[id]+=1
			if i%10==0:
				var projection:Dictionary=runtime.actor_presentation()
				for id:String in outside:
					if id in projection.visible_actor_ids:visible[id]+=1
			if i%50==0:
				var sample:Dictionary={"time":runtime.clock()}
				for id:String in outside:sample[id]=runtime.actor(id)
				tracks.append(sample)
		for id:String in outside:
			check("unjoined actor physically exits to public entrance/road "+str(seed_value)+" "+id,int(outside[id])>10 and float(travelled[id])>3,{"outside_ticks":outside[id],"travelled_metres":travelled[id],"actor":runtime.actor(id)})
			check("outside activity grants no recruitment supply or skills "+str(seed_value)+" "+id,not runtime.actor(id).relationship.member and not runtime.actor(id).relationship.consent and runtime.actor(id).pack.is_empty() and runtime.actor(id).skills==baseline.facts.actors.filter(func(a:Dictionary)->bool:return a.id==id)[0].skills)
		check("all outdoor steps remain real half-metre terrain steps "+str(seed_value),bad_steps.is_empty(),bad_steps)
		check("outdoor activity never refills or debits untouched shared stock "+str(seed_value),Data.json_equal(baseline.facts.stocks,runtime.facts().stocks))
		observations.append({"seed":seed_value,"initial_actors":baseline.facts.actors,"outside_ticks":outside,"visible_from_original_player_samples":visible,"tracks":tracks})
	finish()

func finish()->void:
	var output:String=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var report:Dictionary={"scope":"two real unmodified generated openings; physical unjoined public activity and true LOS visibility observations, not OS/animation/app acceptance","checks":checks,"observations":observations,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}))
	if host!=null:host.free()
	quit(1 if report.failed else 0)
