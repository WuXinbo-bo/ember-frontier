extends "res://tests/buildings/presentation_suite.gd"
## Explicit visual HP/finish fixtures on actual validated structure edits.
## Finite real repair labor itself is verified by building_state_suite.
func edit_piece(next:Dictionary)->bool:
	var old:Dictionary=building.instance(str(next.id));next.version=int(old.version)+1
	var edit:Dictionary=building.prepare_edit([next.id],[next],runtime.facts())
	if not edit.ok:return false
	return runtime._commit({"ok":true,"world_changes":edit.world_changes,"fact_changes":[]}).ok

func detail(view:Node3D,id:String)->MeshInstance3D:
	for child:MeshInstance3D in view.get_node("StateDetails").get_children():
		if child.get_meta("piece",{}).get("id")==id and child.has_meta("state_material"):return child
	return null

func run()->void:
	var started:=Time.get_ticks_msec()
	expect("actual retained rural world loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var seeded:Dictionary=building.seed_rural(world)
	var p:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("actual retained buildings commit",p.ok and world.commit_prepared(p.capability).ok)
	initialize_at(Geometry.location(runtime.actor("player")),[],seeded.initial_stocks)
	# The production transaction initializes an absent optional event ledger,
	# including for an empty event list. Normalize this explicit fixture first,
	# then retain an exact full-facts comparison for every subsequent edit.
	expect("normalize original optional ledger through actual transaction",runtime._commit({"ok":true,"world_changes":[],"fact_changes":[]}).ok)
	var view:Node3D=building.create_view({"runtime":runtime})
	view.set_view_policy(preload("res://scripts/presentation/interior_view_policy.gd").new())
	var wall:Dictionary=building.structures().instances.filter(func(v:Dictionary)->bool:return v.buildingId=="rural:v1:RH-HOME:old-house" and v.definitionId=="wall")[0]
	var original_facts:=runtime.facts();var original_production:Variant=world.extension(Production.KEY);var rows:Array=[]
	for base:String in ["old_brick","cream_plaster","wood_floor","roof_tile","zinc","mint_paint"]:
		# Explicit surface-contract fixture, not six new gameplay buildings or
		# random damage. Shape, support, residents and exit checks stay real.
		var changed:=wall.duplicate(true);changed.presentation={"wall":base,"condition":"aged"}
		expect("validated surface fixture "+base,edit_piece(changed))
		var ids:Dictionary={}
		for key:String in view.static_nodes:ids[key]=view.static_nodes[key].get_instance_id()
		changed=building.instance(wall.id);changed.hp=float(building.geometry.definition(changed).maxHp)-1
		expect("actual positive HP edit "+base,edit_piece(changed))
		var node:=detail(view,wall.id)
		var family:String=preload("res://scripts/buildings/building_surface_state.gd").FAMILIES[base]
		var matching:bool=node!=null and node.get_meta("state")=="damaged" and mesh_contains(node,view.material("b_"+family+"_damaged")) and mesh_contains(node,view.material("b_"+family+"_damage_detail"))
		expect("live HP selects matching approved surface and alpha mark "+family,matching)
		var retained:bool=ids.size()==view.static_nodes.size()
		for key:String in ids:retained=retained and view.static_nodes.has(key) and ids[key]==view.static_nodes[key].get_instance_id()
		expect("positive HP refresh retains unchanged static batches "+family,retained)
		expect("state shell follows actual host cutaway "+family,node!=null and node.has_meta("state_batch") and node.visible==view.static_nodes[node.get_meta("state_batch")].visible)
		changed=building.instance(wall.id);changed.hp=building.geometry.definition(changed).maxHp
		expect("explicit restored HP alone remains valid "+family,edit_piece(changed))
		expect("HP without completed repair never fabricates patch history "+family,detail(view,wall.id)==null)
		rows.append({"family":family,"dynamic_bound":matching,"static_batches_retained":retained})
	expect("visual fixtures leave inventories actors clock and learning unchanged",runtime.facts()==original_facts and world.extension(Production.KEY)==original_production,{"before":original_facts,"after":runtime.facts()})
	print("ACTUAL_DYNAMIC_SURFACE_BINDINGS "+JSON.stringify(rows))
	view.free();finish(started)
