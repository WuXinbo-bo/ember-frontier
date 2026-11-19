extends "res://tests/buildings/roof_coherence_suite.gd"
## B renderer integration, using A's actual policy and real retained home.
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
const Data=preload("res://scripts/world/world_data.gd")

class ObservedPolicy extends "res://scripts/presentation/interior_view_policy.gd":
	var samples:=0
	func sample(location:Dictionary,now_ms:int=-1)->bool:
		samples+=1
		return super.sample(location,now_ms)

func verify_adapter(policy:RefCounted,label:String)->void:
	var mismatch:Array=[];var mixed:Array=[]
	var query:RefCounted=building.current_space()
	for node:MeshInstance3D in view.static_nodes.values():
		var piece:Dictionary=node.get_meta("piece");var role:String=node.get_meta("role")
		var cut:bool=policy.cut_wall(piece)
		var expected:bool=policy.base_visible(piece,role) and (not cut if role=="wall" else false if role=="cap" else true)
		if node.visible!=expected:mismatch.append(piece.id)
		for id:String in node.get_meta("piece_ids",[]):
			var actual:Dictionary=query.by_id[id]
			if policy.base_visible(actual,role)!=policy.base_visible(piece,role) or (role in ["wall","cap"] and policy.cut_wall(actual)!=cut):mixed.append({"representative":piece.id,"member":id,"role":role})
	expect(label+" static full/entry/roof follow one policy with no near-wall remnant",mismatch.is_empty() and not view.batches.values().any(func(v:Dictionary)->bool:return v.role=="cap"),mismatch)
	expect(label+" every batched member has the same view state",mixed.is_empty(),mixed)
	var leaks:Array=[];var door_mismatch:Array=[]
	var player:Dictionary=runtime.actor("player")
	for node:Node3D in view.objects.values():
		var piece:Dictionary=node.get_meta("piece")
		var definition:Dictionary=building.geometry.definitions.get(piece.get("definitionId"),{})
		var fixed:bool=definition.get("kind") in ["cabinet","workbench"] or piece.get("data",{}).get("assetId")=="city_bed"
		var observed:bool=policy.can_observe_geometry(piece,player) if fixed and policy.has_method("can_observe_geometry") else view.visible_room(piece,player)
		if node.visible!=(observed and policy.base_visible(piece,"object")):leaks.append(piece.id)
	for group:String in ["Contents","StateDetails"]:
		if not view.has_node(group):continue
		for node:Node3D in view.get_node(group).get_children():
			var piece:Dictionary=node.get_meta("piece")
			var cut:bool=group=="StateDetails" and node.get_meta("wall_attached",false) and policy.cut_wall(piece)
			if node.visible!=(view.visible_room(piece,player) and policy.base_visible(piece,"object") and not cut):leaks.append(piece.id)
	for entry:Dictionary in view.doors.values():
		if entry.node.visible!=policy.base_visible(entry.piece,"door") or entry.full.visible==policy.cut_wall(entry.piece) or entry.has("cut"):door_mismatch.append(entry.piece.id)
	expect(label+" objects contents and details retain actual LOS",leaks.is_empty(),leaks)
	expect(label+" actual hinged leaves and frames share view scope",door_mismatch.is_empty(),door_mismatch)

func run()->void:
	var started:=Time.get_ticks_msec()
	expect("retained rural source loads",world.load_snapshot(Generator.generate(713)).ok)
	building.configure({"world":world,"runtime":runtime})
	var seeded:Dictionary=building.seed_rural(world)
	var facts:=Initial.facts(seeded)
	var changes:Array=seeded.world_changes.duplicate(true)
	changes.append_array([building.extension_change(Production.KEY,Initial.production(seeded)),building.extension_change(Gameplay.KEY,Gameplay.initial()),building.extension_change("r3:structure-orders",{"version":1,"orders":[]})])
	var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
	expect("same authoritative C capability commits fixture",draft.ok and world.commit_prepared(draft.capability).ok)
	host=Client.new()
	var assembled:Dictionary=host._assemble({"world":world.snapshot(),"facts":facts,"source":{"test":"B actual interior adapter"}})
	expect("formal assembler supplies original services",assembled.ok,assembled.get("reason"))
	if not assembled.ok:host.free();finish(started);return
	world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings;actions=assembled.services.actions;production=assembled.services.production
	view=building.create_view({"runtime":runtime})
	var policy:=ObservedPolicy.new()
	view.set_view_policy(policy)
	for station:Vector2 in [Vector2(18,36),Vector2(18.5,36),Vector2(19,36),Vector2(12,35.5),Vector2(12,29.5),Vector2(30,43)]:
		if not fixture_at(station.x,station.y):continue
		var at:=Geometry.location(runtime.actor("player"));policy.sample(at,Time.get_ticks_msec()+200)
		view.update_visibility();verify_adapter(policy,"station "+str(station))
	var before:=runtime.capture_checkpoint();var count:int=policy.samples
	for i in 4:view.update_visibility()
	expect("stationary refresh still advances policy hysteresis clock",policy.samples==count+4)
	expect("derived view never changes world time stock or actor facts",Data.json_equal(before,runtime.capture_checkpoint()))
	# New stock meshes must be hidden again even when the only change was a
	# fact-level count, with the player and C world revision unchanged.
	fixture_at(18,36);policy.sample(Geometry.location(runtime.actor("player")),Time.get_ticks_msec()+200);view.update_visibility()
	var hidden_id:String=HOME+":storage";var changed:=runtime.facts()
	for stock:Dictionary in changed.stocks:
		if stock.id==hidden_id:stock.searched=true;stock.items.water=int(stock.items.get("water",0))+1
	runtime.configure({"world":world,"facts":changed,"services":{"buildings":building,"actions":actions,"production":production}})
	view.update_contents();view.update_visibility();verify_adapter(policy,"stationary stock-only rebuild")
	view.set_view_policy(null)
	expect("policy may be detached without losing retained fallback",view._view_policy==null and not view.roof_cutaway.components.is_empty())
	view.free();host.free();finish(started)
