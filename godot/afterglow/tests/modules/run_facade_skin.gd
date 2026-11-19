extends "res://tests/modules/run_stock_layout.gd"
const BuildingView=preload("res://scripts/buildings/building_view.gd")
const Facade=preload("res://scripts/buildings/module_facade_detail.gd")
const Store=preload("res://scripts/storage/native_store.gd")
func run()->void:
	for seed:int in [713,2026]:
		var locked:=Contract.fresh(Catalog.profiles(),3)
		var made:Dictionary=Assembly.prepare(Generator.generate(seed,Catalog.profiles(),locked.contract))
		var host:=Native.new();var built:Dictionary=host._assemble(made.capture) if made.ok else made;host.free()
		check("actual content3 normal world mounts "+str(seed),built.ok,built.get("reason"))
		if not built.ok:continue
		var before:Dictionary=built.runtime.capture_checkpoint();var view:=BuildingView.new();root.add_child(view)
		view.configure({"service":built.services.buildings,"runtime":built.runtime})
		var present:int=0;var near_present:int=0;var bad:Array=[]
		for id:String in view.objects:
			var node:Node3D=view.objects[id]
			if node.get_meta("facade_skin_version","")!=Facade.VERSION:continue
			present+=1
			var entity:Dictionary=built.world.entity(id);var bounds:AABB=G.aabb(entity.bounds)
			if entity.regionId==built.runtime.actor("player").regionId:near_present+=1
			var visual:AABB=node.global_transform*node.get_aabb()
			if not node.visible or not bounds.grow(0.20).encloses(visual):bad.append({"id":id,"visible":node.visible,"authority":G.json_box(bounds),"visual":G.json_box(visual)})
			var materials:Array=[]
			for surface:int in node.mesh.get_surface_count():materials.append(node.mesh.surface_get_material(surface))
			check("actual side rear skin uses existing wood brick and metal textures "+str(seed)+id,materials.has(view.material("b_wood_aged")) and materials.has(view.material("old_brick")) and materials.has(view.material("painted_metal")))
		check("normal camera visible home and repair side rear have real skin "+str(seed),near_present==6 and present==15 and bad.is_empty(),{"present":present,"near_present":near_present,"bad":bad})
		check("display never changes old geometry permission stock or world "+str(seed),Data.json_equal(before,built.runtime.capture_checkpoint()))
		var encoded:Dictionary=Store.encode(before);var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
		var cold_host:=Native.new();var cold:Dictionary=cold_host._assemble(decoded.capture) if decoded.ok else decoded;cold_host.free()
		var restored:=BuildingView.new();root.add_child(restored)
		if cold.ok:restored.configure({"service":cold.services.buildings,"runtime":cold.runtime})
		var same:bool=cold.ok
		for id:String in view.objects:
			var original:Node3D=view.objects[id]
			if not original.has_meta("facade_skin_version"):continue
			same=same and restored.objects.has(id)
			if not restored.objects.has(id):continue
			var again:MeshInstance3D=restored.objects[id]
			same=same and again.get_meta("facade_skin_version","")==Facade.VERSION and original.mesh.get_aabb().is_equal_approx(again.mesh.get_aabb())
		check("real saved member identities rebuild identical display skin "+str(seed),same)
		var shed:Dictionary=built.services.modules.instance("r34:generated:RH-HOME:woodwork")
		var destroyed:Dictionary=built.runtime._commit(built.services.modules.prepare_damage(shed.id,1000,"B:skin:damage"))
		check("actual destroyed shell and its attached skin disappear together "+str(seed),destroyed.ok and not view.objects.has(shed.id+":part:repair-shed:rear"),destroyed.get("reason"))
		view.free();restored.free()
	var ok:bool=checks.all(func(c:Dictionary)->bool:return c.ok)
	print(JSON.stringify({"ok":ok,"checks":checks,"scope":"real current BuildingView consumer, original pinned entities and native save/ruin; no new opening/collider; no OS/VA approval"}));quit(0 if ok else 1)
