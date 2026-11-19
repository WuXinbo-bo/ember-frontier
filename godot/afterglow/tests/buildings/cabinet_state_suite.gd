extends "res://tests/buildings/generated_camp_suite.gd"
## Real finite camp route with the actual renderer subscribed to every change.
## No UI/Metal acceptance is implied by this command-level state evidence.
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")

func assert_cabinet(view:Node3D,service:RefCounted,label:String)->void:
	var id:="RH-HOME:home:storage"
	var actual:Node3D=view.objects.get(id)
	var piece:Dictionary=service.instance(id)
	var bounds:AABB=view.model_bounds(actual)
	var expected:AABB=service.geometry.boxes(piece)[0]
	expect(label+" actual model and joinery follow current full cabinet volume",actual!=null and actual.has_node("CabinetJoinery") and bounds.position.distance_to(expected.position)<0.0001 and bounds.size.distance_to(expected.size)<0.0001,{"rendered":str(bounds),"current":str(expected)})

func run()->void:
	var started:=Time.get_ticks_msec()
	host=Client.new()
	var prepared:Dictionary=Assembly.prepare(Generator.generate_settlement(713,Building.generation_profiles()))
	expect("live-view camp starts from actual finite generated world",prepared.ok,prepared.get("reason"))
	if not prepared.ok:host.free();finish(started);return
	var assembled:Dictionary=host._assemble(prepared.capture)
	expect("sole formal assembler supplies live renderer and execution services",assembled.ok,assembled.get("reason"))
	if not assembled.ok:host.free();finish(started);return
	world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings;actions=assembled.services.actions;production=assembled.services.production
	var view:Node3D=building.create_view({"runtime":runtime})
	view.set_view_policy(Policy.new())
	var old_position:Dictionary=building.instance("RH-HOME:home:storage").position.duplicate(true)
	var cached:Texture2D=view.materials.wood_floor.albedo_texture
	assert_cabinet(view,building,"before labor")
	generated_opening()
	expect("actual finite camp labor really moved the loaded cabinet",building.instance("RH-HOME:home:storage").position!=old_position)
	assert_cabinet(view,building,"after actual relocation")
	expect("real dismantle immediately removes the workbench render node",not view.objects.has("RH-HOME:home:workbench-reservation"))
	expect("actual move and removal rebuilds reuse existing real mip texture",view.materials.wood_floor.albedo_texture==cached and cached.get_image().has_mipmaps())
	var capture:=runtime.capture_checkpoint();var encoded:=Store.encode(capture);var decoded:=Store.decode(encoded.get("text",""))
	var restored:Dictionary=host._assemble(decoded.capture) if encoded.ok and decoded.ok else {"ok":false}
	expect("actual changed cabinet route restores using native storage",restored.ok)
	if restored.ok:
		var before:Dictionary=restored.runtime.capture_checkpoint()
		var restored_view:Node3D=restored.services.buildings.create_view({"runtime":restored.runtime})
		assert_cabinet(restored_view,restored.services.buildings,"after native restore")
		expect("restored view never restores demolished bench or adds contents",not restored_view.objects.has("RH-HOME:home:workbench-reservation") and restored.runtime.stock("RH-HOME:home:storage").items==runtime.stock("RH-HOME:home:storage").items)
		expect("restored visual construction does not mutate any saved fact",preload("res://scripts/world/world_data.gd").json_equal(before,restored.runtime.capture_checkpoint()))
		restored_view.free()
	view.free();host.free();host=null
	print("ACTUAL_CABINET_ROUTE "+JSON.stringify(route_steps))
	finish(started)
