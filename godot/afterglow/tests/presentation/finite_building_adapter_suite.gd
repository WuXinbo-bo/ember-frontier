extends "res://tests/presentation/finite_geometry_policy_suite.gd"
## Actual B renderer nodes consume D policy. Headless node visibility and
## material presence are not rendered Metal pixels or formal VA evidence.

func run()->void:
	var started:int=Time.get_ticks_msec()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	expect("actual generated finite world prepares for shared adapter",prepared.ok,prepared.get("code"))
	if not prepared.ok:finish_local(started);return
	expect("actual authority loads shared adapter world",world.load_snapshot(prepared.capture.world).ok)
	expect("actual runtime configures shared adapter services",runtime.configure({"world":world,"facts":prepared.capture.facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	var warm:Array=[]
	for id:String in world.chunk_keys():
		if not world.chunk(id).resident:warm.append({"op":"chunk.residency","id":id,"before":false,"after":true})
	if not warm.is_empty():commit(warm,"explicit shared adapter fixture warms existing finite data")
	var pair:Dictionary=find_pair()
	expect("actual adapter has supported clear six-metre seam",not pair.is_empty(),pair)
	if pair.is_empty():finish_local(started);return
	var bench:Dictionary=building.make_instance("workbench","ddd:finite-adapter-station",pair.to)
	expect("actual B metre-scale bench supported at observed seam",building.supported(building.current_space(),bench))
	var structures:Dictionary=building.structures();structures.instances.append(bench)
	if not commit(building.changes_for(structures,[bench],[]),"actual versioned workbench installs through C capability"):finish_local(started);return
	var facts:Dictionary=runtime.facts()
	for actor:Dictionary in facts.actors:
		if actor.id=="player":actor.merge(pair.from,true);actor.intent=null
	expect("explicit supported observer retains all other generated facts",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	var view:Node3D=building.create_view({"runtime":runtime});root.add_child(view);view.set_process(false)
	var policy:=Policy.new();view.set_view_policy(policy)
	var before:Dictionary=runtime.capture_checkpoint()
	expect("shared renderer mounts actual workbench object",view.objects.has(bench.id))
	if view.objects.has(bench.id):
		expect("actual fixed furniture shell is visible across seam",view.objects[bench.id].visible)
	expect("B actual content-sight adapter crosses seam only with real LOS",view.visible_room(bench,runtime.actor("player")))
	var external:Array=[];var hidden:Array=[]
	for mesh:MeshInstance3D in view.static_nodes.values():
		var piece:Dictionary=mesh.get_meta("piece");var role:String=mesh.get_meta("role")
		if piece.regionId!=pair.to.regionId or piece.get("buildingId")==null or role=="cap":continue
		if not policy.base_visible(piece,role):continue
		external.append(piece.id)
		if not mesh.visible:hidden.append(piece.id)
	expect("actual neighboring structure meshes consume same finite scope",not external.is_empty() and hidden.is_empty(),{"expected_nodes":external.size(),"hidden":hidden})
	var cfg:Dictionary=world.config();var width:float=float(cfg.cellSize)*int(cfg.chunkCells)
	var middle:Vector3=Geometry.point(pair.from).lerp(Geometry.point(pair.to),0.5)
	var key:String="%d,%d,%d"%[floori(middle.x/width),floori(middle.y/width),floori(middle.z/width)]
	expect("renderer observations never mutate authority",Data.json_equal(before,runtime.capture_checkpoint()))
	if commit([{"op":"chunk.residency","id":key,"before":true,"after":false}],"shared adapter fixture withdraws actual traversed residency"):
		view.update_policy_visibility(runtime.actor("player"),building.current_space())
		expect("same real renderer hides fixed shell on actual cold segment",view.objects.has(bench.id) and not view.objects[bench.id].visible)
		expect("B actual content-sight rejects cold neighbor segment",not view.visible_room(bench,runtime.actor("player")))
		if commit([{"op":"chunk.residency","id":key,"before":false,"after":true}],"shared adapter restores same actual generated residency"):
			view.update_policy_visibility(runtime.actor("player"),building.current_space())
			expect("same mounted renderer restores finite furniture shell",view.objects.has(bench.id) and view.objects[bench.id].visible)
	view.free();finish_local(started)
