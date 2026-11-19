extends "res://tests/modules/normal_module_lifecycle.gd"
## Resume the untouched real cancelled order; never regenerate a saved house.
## Prior normal04 established the finite funding route. This only validates
## the new construction output after the current kit has been finalized.
func run()->void:
	var args:=OS.get_cmdline_user_args();outdir=args[0];source_path=args[1];sequence=100000
	var decoded:=Store.decode(FileAccess.get_file_as_string(source_path));var native:=Native.new()
	live=native._assemble(decoded.capture) if decoded.ok else decoded;native.free()
	check("exact real normal04 cancelled order mounts unchanged",FileAccess.get_sha256(source_path)=="35f7b05b63ad6571ba4e7033cbbff230b66540ceca29286efb47f718cd20c4b6" and live.get("ok",false),live.get("reason"))
	if not live.get("ok",false):return finish()
	var rt:RefCounted=live.runtime;var id:="B:architecture:normal-home"
	var modules:RefCounted=rt._services.modules;var old:Dictionary=modules.instance(id)
	var definition:Dictionary=Modules.definition(old.definition_id)
	var project:Dictionary=modules.state().projects.filter(func(p:Dictionary)->bool:return p.id==old.project_id)[0]
	check("original order remains cancelled partially worked and unpaid",old.status=="planned" and old.members.size()==1 and old.members[0].id==id and old.get("paid_cost",{}).is_empty() and project.status=="cancelled" and float(project.progress_seconds)>0 and float(project.progress_seconds)<40)
	var pack:Dictionary=rt.actor("player").pack.duplicate(true);var prior_world:Dictionary=live.world.snapshot()
	var resumed:=send(rt,"module.work",id);var done:=progress(rt,600) if resumed.ok else {}
	var built:Dictionary=modules.instance(id)
	check("same project finishes real remaining labor and pays once",resumed.ok and done.get("finished",false) and built.status=="operational" and built.project_id==project.id and Data.json_equal(built.paid_cost,definition.build_cost) and float(pack.timber)-float(rt.actor("player").pack.timber)==24 and float(pack.scrap)-float(rt.actor("player").pack.scrap)==8,done)
	if built.status!="operational":return finish()
	var expected:Array=ModuleShape.entities(built,definition);var matching:bool=expected.size()+1==built.members.size()
	var recipes:Array=[]
	for entity:Dictionary in expected:
		var actual:Dictionary=live.world.entity(entity.id)
		matching=matching and not actual.is_empty() and Data.json_equal(actual.data.module_part,entity.data.module_part) and Data.json_equal(actual.bounds,entity.bounds)
		if actual.get("data",{}).get("module_part",{}).has("architecture_detail"):recipes.append(actual.data.module_part.architecture_detail.kind)
	check("new paid output contains every current authoritative part and recipe",matching and recipes.has("lean_roof") and recipes.has("gable_roof"),{"members":built.members.size(),"recipes":recipes})
	var untouched:bool=true
	for entity_id:String in prior_world.entities:
		if entity_id==id or entity_id.begins_with(id+":"):continue
		untouched=untouched and Data.json_equal(prior_world.entities[entity_id],live.world.entity(entity_id))
	check("all pre-existing world entities retain exact bytes and IDs",untouched)
	check("same three actors and housing design2 remain",rt.facts().actors.size()==3 and modules.housing_projection("player").homes.any(func(h:Dictionary)->bool:return h.id==id and h.usable and h.capacity==2))
	for port:Dictionary in ModuleShape.ports(built,definition):
		var moved:=walk(rt,port.location)
		check("real revised building service route "+str(port.id),moved.get("ok",false),moved.get("reason"))
	if not cold("actual-paid-current-geometry"):return finish()
	note(live.runtime,"resumed original finite order produces current geometry without rewriting old houses",built)
	finish()

func finish()->void:
	if live.get("ok",false):save_scene(live.runtime,"actual-current-home-final")
	var result:Dictionary={"checks":checks,"journey":journey,"commands":commands,"source":source_path,"live_roundtrip":live_roundtrip,"scope":"Exact normal04 real cancelled order resumed with original finite materials/tool/remaining labor; newly constructed geometry only; old entities/IDs preserved; canonical cold and actual service routes. No grants/teleports/capture edits or retroactive member regeneration; not OS/PCK/VA/FPS."}
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	var ok:bool=not checks.is_empty() and checks.all(func(c:Dictionary)->bool:return c.ok)
	if live.get("ok",false):live.runtime.retire()
	quit(0 if ok else 1)
