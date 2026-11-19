extends "res://tests/gameplay/run_compact_production17.gd"

const Families18=preload("res://scripts/modules/village_family_catalog.gd")
const Stage18=preload("res://scripts/modules/village_building_stage.gd")
const Catalog18=preload("res://scripts/modules/module_catalog.gd")
const Geometry18=preload("res://scripts/modules/module_geometry.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Village18=preload("res://scripts/runtime/village_progression.gd")
const ActionDraft18=preload("res://scripts/actions/domain_draft.gd")
const Regional19=preload("res://scripts/modules/village_regional_catalog.gd")
const Home18="r34:generated:RH-HOME:home"

func run()->void:
	wall_start15=Time.get_ticks_msec()
	outdir=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	check("catalog contracts validate",Catalog18.validate().ok)
	for spec:Array in Families18.specs():
		var previous:Array=[]
		for level:int in range(1,spec[1].size()+1):
			var d:=Catalog18.definition(Families18.id_for(spec[0],level))
			var parts:=Geometry18.parts(d)
			var box:=G.aabb(d.footprint).grow(.001)
			var outside:Array=parts.filter(func(p:Dictionary)->bool:
				var size:=G.point(p.size);return not box.encloses(AABB(G.point(p.center)-size*.5,size)))
			check(d.id+" distinct real geometry inside its footprint",not parts.is_empty() and parts!=previous and outside.is_empty(),outside.map(func(p:Dictionary)->String:return p.id))
			previous=parts
			var clear:bool=true
			for turn:int in 4:
				var v:Dictionary={"position":{"x":0,"y":0,"z":0},"quarter_turn":turn,"region":"RH-HOME"}
				var occupied:=Geometry18.transform_box(v,G.aabb(d.footprint))
				for port:Dictionary in Geometry18.ports(v,d):
					var at:=G.point(port.location)
					clear=clear and not occupied.intersects(AABB(at-Vector3(.4,0,.4),Vector3(.8,1.8,.8)))
			check(d.id+" exposes clear standing space in four rotations",clear)
	for source:String in Regional19.VARIANTS:
		var original:=Catalog18.definition(source)
		var rebuilt:=Catalog18.definition(Regional19.id_for(source,19))
		var parts:=Geometry18.parts(rebuilt);var box:=G.aabb(rebuilt.footprint).grow(.001)
		check(rebuilt.id+" uses new bounded geometry with the same service ports",rebuilt.ports==original.ports and not parts.is_empty() and parts!=Geometry18.parts(original) and parts.all(func(p:Dictionary)->bool:return box.encloses(AABB(G.point(p.center)-G.point(p.size)*.5,G.point(p.size)))))
	var profiles:Dictionary=Assembly.generation_profiles()
	check("historical content 18 never gains regional overlays",Assembly.generation_profiles(18).profiles.all(func(p:Dictionary)->bool:return not str(p.id).begins_with("r39.module.")))
	for seed:int in [713,42,907]:
		var generated:Dictionary=Assembly.generate(seed,profiles.profiles)
		check("v18 seed %d generates"%seed,generated.get("ok",true) and not generated.get("chunks",[]).is_empty(),generated.get("code"))
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("v18 opening prepares",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.ok:return finish()
	var opening:Dictionary=Profile15.prepare_opening(prepared.capture,"playtest")
	for actor:Dictionary in opening.facts.actors:
		if actor.id=="player":actor.pack.merge({"timber":108,"scrap":42,"cloth":8,"log":14,"tool_handle":1,"stone_m3":3,"r34:potato":2,"r34:water_bucket":1,"r34:salvaged_drive_unit":1},true)
	var host:=Native.new();var built:Dictionary=host._assemble(opening);host.free()
	check("v18 opens with its own saved content",built.get("ok",false),built.get("reason"))
	if not built.ok:return finish()
	var r:RefCounted=built.runtime;live15=r
	var m:RefCounted=r._services.modules
	var original_store:Dictionary=m.instance("r34:generated:RH-VILLAGE:store")
	var original_frame:Dictionary=m.instance("RH-HOME:woodshop-old-frame")
	var seed_bag:Dictionary=r.stock("r34:generated:RH-VILLAGE:store:regional-seed-bag:v1")
	check("regional store generates with its one finite seed stock",original_store.definition_id==Regional19.STORE and seed_bag.items.get("r34:potato_seed")==4 and not seed_bag.searched)
	check("regional home mounts with the new geometry",m.instance("r34:generated:RH-VILLAGE:neighbor").definition_id==Regional19.HOME)
	check("the heritage mill is registered damaged with no drive housing",original_frame.definition_id==Regional19.FRAME and original_frame.status=="damaged" and r.world.entity(original_frame.id+":part:fixed-power-housing").is_empty())
	var choice:Dictionary=r.factory_page_snapshot("player","factory_catalog").get("modules",{})
	check("catalog shows stage one and only base construction choices",choice.get("village_stage",{}).get("level")==1 and choice.get("build_definition_ids",[])==Families18.CHOICES,choice.get("village_stage"))
	var saw_id:=Families18.id_for("sawmill",1)
	check("shared build preview refuses stage two building",preview18(r,saw_id).get("code")=="MODULE_VILLAGE_STAGE")
	check("shared build preview refuses direct advanced placement",preview18(r,Families18.id_for("warehouse",2)).get("code")=="MODULE_NOT_IN_BUILD_MENU")
	for id:String in [Warehouse17,Home18]:
		if not care(r,80):return finish()
		var started:Dictionary=send(r,"module.restore",id)
		check("paid restoration starts "+id,started.ok,started.get("reason"))
		if not started.ok:return finish()
		var completed:Dictionary=progress(r,1000)
		check("real restoration finishes "+id,completed.finished and m.instance(id).get("restoration",{}).get("completed",false),completed)
		if not completed.finished:return finish()
	for step:int in 20:
		if Stage18.read(r.world).level==2:break
		r.tick(.1)
	check("both repairs reach production street",Stage18.read(r.world).level==2,Stage18.read(r.world))
	var warehouse:Dictionary=m.instance(Warehouse17);var dest:String=warehouse.stock_refs.storage
	var hammer:String=opening.source.opening_configuration.tools.hammer
	var yard:=build17(r,Families18.id_for("stockyard",1),"compact17:test:yard",30,21,hammer)
	var saw:=build17(r,saw_id,"compact17:test:saw",35,21,hammer)
	if yard.is_empty() or saw.is_empty():return finish()
	if not near_stock(r,yard.stock_refs.storage):return finish()
	check("yard receives two physically delivered logs",send(r,"deposit",yard.stock_refs.storage,{"items":{"log":2}}).ok)
	if not near_stock(r,saw.stock_refs.fuel):return finish()
	check("separate fuel port accepts fuel",send(r,"deposit",saw.stock_refs.fuel,{"items":{"log":1}}).ok)
	if not transfer17(r,yard.stock_refs.storage,saw.stock_refs.input,"log",2):return finish()
	var order:Dictionary=send(r,"factory.configure",saw.id,{"recipe_id":"saw_timber","batches":-1})
	check("real mill accepts machine recipe",order.ok,order.get("reason"))
	if not order.ok:return finish()
	for step:int in 450:
		r.tick(.1)
		if r.stock(saw.stock_refs.output).items.get("timber",0)==8:break
	check("two batches consume real raw input and fuel",r.stock(saw.stock_refs.output).items.get("timber",0)==8 and r.stock(saw.stock_refs.input).items.get("log",0)==0 and r.stock(saw.stock_refs.fuel).items.get("log",0)==0)
	check("continuous order can be paused by the player",send(r,"factory.pause",saw.id).ok)
	if not transfer17(r,saw.stock_refs.output,dest,"timber",8):return finish()
	if not care(r,70):return finish()
	var next:=Families18.id_for("warehouse",2)
	var upgrade:Dictionary=send(r,"module.upgrade",Warehouse17,{"definition_id":next,"source_id":"pack:player","tool_id":hammer})
	check("paid upgrade starts with occupied compatible storage",upgrade.ok,upgrade.get("reason"))
	if not upgrade.ok:return finish()
	var work:Dictionary=progress(r,1000)
	var saved:Dictionary=m.instance(Warehouse17)
	check("upgrade retains ID, repair history, slot and the eight boards",work.finished and saved.definition_id==next and saved.position==warehouse.position and saved.restoration.completed and saved.stock_refs.storage==dest and r.stock(dest).items.get("timber",0)==8,saved.definition_id)
	check("stage three still requires radio transmission",Stage18.read(r.world).level==2 and "修好电台并发报" in Stage18.read(r.world).missing)
	var visible_goods:Dictionary=m.visual_projection("player",Warehouse17).instances[0].visuals.buffers.filter(func(row:Dictionary)->bool:return row.item_id=="timber")[0]
	check("real boards have a supported, unobstructed outdoor display",visible_goods.actual==8 and visible_goods.visual_available,visible_goods)
	if not water_test(r,hammer):return finish()
	if not kitchen_test(r,hammer) or not repeat_test(r,saw,dest):return finish()
	var encoded:Dictionary=Store.encode(r.capture_checkpoint())
	if encoded.ok:FileAccess.open(outdir+"/working-street.native.json",FileAccess.WRITE).store_string(encoded.text)
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	var cold:=Native.new();var loaded:Dictionary=cold._assemble(decoded.capture) if decoded.ok else decoded;cold.free()
	check("cold reload conserves the upgraded stock and repeated deliveries",loaded.get("ok",false) and loaded.runtime.stock(dest).items.get("timber",0)==16 and loaded.runtime._services.modules.instance(original_store.id).definition_id==Regional19.STORE,loaded.get("reason"))
	if loaded.get("ok",false):loaded.runtime.retire()
	finished15=work.finished and saved.definition_id==next and loaded.get("ok",false) and radio18(r,hammer) and repair_test(r,hammer) and heritage_test(r,original_frame,hammer)
	finish()

func preview18(r:RefCounted,definition:String)->Dictionary:
	return r._services.modules.preview({"actor_id":"player","target_id":"v18:test:preview","payload":{"definition_id":definition,"position":{"x":35,"z":21,"y":r.world.surface_height(35,21),"regionId":"RH-HOME"},"quarter_turn":0}})

func water_test(r:RefCounted,hammer:String)->bool:
	var station:=build17(r,Families18.id_for("water",1),"v18:test:water",30,27,hammer)
	if station.is_empty():return false
	var source:Dictionary=r.world.extension("generation:RH-HOME").ecology_sources[0]
	var wx:int=floori(float(source.location.x)*2);var wz:int=floori(float(source.location.z)*2)
	var zone:Dictionary=send(r,"zone.create",water15,{"spec":{"kind":"forage","region_id":"RH-HOME","bounds":{"x0":wx-2,"x1":wx+3,"z0":wz-2,"z1":wz+3},"policy":{"worker_ids":["player"]}}})
	check("original water source accepts a real work zone",zone.ok,zone.get("reason"))
	if not zone.ok:return false
	for draw:int in 2:
		if not labor15(r,water15,"draw_raw_water"):return false
	var before:Dictionary=r.actor("player").pack.duplicate(true)
	if not complete15(r,"craft",station.id,{"recipe_id":"r34:raw_boil_water_v2","source_id":"pack:player","output_id":"pack:player","tool_ids":[]}):return false
	var after:Dictionary=r.actor("player").pack
	var converted:bool=float(after.get("r34:raw_water",0))==float(before.get("r34:raw_water",0))-2 and float(after.get("water",0))>float(before.get("water",0))
	check("new station converts real raw water into potable water",converted)
	var output:String=station.stock_refs.output
	if not converted or not near_stock(r,output):return false
	var stored:Dictionary=send(r,"deposit",output,{"items":{"water":2}})
	check("treated water enters actual station inventory",stored.ok and r.stock(output).items.get("water",0)==2,stored.get("reason"))
	return stored.ok and r.world.extension("r34:gameplay").flags.get("village_clean_water",false)

func kitchen_test(r:RefCounted,hammer:String)->bool:
	var kitchen:=build17(r,Families18.id_for("kitchen",1),"v19:test:kitchen",35,27,hammer)
	if kitchen.is_empty():return false
	if not complete15(r,"craft",kitchen.id,{"recipe_id":"r34:cook_potato_v2","source_id":"pack:player","output_id":"pack:player","tool_ids":[]}):return false
	var output:String=kitchen.stock_refs.output
	if not near_stock(r,output):return false
	var stored:Dictionary=send(r,"deposit",output,{"items":{"r34:meal_simple":2}})
	var ok:bool=stored.ok and r.stock(output).items.get("r34:meal_simple",0)==2 and r.actor("player").pack.get("r34:potato",0)==0
	check("kitchen consumes real ingredients and stores two meals",ok,stored.get("reason"))
	return ok

func repeat_test(r:RefCounted,saw:Dictionary,destination:String)->bool:
	var old_ids:Array=r.world.extension("r34:logistics").tasks.map(func(t:Dictionary)->String:return t.id)
	var order:Dictionary=send(r,"logistics.create","",{"source_id":saw.stock_refs.output,"destination_id":destination,"items":{"timber":4},"repeat":true})
	check("continuous logistics can wait at an empty source",order.ok and r.stock(saw.stock_refs.output).items.get("timber",0)==0,order.get("reason"))
	if not order.ok:return false
	var id:String=r.world.extension("r34:logistics").tasks.filter(func(t:Dictionary)->bool:return not old_ids.has(t.id))[0].id
	if not near_stock(r,saw.stock_refs.fuel) or not send(r,"deposit",saw.stock_refs.fuel,{"items":{"log":1}}).ok:return false
	if not near_stock(r,saw.stock_refs.input) or not send(r,"deposit",saw.stock_refs.input,{"items":{"log":2}}).ok:return false
	var resumed:Dictionary=send(r,"factory.resume",saw.id)
	if not resumed.ok:return false
	for step:int in 1600:
		r.tick(.1)
		if r.stock(destination).items.get("timber",0)==16:break
	var tasks:Array=r.world.extension("r34:logistics").tasks
	var row:Dictionary=tasks.filter(func(t:Dictionary)->bool:return t.id==id)[0]
	var moved:bool=int(row.trips)==2 and r.stock(destination).items.get("timber",0)==16 and r.stock(saw.stock_refs.output).items.get("timber",0)==0
	check("the same standing order delivers two batches after replenishment",moved,row)
	return moved and send(r,"factory.pause",saw.id).ok

func repair_test(r:RefCounted,hammer:String)->bool:
	var repair:=build17(r,Families18.id_for("repair",1),"v19:test:repair",25,27,hammer)
	if repair.is_empty():return false
	var before:float=r.tool(hammer).durability
	if not complete15(r,"craft",repair.id,{"recipe_id":"r34:repair_hammer_v2","source_id":"pack:player","output_id":"pack:player","repair_tool_id":hammer,"tool_ids":[]}):return false
	var after:float=r.tool(hammer).durability
	check("a worn field hammer regains actual durability in the new repair shed",after>before)
	return after>before

func heritage_test(r:RefCounted,frame:Dictionary,hammer:String)->bool:
	var sources:Array=r.world.extension("generation:RH-HOME").content_anchors.filter(func(a:Dictionary)->bool:return a.purpose=="stockyard-and-recovery")
	if sources.size()!=1 or not take_source(r,str(sources[0].id)+":container",{"r34:salvaged_drive_unit":1}):return false
	var d:=Catalog18.definition(frame.definition_id)
	for port:Dictionary in Geometry18.ports(frame,d):
		if port.purpose!="repair":continue
		if not care(r,70) or not walk(r,port.location).ok:return false
		if not send(r,"module.discover",frame.id).ok:return false
		break
	var started:Dictionary=send(r,"module.restore",frame.id,{"source_id":"pack:player","tool_id":hammer})
	check("the new heritage mill starts the original paid repair",started.ok,started.get("reason"))
	if not started.ok:return false
	var done:Dictionary=progress(r,1000);var current:Dictionary=r._services.modules.instance(frame.id)
	var ok:bool=done.finished and current.status=="operational" and current.restoration.completed and not r.world.entity(frame.id+":part:fixed-power-housing").is_empty()
	check("actual repair installs the missing visual drive on the same machine",ok)
	if ok:save_scene(r,"restored-mill")
	return ok

func radio18(r:RefCounted,hammer:String)->bool:
	var station:=Village18.radio_station(r.world)
	var building:RefCounted=r._services.buildings
	var points:Array=building.current_space().use_points(building.instance(station))
	check("actual workshop radio has a clear service position",not points.is_empty())
	if points.is_empty() or not care(r,90) or not walk(r,points[0]).ok:return false
	# This fixture supplies prior reading knowledge only; work and costs remain real.
	var tx:=ActionDraft18.new(r._services.production.context)
	var production:Dictionary=tx.extension("r3:production")
	production.knowledge.player=["basic_tool_repair"]
	if not r._commit(tx.result()).ok:return false
	var repaired:Dictionary=send(r,"radio",station,{"operation":"repair","tool_id":hammer})
	check("gated radio repair starts after production",repaired.ok,repaired.get("reason"))
	if not repaired.ok:return false
	for step:int in 280:
		if r.actor("player").intent==null:break
		r.tick(.1)
	var sent:Dictionary=send(r,"radio",station,{"operation":"transmit"})
	check("restored radio accepts transmission",sent.ok,sent.get("reason"))
	if not sent.ok:return false
	for step:int in 380:
		if Stage18.read(r.world).level==3:break
		r.tick(.1)
	check("actual transmission opens stage three",Stage18.read(r.world).level==3,Stage18.read(r.world))
	return Stage18.read(r.world).level==3

func finish()->void:
	check("complete production street and transmission",finished15)
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed},"\t"))
	print(JSON.stringify({"suite":"village-families18","checks":checks.size(),"failed":failed}))
	if live15!=null:live15.retire()
	quit(1 if failed else 0)
