extends SceneTree

const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Profile=preload("res://scripts/runtime/playtest_profile.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Generator=preload("res://scripts/world/factory_generator.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Compact=preload("res://scripts/modules/compact_catalog.gd")
const Stock=preload("res://scripts/modules/module_stock_layout.gd")
const Projects=preload("res://scripts/modules/module_projects.gd")
const Warehouse="r34:generated:RH-HOME:village-warehouse"
var checks:Array=[]

func _initialize()->void:call_deferred("run")

func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name+" "+str(detail))

func run()->void:
	check("catalog validates all definitions",Catalog.validate().ok)
	for id:String in Compact.CHOICES+[Compact.WORKSHOP,Compact.WAREHOUSE_UPGRADE]:
		var d:=Catalog.definition(id)
		var fp:=G.aabb(d.footprint).grow(.001)
		var parts:=Shape.parts(d)
		check(id+" has geometry in its own footprint",not parts.is_empty() and parts.all(func(p:Dictionary)->bool:
			var size:=G.point(p.size)
			return fp.encloses(AABB(G.point(p.center)-size*.5,size))))
		for turn:int in 4:
			var inst:Dictionary={"position":{"x":0,"y":0,"z":0},"quarter_turn":turn,"region":"RH-HOME"}
			var box:=Shape.transform_box(inst,G.aabb(d.footprint))
			check(id+" service clearance turn %d"%turn,Shape.ports(inst,d).all(func(p:Dictionary)->bool:
				var q:=G.point(p.location)
				return not box.intersects(AABB(q-Vector3(.4,0,.4),Vector3(.8,1.8,.8)))))
	var current:=Assembly.generation_profiles(17)
	var new_lock:=Contract.fresh(current.profiles,17,1)
	check("content17 generation contract validates",new_lock.ok,new_lock.get("reason"))
	if not new_lock.ok:return finish()
	for seed:int in [713,1,42,907,20261118,2718]:
		for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1),Vector2i(1,0)]:
			var plan:Dictionary=Generator.plan_region(seed,coord,current.profiles,new_lock.contract)
			check("seed %d region %s generates"%[seed,coord],plan.get("ok",false),plan.get("code","")+":"+plan.get("reason",""))
	var old:=Assembly.generation_profiles(16)
	var old_lock:=Contract.fresh(old.profiles,16,1)
	check("historical profiles and choices exclude compact content",old_lock.ok and not old.profiles.any(func(p:Dictionary)->bool:return p.id.begins_with(Compact.PREFIX)) and not Catalog.build_definition_ids(16).has(Compact.SAWMILL))
	var prepared:=Assembly.prepare(Assembly.generate(713,current.profiles,17))
	check("fresh content17 composes native data",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):return finish()
	var host:=Native.new()
	var made:Dictionary=host._assemble(Profile.prepare_opening(prepared.capture,"playtest"))
	check("fresh content17 mounts",made.get("ok",false),made.get("reason"))
	if not made.get("ok",false):host.free();return finish()
	var runtime:RefCounted=made.runtime
	var modules:RefCounted=runtime._services.modules
	var warehouse:Dictionary=modules.instance(Warehouse)
	check("original storage uses the compact unrestored warehouse",warehouse.get("definition_id")==Compact.WAREHOUSE and warehouse.get("restoration",{}).get("completed")==false)
	var menu:Dictionary=runtime.factory_page_snapshot("player","factory_catalog")
	check("shipping build menu selects compact stations",menu.get("modules",{}).get("build_definition_ids",[]).slice(0,Compact.CHOICES.size())==Compact.CHOICES)
	check("every real warehouse item has a physical shelf bay",Stock.local_plan(Catalog.definition(Compact.WAREHOUSE)).size()==9)
	var placed:Array=[]
	for spec:Array in [[Compact.YARD,30,21],[Compact.SAWMILL,35,21],[Compact.PREFIX+"cottage",9,39]]:
		var pos:Dictionary={"x":spec[1],"z":spec[2],"y":runtime.world.surface_height(spec[1],spec[2]),"regionId":"RH-HOME"}
		var v:Dictionary=Projects.plan_instance(modules,{"target_id":"test:"+spec[0],"payload":{"definition_id":spec[0],"position":pos,"quarter_turn":0}})
		var valid:Dictionary=Projects.footprint_check(modules,v,runtime.facts())
		check("prepared land supports "+spec[0],valid.ok,valid)
		placed.append(v)
	check("yard and saw footprint fit side by side",not Shape.transform_box(placed[0],G.aabb(Catalog.definition(Compact.YARD).footprint)).intersects(Shape.transform_box(placed[1],G.aabb(Catalog.definition(Compact.SAWMILL).footprint))))
	var encoded:=Store.encode(runtime.capture_checkpoint())
	var decoded:=Store.decode(encoded.text)
	var loaded:Dictionary=host._assemble(decoded.capture) if decoded.ok else decoded
	check("native v17 checkpoint cold mounts",loaded.get("ok",false),loaded.get("reason"))
	if loaded.get("ok",false):loaded.runtime.retire()
	runtime.retire();host.free()
	finish()

func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"suite":"compact-village-17","checks":checks,"failed":failed}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify({"suite":report.suite,"checks":checks.size(),"failed":failed}))
	quit(1 if failed else 0)
