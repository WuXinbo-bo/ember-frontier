extends "res://tests/buildings/interior_adapter_suite.gd"
## Explicit legal camera/stock presentation fixtures. Not OS movement or VA.
var suite_services:Dictionary={}
var render_mutations:Array=[]

func ids(nodes:Dictionary)->Dictionary:
	var result:Dictionary={}
	for id:String in nodes:result[id]=nodes[id].get_instance_id()
	return result

func use_facts(value:Dictionary)->void:
	# Reconfigure is an explicit pose/count fixture, not a rendering operation.
	# Preserve its source/revisions/receipts rather than silently resetting the
	# real runtime metadata and then blaming that reset on the renderer.
	var previous:=runtime.capture_checkpoint()
	runtime.configure({"world":world,"facts":value,"services":suite_services,"source":previous.source,"command_revision":previous.command_revision,"receipts":previous.receipts})
	var configured:=runtime.capture_checkpoint()
	view.update_contents();view.update_visibility()
	if not Data.json_equal(configured,runtime.capture_checkpoint()):render_mutations.append({"before":configured,"after":runtime.capture_checkpoint()})

func run()->void:
	var started:=Time.get_ticks_msec()
	expect("real retained village loads",world.load_snapshot(Generator.generate(713)).ok)
	building.configure({"world":world,"runtime":runtime})
	var seeded:Dictionary=building.seed_rural(world)
	var changes:Array=seeded.world_changes.duplicate(true)
	changes.append_array([building.extension_change(Production.KEY,Initial.production(seeded)),building.extension_change("r3:structure-orders",{"version":1,"orders":[]})])
	var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
	expect("sole world accepts fixture seed",draft.ok and world.commit_prepared(draft.capability).ok)
	host=Client.new()
	var assembled:Dictionary=host._assemble({"world":world.snapshot(),"facts":Initial.facts(seeded),"source":{"test":"B real domestic shell/contents state"}})
	expect("formal native assembler supplies same authority",assembled.ok,assembled.get("reason"))
	if not assembled.ok:host.free();finish(started);return
	world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings;actions=assembled.services.actions;production=assembled.services.production
	suite_services=assembled.services
	view=building.create_view({"runtime":runtime})
	var policy:=Policy.new();view.set_view_policy(policy)
	expect("D stable shell API is actually available",policy.has_method("can_observe_geometry"))
	var original:=runtime.capture_checkpoint()
	var shells:=ids(view.objects);var contents:=ids(view.content_nodes)
	view.rebuild()
	expect("unrelated static rebuild preserves all original furniture/scenery node identities",ids(view.objects)==shells,{"before":shells,"after":ids(view.objects)})
	expect("unrelated static rebuild preserves every unchanged content mesh",ids(view.content_nodes)==contents)
	var facts:Dictionary=runtime.facts();facts.stocks.reverse()
	use_facts(facts)
	expect("stock ordering alone never rebuilds contents",ids(view.content_nodes)==contents)
	var unknown:String="";var known:String=""
	for stock:Dictionary in facts.stocks:
		if stock.searched and view.content_nodes.has(stock.id):known=stock.id
		elif not stock.searched:unknown=stock.id
	expect("fixture contains real known and unsearched stock",not known.is_empty() and not unknown.is_empty())
	for stock:Dictionary in facts.stocks:
		if stock.id==unknown:stock.items.scrap=int(stock.items.get("scrap",0))+1
	use_facts(facts)
	expect("unknown-holder count change does not flash known content",ids(view.content_nodes)==contents)
	expect("unsearched stock still creates no content mesh",not view.content_nodes.has(unknown))
	for stock:Dictionary in facts.stocks:
		if stock.id==known:stock.items.water=int(stock.items.get("water",0))+1
	use_facts(facts)
	expect("real changed display count replaces only the affected holder",view.content_nodes.has(known) and view.content_nodes[known].get_instance_id()!=contents[known] and ids(view.objects)==shells)
	var stable:=ids(view.content_nodes)
	view.update_contents()
	expect("identical next refresh retains changed holder mesh",ids(view.content_nodes)==stable)
	for stock:Dictionary in facts.stocks:
		if stock.id==known:stock.searched=false
	use_facts(facts)
	expect("loss of searched fact removes content immediately",not view.content_nodes.has(known))
	use_facts(original.facts)
	var samples:=0;var mismatches:Array=[];var old_los:Dictionary={};var shell_states:Dictionary={}
	for x:float in [10.5,11.0,11.5,12.0,12.5,13.0,13.5,17.5,18.0,18.5,19.0,19.5,20.0,20.5]:
		for z:float in [28.5,29.5,30.5,31.5,32.5,33.5,34.5,35.5,36.5]:
			var feet:Dictionary=building.current_space().standing_point({"x":x,"y":0,"z":z,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
			if feet.is_empty() or feet.get("buildingId")!=HOME:continue
			var f:=runtime.facts();f.actors[0].merge(feet,true)
			use_facts(f);policy.sample(feet,Time.get_ticks_msec()+200);view.update_visibility();samples+=1
			var room:String=policy.statistics().get("room_id","")
			for id:String in view.objects:
				var piece:Dictionary=view.objects[id].get_meta("piece")
				if piece.get("buildingId")!=HOME:continue
				var key:String=room+"|"+id
				if not old_los.has(key):old_los[key]={};shell_states[key]={}
				old_los[key][view.visible_room(piece,runtime.actor("player"))]=true
				shell_states[key][view.objects[id].visible]=true
				if view.objects[id].visible!=view.visible_shell(piece,runtime.actor("player")):mismatches.append(key)
			for node:MeshInstance3D in view.get_node("Contents").get_children():
				var piece:Dictionary=node.get_meta("piece")
				if node.visible and not view.visible_room(piece,runtime.actor("player")):mismatches.append("content leak "+piece.id)
	var old_toggle:Array=[];var new_toggle:Array=[]
	for key:String in old_los:
		if old_los[key].size()>1:old_toggle.append(key)
		if shell_states[key].size()>1:new_toggle.append(key)
	expect("actual legal interior stations exercise closed structural rooms",samples>40,samples)
	expect("furniture and contents obey distinct exact scope without unknown-content leak",mismatches.is_empty(),mismatches)
	print("ACTUAL_FURNITURE_STABILITY "+JSON.stringify({"legal_stations":samples,"old_origin_los_toggles":old_toggle,"stable_shell_toggles":new_toggle,"node_reuse":true,"scope":"legal pose fixtures; not frame capture or OS playtest"}))
	use_facts(original.facts)
	expect("every render refresh retains the full exact configured authority",render_mutations.is_empty(),render_mutations)
	var after:=runtime.capture_checkpoint()
	expect("derived construction never changes any original world/fact/metadata",Data.json_equal(original,after),{"original_source":original.source,"after_source":after.source,"original_command_revision":original.command_revision,"after_command_revision":after.command_revision,"facts_same":Data.json_equal(original.facts,after.facts),"world_same":Data.json_equal(original.world,after.world),"receipts_same":Data.json_equal(original.receipts,after.receipts)})
	for child:Node in view.get_children():child.queue_free()
	await process_frame
	view.queue_free();host.queue_free();await process_frame
	finish(started)
