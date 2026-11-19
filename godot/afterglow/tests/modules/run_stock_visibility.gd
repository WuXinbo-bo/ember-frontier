extends "res://tests/modules/run_stock_layout.gd"
## The real owner projection and D consumer, after authority commits actual
## voxel/entity edits. Finite full-stock fixture is explicit, not economy proof.
func row(rt:RefCounted,module_id:String,buffer_id:String)->Dictionary:
	for v:Dictionary in rt.factory_snapshot().modules.instances:
		if v.id==module_id:
			for b:Dictionary in v.visuals.buffers:
				if b.id==buffer_id:return b
	return {}

func edit(rt:RefCounted,changes:Array)->Dictionary:
	return rt._commit({"ok":true,"world_changes":changes,"fact_changes":[],"events":[]})

func put(e:Dictionary)->Dictionary:
	return {"op":"entity.put","id":e.id,"before_exists":false,"before":null,"after":e}

func remove(e:Dictionary)->Dictionary:
	return {"op":"entity.remove","id":e.id,"before_exists":true,"before":e,"after":null}

func run()->void:
	var lock:Dictionary=Contract.fresh(Catalog.profiles(),3)
	var made:Dictionary=Assembly.prepare(Generator.generate(713,Catalog.profiles(),lock.contract))
	check("actual content3 composes",made.ok,made.get("reason"))
	if not made.ok:return done()
	var capture:Dictionary=made.capture
	for v:Dictionary in capture.world.extensions[Modules.KEY].instances:
		if v.region!="RH-HOME":continue
		for b:Dictionary in Catalog.definition(v.definition_id).buffer_specs:
			var stock:Dictionary=Draft.find(capture.facts.stocks,str(v.stock_refs[b.id]));stock.searched=true;stock.items=b.limits.duplicate(true)
	var host:=Native.new();var built:Dictionary=host._assemble(capture);host.free()
	check("explicit finite full stock fixture validates with formal Native",built.ok,built.get("reason"))
	if not built.ok:return done()
	var rt:RefCounted=built.runtime;var world:RefCounted=built.world;var modules:RefCounted=built.services.modules
	var home:Dictionary=modules.instance("r34:generated:RH-HOME:home")
	var d:Dictionary=Catalog.definition(home.definition_id);var bay:Dictionary=Layout.bay(home,d,"supplies","food")
	var box:=Layout._bounds(Vector3(bay.anchor.position[0],bay.anchor.position[1],bay.anchor.position[2]),int(bay.anchor.quarter_turn),Vector3(bay.extent[0],bay.extent[1],bay.extent[2]))
	var before:Dictionary=rt.capture_checkpoint();var stock_before:Dictionary=rt.stock(home.stock_refs.supplies)
	var view:=View.new();root.add_child(view);view.configure(rt)
	check("initial owner and actual consumer show supported cargo",row(rt,home.id,"supplies:food").visual_available and view._buffers[home.id]["supplies:food"].statistics().visible_parts==9)
	check("queries and view leave real facts unchanged",Data.json_equal(before,rt.capture_checkpoint()))
	var cell:=Vector3i(floori(box.get_center().x*2),floori((box.position.y-0.01)*2),floori(box.get_center().z*2))
	var material:int=world.cell_at(cell.x,cell.y,cell.z)
	var removed:Dictionary=edit(rt,[{"op":"voxel.set","cell":{"x":cell.x,"y":cell.y,"z":cell.z},"before":material,"after":0}]);view.sync()
	check("real apron voxel removal passes original safety",material>0 and removed.ok,removed)
	var hidden:Dictionary=row(rt,home.id,"supplies:food")
	check("removed actual support invalidates owner and hides consumer",not hidden.visual_available and hidden.visual_reason=="unsupported" and view._buffers[home.id]["supplies:food"].statistics().visible_parts==0,hidden)
	check("unsupported visual never moves loses or changes actual stock",Data.json_equal(stock_before,rt.stock(home.stock_refs.supplies)))
	var cold_host:=Native.new();var restored:Dictionary=cold_host._assemble(rt.capture_checkpoint());cold_host.free()
	check("cold Native recomputes unsupported state without cached proof",restored.ok and not row(restored.runtime,home.id,"supplies:food").visual_available,restored.get("reason"))
	var filled:Dictionary=edit(rt,[{"op":"voxel.set","cell":{"x":cell.x,"y":cell.y,"z":cell.z},"before":0,"after":material}]);view.sync()
	check("true refill restores original supported cargo same quantity",filled.ok and row(rt,home.id,"supplies:food").visual_available and view._buffers[home.id]["supplies:food"].statistics().visible_parts==9,filled)
	var occupied_box:=AABB(box.position+Vector3(0.01,0.01,0.01),box.size-Vector3(0.02,0.02,0.02))
	var blocker:Dictionary={"id":"B:cargo:transparent-solid","kind":"prop","regionId":home.region,"position":G.json_point(occupied_box.position),"bounds":G.json_box(occupied_box),"revision":world.get_revision(),"blocksTerrain":false,"supportBounds":[],"data":{"solid":true,"opaque":false}}
	var occupied:Dictionary=edit(rt,[put(blocker)]);view.sync()
	check("transparent physical object invalidates cargo availability",occupied.ok and not row(rt,home.id,"supplies:food").visual_available and row(rt,home.id,"supplies:food").visual_reason=="occupied" and view._buffers[home.id]["supplies:food"].statistics().visible_parts==0,occupied)
	var unblocked:Dictionary=edit(rt,[remove(world.entity(blocker.id))]);view.sync()
	check("removing actual obstruction restores same proxy",unblocked.ok and row(rt,home.id,"supplies:food").visual_available and view._buffers[home.id]["supplies:food"].statistics().visible_parts==9,unblocked)
	var shed:Dictionary=modules.instance("r34:generated:RH-HOME:woodwork")
	var shelf:Dictionary=world.entity(shed.id+":part:repair-shed:rear-plinth")
	# A removed ID is retired by C and cannot be resurrected. Move this same
	# finite support in the fixture, then restore its exact CAS image instead.
	var shifted:Dictionary=shelf.duplicate(true);shifted.position.y+=0.8;shifted.bounds.min.y+=0.8;shifted.bounds.max.y+=0.8
	var detached:Dictionary=edit(rt,[{"op":"entity.put","id":shelf.id,"before_exists":true,"before":shelf,"after":shifted}]);view.sync()
	check("removing actual shelf support never draws floating goods",detached.ok and not row(rt,shed.id,"tools:timber").visual_available and row(rt,shed.id,"tools:timber").visual_reason=="unsupported" and view._buffers[shed.id]["tools:timber"].statistics().visible_parts==0,detached)
	var replaced:Dictionary=edit(rt,[{"op":"entity.put","id":shelf.id,"before_exists":true,"before":world.entity(shelf.id),"after":shelf}]);view.sync()
	check("replacing same real shelf restores without new inventory",replaced.ok and row(rt,shed.id,"tools:timber").visual_available and view._buffers[shed.id]["tools:timber"].statistics().visible_parts==9,replaced)
	check("non detailed region gives explicit visual reason only",modules.stock_visual_status(home,bay,false)=={"visual_available":false,"visual_reason":"not_detailed"} and modules.stock_visual_status(home,bay,true).visual_available)
	check("all visual changes preserve exact quantities and consumer validity",Data.json_equal(stock_before,rt.stock(home.stock_refs.supplies)) and view.statistics().required_errors.is_empty(),view.statistics().required_errors)
	view.free();done()

func done()->void:
	var ok:bool=checks.all(func(c:Dictionary)->bool:return c.ok)
	print(JSON.stringify({"ok":ok,"checks":checks,"scope":"real owner to D consumer after original Runtime voxel/entity safety commits, explicit full stock fixture; no renderer/package/VA/performance"}));quit(0 if ok else 1)
