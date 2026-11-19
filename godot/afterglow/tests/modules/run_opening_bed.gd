extends "res://tests/modules/run_architecture_lifecycle.gd"
func idle(rt:RefCounted,limit:int=200)->void:
	for i:int in limit:
		rt.tick(.1)
		if rt.actor("player").get("intent")==null:break
func run()->void:
	out=OS.get_cmdline_user_args()[0]
	for seed:int in [713,2026]:
		var opened:=Assembly.prepare(Generator.generate(seed,Catalog.profiles_for_content(12),preload("res://scripts/world/factory_generation_contract.gd").fresh(Catalog.profiles_for_content(12),12,1).contract))
		check("exact current12 generated opening "+str(seed),opened.ok,opened.get("reason"))
		if not opened.ok:continue
		var live:=mount(opened.capture);check("actual Native current12 mount "+str(seed),live.get("ok",false),live.get("reason"))
		if not live.get("ok",false):continue
		var rt:RefCounted=live.runtime;var modules:RefCounted=live.services.modules
		var home:Dictionary=modules.instance("r34:generated:RH-HOME:home");var bed_id:String=str(home.id)+":bed:opening:v1";var bed:Dictionary=live.world.entity(bed_id)
		check("only explicit source attachment creates unprepared owned actual bed "+str(seed),home.config.get("opening_bed_v1")==1 and bed.get("data",{}).get("prepared")==false and bed.data.get("owner")=="home-residents",bed)
		if bed.is_empty():rt.retire();continue
		var linen:=send(rt,"take",str(home.stock_refs.values()[0]),{"source_id":str(home.stock_refs.values()[0]),"output_id":"pack:player","items":{"cloth":2}})
		check("take finite original home linen at actual spawn "+str(seed),linen.ok,linen)
		var saved:=Store.encode(rt.capture_checkpoint());if saved.ok:FileAccess.open(out+"/actual-new12-unprepared-"+str(seed)+".native.json",FileAccess.WRITE).store_string(saved.text)
		var before:Dictionary=rt.capture_checkpoint();var no_rest:=send(rt,"rest",bed_id)
		check("unprepared bed rejects rest with no free furnishing "+str(seed),not no_rest.ok and Data.json_equal(before,rt.capture_checkpoint()),no_rest)
		var approach:Dictionary=bed.data.module_bed.approach;var q:RefCounted=modules.context.spatial.current_space()
		check("real bed frame supported by unchanged terrain "+str(seed),q.terrain_supports(home.region,AABB(Vector3(G.aabb(bed.bounds).position.x,home.position.y,G.aabb(bed.bounds).position.z),Vector3(G.aabb(bed.bounds).size.x,0,G.aabb(bed.bounds).size.z))),bed.bounds)
		sequence+=1;var walk:Dictionary=rt.command({"kind":"walk","actor_id":"player","command_id":"B:opening-bed-walk:"+str(sequence),"destination":approach,"payload":{}});idle(rt)
		check("actual original spawn walks to real porch approach "+str(seed),walk.ok and G.point(G.location(rt.actor("player"))).distance_to(G.point(approach))<.1,{"walk":walk,"at":G.location(rt.actor("player")),"approach":approach,"activity":rt.actor("player").activity})
		var cloth:float=float(rt.actor("player").pack.get("cloth",0));var prepared:=send(rt,"prepare_bed",bed_id,{"source_id":"pack:player"})
		check("real finite starting cloth admits original care "+str(seed),prepared.ok and cloth>=2,prepared)
		if not prepared.ok:rt.retire();continue
		for i:int in 20:rt.tick(.1)
		var pause:=send(rt,"held","",{"held":false});var elapsed:float=float(rt.actor("player").intent.elapsed)
		for i:int in 3:rt.tick(.1)
		check("preparation standard hold stops labor and material "+str(seed),pause.ok and rt.actor("player").intent.elapsed==elapsed and rt.actor("player").pack.cloth==cloth)
		var encoded:=Store.encode(rt.capture_checkpoint());var decoded:=Store.decode(encoded.text) if encoded.ok else encoded;var cold:=mount(decoded.capture) if decoded.ok else decoded
		check("actual partial care full JSON cold "+str(seed),cold.get("ok",false),cold.get("reason"))
		if not cold.get("ok",false):rt.retire();continue
		rt.retire();live=cold;rt=live.runtime;modules=live.services.modules
		send(rt,"held","",{"held":true});idle(rt)
		check("preparation pays exactly two real cloth after six labor seconds "+str(seed),rt.actor("player").get("intent")==null and rt.actor("player").pack.cloth==cloth-2 and live.world.entity(bed_id).data.prepared,{"actor":rt.actor("player"),"bed":live.world.entity(bed_id)})
		var resting:=send(rt,"rest",bed_id);check("same actual bed accepts original rest and occupancy "+str(seed),resting.ok and Draft.find(modules.housing_projection("player").homes,str(home.id)).beds.any(func(b:Dictionary)->bool:return b.bed_id==bed_id and b.occupied),resting)
		var demolished:=send(rt,"module.dismantle",home.id,{"source_id":"pack:player","tool_id":"missing:bedtest"});check("actual occupied bed vetoes teardown "+str(seed),not demolished.ok and demolished.code=="ACTOR_BUSY" and not preload("res://scripts/modules/module_projects.gd").can_dismantle(modules,Draft.new(modules.context),modules.instance(str(home.id))).ok,demolished)
		var final_save:=Store.encode(rt.capture_checkpoint());if final_save.ok:FileAccess.open(out+"/actual-new12-prepared-rest-"+str(seed)+".native.json",FileAccess.WRITE).store_string(final_save.text)
		rt.retire()
	finish()
func finish()->void:
	var report:Dictionary={"checks":checks,"scope":"Unchanged actual generated content12 two seeds, original starting spawn/stocks/cloth, real walking/care/rest/fullJSONcold. Source attachment only, no grants/teleport/terrain rewrite. Not package/OS/VA/FPS."}
	FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify(report));quit(0 if not checks.is_empty() and checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
