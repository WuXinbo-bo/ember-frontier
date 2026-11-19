extends "res://tests/modules/normal_module_lifecycle.gd"
## One real finite home from original20 normal53. No terrain/actor/inventory edits.
func choose_site(rt:RefCounted,id:String,hammer:String)->Dictionary:
	for z:int in range(8,57,2):
		for x:int in range(12,57,2):
			var height:Variant=rt.world.surface_height(x,z)
			if height==null:continue
			for q:int in [0,1]:
				var payload:Dictionary={"definition_id":"r34.module.home_small_porch_v1","position":{"x":float(x),"y":height,"z":float(z),"regionId":"RH-HOME"},"quarter_turn":q,"source_id":"pack:player","tool_id":hammer}
				var preview:Dictionary=rt._services.modules.preview({"kind":"module.plan","actor_id":"player","target_id":id,"payload":payload})
				if not preview.ok:continue
				for port:Dictionary in preview.ports:
					if port.purpose!="service":continue
					var route:Dictionary=rt._services.actions.route("player",Geometry.location(rt.actor("player")),port.location)
					if route.ok:return {"payload":payload,"port":port.location}
	return {}
func run()->void:
	var args:=OS.get_cmdline_user_args();outdir=args[0];source_path=args[1];DirAccess.make_dir_recursive_absolute(outdir)
	var decoded:=Store.decode(FileAccess.get_file_as_string(source_path));var native:=Native.new();live=native._assemble(decoded.capture) if decoded.ok else decoded;native.free()
	check("unchanged original20 actual normal53 input mounts",FileAccess.get_sha256(source_path)=="968d950768146a1683f73900be469d14c982163bd58ca31ba008d795e2cc9ea5" and live.get("ok",false),live.get("reason"))
	if not live.get("ok",false):return finish()
	var rt:RefCounted=live.runtime;var hammer:="r34:generated:RH-HOME:woodwork:tool:hammer";var id:="B:architecture:normal-home"
	var site:=choose_site(rt,id,hammer)
	check("original unmodified land offers complete seven-metre home site",not site.is_empty(),site)
	if site.is_empty():return finish()
	var before:Dictionary=rt.capture_checkpoint();var denied:=send(rt,"module.plan",id,site.payload)
	check("insufficient original materials atomically refuse real home plan",not denied.ok and denied.code=="MODULE_MATERIALS" and Data.json_equal(before.facts,rt.capture_checkpoint().facts) and Data.json_equal(before.world,rt.capture_checkpoint().world),denied.get("code"))
	var paused:=send(rt,"factory.pause","r34:normal-built-woodshop")
	check("finite funding deliberately pauses old empty machine",paused.ok)
	if not paused.ok or not dismantle("r34:normal-built-woodshop",hammer,"finite-empty-machine-reclamation"):return finish()
	if not take_source(rt,"r34:normal-built-warehouse:stock:storage",{"timber":8}):return finish()
	if not care(rt,80):return finish()
	var arrived:=walk(rt,site.port);check("real player walks to home service construction face",arrived.get("ok",false),arrived.get("reason"))
	if not arrived.get("ok",false):return finish()
	var pack:Dictionary=rt.actor("player").pack.duplicate(true);var planned:=send(rt,"module.plan",id,site.payload)
	check("home plan reserves existing finite24timber8scrap and empty buffers",planned.ok and Data.json_equal(pack,rt.actor("player").pack) and rt._services.production.reserved("pack:player","timber")==24,planned.get("reason"))
	if not planned.ok:return finish()
	for i:int in 20:rt.tick(0.1)
	var project:Dictionary=rt._services.modules.state().projects.filter(func(p:Dictionary)->bool:return p.module_id==id)[0];var progress_before:float=project.progress_seconds
	var cancel:=send(rt,"module.cancel",id)
	check("real hammer partial work cancels without material grant or geometry construction",cancel.ok and progress_before>0 and progress_before<40 and rt._services.modules.instance(id).status=="planned" and Data.json_equal(pack,rt.actor("player").pack))
	if not cold("actual-home-cancelled"):return finish()
	rt=live.runtime;var resume:=send(rt,"module.work",id);var done:Dictionary=progress(rt,600) if resume.ok else {}
	var home:Dictionary=rt._services.modules.instance(id)
	check("same project resumes pays once and assembles actual new geometry",resume.ok and done.get("finished",false) and home.status=="operational" and home.geometry_version=="r34.module.home_small_porch_v1.geometry-v1" and float(pack.timber)-float(rt.actor("player").pack.timber)==24 and float(pack.scrap)-float(rt.actor("player").pack.scrap)==8,done)
	if home.status!="operational":return finish()
	var housing:Dictionary=rt._services.modules.housing_projection("player");var row:Dictionary=housing.homes.filter(func(h:Dictionary)->bool:return h.id==id)[0]
	check("real built home exposes design2 only without beds or automatic actors",row.capacity==2 and row.usable and rt.facts().actors.size()==3 and not row.has("occupied") and not row.has("free"),row)
	for port:Dictionary in ModuleShape.ports(home,Modules.definition(home.definition_id)):
		var walked:=walk(rt,port.location);check("actual built home reaches service "+str(port.id),walked.get("ok",false),walked.get("reason"))
	var moved:=walk(rt,site.port)
	if not moved.get("ok",false):return finish()
	var supply:String=home.stock_refs.supplies;var food:float=rt.actor("player").pack.get("food",0)
	if food>=1:
		var put:=send(rt,"deposit",supply,{"items":{"food":1}});var taken:=send(rt,"take",supply,{"items":{"food":1}}) if put.ok else {}
		check("home service transports actual finite food with no free supply",put.ok and taken.get("ok",false) and rt.stock(supply).items.get("food",0)==0 and rt.actor("player").pack.get("food",0)==food,{"put":put,"take":taken})
	else:check("normal route retains finite food for service evidence",false)
	if not cold("actual-paid-home"):return finish()
	rt=live.runtime;check("cold home retains real capacity/module members and population",rt._services.modules.housing_projection("player").homes.any(func(h:Dictionary)->bool:return h.id==id and h.capacity==2 and h.usable) and rt.facts().actors.size()==3)
	note(rt,"real finite paid home; old machine intentionally reclaimed",rt._services.modules.instance(id));finish()
func finish()->void:
	if live.get("ok",false):save_scene(live.runtime,"actual-home-normal-final")
	var result:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"source":source_path,"journey":journey,"commands":commands,"live_roundtrip":live_roundtrip,"scope":"Original20 normal53 unchanged. Real finite material plan denial, old empty machine reclaimed for funding, actual walk/hammer/cancel/canonical cold/resume/payment/service/cold. Not natural new placement/content, machine restoration, NPC housing allocation, damage, renderer/PCK/VA/FPS."}
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	if live.get("ok",false):live.runtime.retire()
	quit(0 if result.failed==0 else 1)
