extends "res://tests/world/factory_joint.gd"
const Entrance=preload("res://scripts/world/factory_story_entrances.gd")
var rows:Array=[]
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();var report:String=args[0]
	var profiles:Array=Modules.generation_profiles();var lock:Dictionary=Contract.fresh(profiles,7,1)
	for seed:int in [713,2026,17,999]:
		var generated:Dictionary=Factory.generate(seed,profiles,lock.contract)
		var plan:Dictionary=generated.extensions["generation:RH-HOME"]
		var candidate:Dictionary=Entrance.prepare(plan)
		check("seed%d finite helper candidate"%seed,candidate.ok,candidate)
		if not candidate.ok:continue
		var site:Dictionary=candidate.entrances[0];plan.story_entrances=candidate.entrances
		var draft:Dictionary={"ok":true,"plan":plan,"chunks":generated.chunks}
		var applied:Dictionary=Entrance.apply(draft)
		check("seed%d all original air and exact base preflight"%seed,applied.ok,applied.get("reason"))
		if not applied.ok:continue
		# Deliberately isolated spatial fixture, not a normal generated world.
		var made:Dictionary=Assembly.prepare(generated);var native:=Native.new()
		var built:Dictionary=native._assemble(made.capture) if made.get("ok",false) else made;native.free()
		check("seed%d fixture full Native geometry composes"%seed,built.get("ok",false),built.get("reason"))
		if not built.get("ok",false):continue
		var q:RefCounted=built.services.buildings.current_space()
		var chain:Array=[site.approach_before]+site.bypass_points+[site.approach_after]
		var valid:bool=true;var edges:Array=[]
		for i:int in chain.size()-1:
			var a:Dictionary=chain[i];var b:Dictionary=chain[i+1]
			var moved:Dictionary=q.walk("player",a,b)
			edges.append({"from":a,"to":b,"receipt":moved});valid=valid and moved.ok
		check("seed%d actual full-body bypass without clearing fixture"%seed,valid,edges)
		check("seed%d short segment blocked by exact stone body"%seed,not q.walk("player",site.approach_before,site.approach_after).ok)
		var mouths:Array=plan.parcels.filter(func(p:Dictionary)->bool:return p.site_id=="woodwork")[0].entrance_ports
		var all_standing:bool=true
		for mouth:Dictionary in mouths+plan.story_sites[0].service_points:
			var at:Dictionary=mouth.position.duplicate(true);at.merge({"regionId":"RH-HOME","buildingId":null,"storeyId":null},true)
			all_standing=all_standing and not q.standing_point(at).is_empty()
		check("seed%d original manual mouths and all old-frame mouths remain standing"%seed,all_standing)
		rows.append({"seed":seed,"site":site,"edges":edges});built.runtime.retire()
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":rows,"scope":"detached helper isolated geometry fixture only; not command normal route/package/OS"},"\t",true,true));quit(1 if failed else 0)
