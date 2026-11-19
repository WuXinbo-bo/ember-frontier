extends "res://tests/world/environment_mount.gd"
## New C entity-notification scope. Exact adopted86 preimage vs current source.
## Actual Runtime harvest and explicit isolated C transactions are kept separate.
const Baseline=preload("res://tests/world/fixtures/environment_before_entity_refresh.gd")
const BaselineTerrain=preload("res://tests/world/fixtures/terrain_before_entity_refresh.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
var flip:bool=false
var actual_old:Node3D
var actual_new:Node3D
var actual_events:Array=[]
var command_sequence:int=0
func commit_pair(ops:Array,a:Node3D,b:Node3D,label:String,summary_only:bool=false)->Dictionary:
	var tx:Dictionary=world.prepare_changes(ops,world.get_revision())
	var result:Dictionary=world.commit_prepared(tx.capability) if tx.ok else tx
	check(label+" sole C fixture transaction",result.ok,result.get("reason"))
	if not result.ok:return result
	var notification:Dictionary=result.changes.duplicate(true)
	if summary_only:notification.erase("operations")
	var old_ms:float;var new_ms:float;var started:int
	if flip:
		started=Time.get_ticks_usec();b.on_world_changed(notification);new_ms=(Time.get_ticks_usec()-started)/1000.0
		started=Time.get_ticks_usec();a.on_world_changed(notification);old_ms=(Time.get_ticks_usec()-started)/1000.0
	else:
		started=Time.get_ticks_usec();a.on_world_changed(notification);old_ms=(Time.get_ticks_usec()-started)/1000.0
		started=Time.get_ticks_usec();b.on_world_changed(notification);new_ms=(Time.get_ticks_usec()-started)/1000.0
	flip=not flip
	if not costs.has("isolated_notifications"):costs.isolated_notifications=[]
	costs.isolated_notifications.append({"label":label,"old_ms":old_ms,"new_ms":new_ms,"new_first":not flip,"changed_entities":result.changes.entities,"changed_chunks":result.changes.chunks.size(),"candidate_patches":b.statistics().last_ecology_candidates,"scope":"explicit C transaction fixture, alternating old/new notify order; never normal harvesting or OS/FPS"})
	compare(a,b,label)
	return result
func replace_entity(e:Dictionary,a:Node3D,b:Node3D,label:String,summary_only:bool=false)->Dictionary:
	var before:Dictionary=world.entity(e.id)
	return commit_pair([{"op":"entity.put","id":e.id,"before_exists":not before.is_empty(),"before":before if not before.is_empty() else null,"after":e}],a,b,label,summary_only)
func supported_patches(view:Node3D)->Array:
	var visible:Array=ids(view);var rows:Array=[]
	for patches:Array in view._ecology_patch_index.values():
		for patch:Dictionary in patches:
			if patch.id in visible:rows.append(patch)
	return rows
func fixture_entity(id:String,patch:Dictionary,foundation:bool=false)->Dictionary:
	var p:Dictionary=patch.position.duplicate(true)
	return {"id":id,"kind":"structure" if foundation else "fixture-prop","regionId":world.region_at(p).id,"position":p,"bounds":{"min":{"x":p.x-1.0,"y":p.y-0.2 if foundation else p.y,"z":p.z-1.0},"max":{"x":p.x+1.0,"y":p.y if foundation else p.y+2.0,"z":p.z+1.0}},"revision":0,"tags":["foundation"] if foundation else [],"data":{"solid":not foundation,"structure":{"hp":100.0}}}
func fixtures(a:Node3D,b:Node3D)->void:
	var tree:Dictionary={}
	for id:String in b._roots:
		var e:Dictionary=world.entity(id)
		if e.data.get("harvest",{}).get("phase")=="standing":tree=e;break
	check("real24 fixture has original live tree",not tree.is_empty())
	if tree.is_empty():return
	var original:String=signature(b)
	for i:int in 8:
		var after:Dictionary=tree.duplicate(true)
		if i%2==0:
			after.data.harvest.phase="stump";after.data.solid=false;after.data.opaque=false
			after.bounds=Geometry.json_box(AABB(Geometry.point(after.position)-Vector3(0.25,0,0.25),Vector3(0.5,0.3,0.5)))
		replace_entity(after,a,b,"isolated tree phase %d"%i)
	check("eight alternating stump/standing fixtures restore exact native output",signature(b)==original)
	var snapshots:Dictionary={};var untouched:String=""
	for id:String in b._roots:
		if id!=tree.id:untouched=id;snapshots.id=b._roots[id].get_instance_id();break
	var changed:Dictionary=tree.duplicate(true);changed.data.appearance.height=float(tree.data.appearance.height)+0.5;changed.data.appearance.yaw+=0.2
	replace_entity(changed,a,b,"isolated tree crown scale yaw deformation")
	check("unaffected tree keeps actual same native node",b._roots[untouched].get_instance_id()==snapshots.id)
	var moved:Dictionary=world.entity(tree.id)
	var point:Dictionary=moved.position.duplicate(true);point.x+=3.0;point.z+=1.0
	var ground:Variant=world.surface_height(point.x,point.z)
	check("tree move fixture has real known destination surface",ground!=null)
	if ground!=null:
		point.y=float(ground);var delta:Vector3=Geometry.point(point)-Geometry.point(moved.position)
		moved.position=point
		for side:String in ["min","max"]:
			moved.bounds[side].x+=delta.x;moved.bounds[side].y+=delta.y;moved.bounds[side].z+=delta.z
		replace_entity(moved,a,b,"isolated real-surface tree movement old and new crown footprints")
		check("moved tree actual root transform follows current entity",b._roots.has(tree.id) and b._roots[tree.id].position==Geometry.point(point))
	var other:Dictionary=world.entity(tree.id);other.kind="fixture-prop"
	replace_entity(other,a,b,"isolated tree becomes non-tree")
	check("kind transition removes tree mesh and collider synchronously",not b._roots.has(tree.id))
	replace_entity(tree,a,b,"isolated tree kind and geometry restoration",true)
	check("IDs-only complete summary restores same tree geometry",signature(b)==original)
	var patches:Array=supported_patches(a);var first:Dictionary=patches[0];var second:Dictionary={}
	for patch:Dictionary in patches:
		if Geometry.point(patch.position).distance_to(Geometry.point(first.position))>12:second=patch;break
	check("blocker fixture uses two actually visible distinct support neighborhoods",not second.is_empty())
	if second.is_empty():return
	var blocker:Dictionary=fixture_entity("fixture:entity-refresh:blocker",first)
	replace_entity(blocker,a,b,"isolated new solid blocker")
	check("new actual blocker hides intersecting grass immediately",first.id not in ids(b))
	blocker=fixture_entity(blocker.id,second)
	replace_entity(blocker,a,b,"isolated blocker old and new footprints")
	check("moving blocker restores old and hides new patch",first.id in ids(b) and second.id not in ids(b))
	blocker=world.entity(blocker.id)
	blocker.bounds.min.x-=9;blocker.bounds.min.z-=9;blocker.bounds.max.x+=9;blocker.bounds.max.z+=9
	replace_entity(blocker,a,b,"isolated wide blocker deformation across diagonal chunk bins")
	blocker=world.entity(blocker.id);blocker.bounds.min.y+=9;blocker.bounds.max.y+=9
	replace_entity(blocker,a,b,"isolated elevated blocker vertical separation")
	check("vertical separation restores grounded plants",second.id in ids(b))
	blocker=fixture_entity(blocker.id,second);blocker.data.solid=false;blocker.blocksTerrain=true;blocker.data.module_target=true
	replace_entity(blocker,a,b,"isolated module-target blocker branch")
	check("blocksTerrain module branch retains exact obstruction",second.id not in ids(b))
	commit_pair([{"op":"entity.remove","id":blocker.id,"before":world.entity(blocker.id)}],a,b,"isolated blocker deletion")
	check("removed blocker releases prior support neighborhood",second.id in ids(b) and not b._entities_by_id.has(blocker.id))
	var contact_patch:Dictionary={}
	for patch:Dictionary in patches:
		if b._grounded(Geometry.point(patch.position),Vector2(2.8,2.8),1):contact_patch=patch;break
	check("contact fixture uses verified full grass support around all exterior edges",not contact_patch.is_empty())
	if contact_patch.is_empty():return
	var foundation:Dictionary=fixture_entity("fixture:entity-refresh:foundation",contact_patch,true)
	replace_entity(foundation,a,b,"isolated grass foundation contact addition")
	check("actual grass support creates contact mesh",b.statistics().foundation_contact_quads>0,b.statistics())
	foundation=fixture_entity(foundation.id,second,true)
	replace_entity(foundation,a,b,"isolated foundation movement across footprints")
	foundation=world.entity(foundation.id);foundation.data.structure.hp=0
	replace_entity(foundation,a,b,"isolated foundation destruction")
	check("zero HP foundation releases all its contact faces",b.statistics().foundation_contact_quads==0)
	commit_pair([{"op":"entity.remove","id":foundation.id,"before":world.entity(foundation.id)}],a,b,"isolated foundation deletion")
	var remove_id:String=str(tree.id)
	commit_pair([{"op":"entity.remove","id":remove_id,"before":world.entity(remove_id)}],a,b,"isolated tree deletion")
	check("deleted tree retires mesh collider and cached projection",not b._roots.has(remove_id) and not b._entities_by_id.has(remove_id))
	var added:Dictionary=tree.duplicate(true);added.id="fixture:entity-refresh:new-tree"
	replace_entity(added,a,b,"isolated fresh stable tree ID")
	check("new tree builds full model and actual collider",b._roots.has(added.id))
	# Cold and mixed edits deliberately retain the complete original fallback.
	var region:String=str(tree.regionId)
	var cold:Dictionary=world.prepare_region_residency(region,false,world.get_revision())
	commit_pair(cold.world_changes,a,b,"isolated real compressed cold region")
	added=world.entity(added.id);added.data.appearance.yaw+=0.3
	replace_entity(added,a,b,"isolated entity edit while compressed cold")
	check("cold edited entity cannot retain stale native tree",not b._roots.has(added.id))
	var warm:Dictionary=world.prepare_region_residency(region,true,world.get_revision())
	commit_pair(warm.world_changes,a,b,"isolated full warm edited entity")
	check("warm rebuild uses actual edited entity appearance",b._roots.has(added.id))
	var p:Dictionary=added.position;var cell:Dictionary={"x":floori(p.x*2),"y":roundi(p.y*2)-1,"z":floori(p.z*2)}
	var mat:int=world.cell_at(cell.x,cell.y,cell.z);var before:Dictionary=world.entity(added.id);added=before.duplicate(true);added.data.appearance.height+=0.25
	commit_pair([{"op":"entity.put","id":added.id,"before_exists":true,"before":before,"after":added},{"op":"voxel.set","cell":cell,"before":mat,"after":0}],a,b,"isolated mixed entity and support dig")
	check("mixed dig has no unsupported tree collider",not b._roots.has(added.id))
	commit_pair([{"op":"voxel.set","cell":cell,"before":0,"after":mat}],a,b,"isolated support refill")
	check("refill restores current edited tree",b._roots.has(added.id))
	# Missing a valid notification must trigger revision-gap fallback next time.
	before=world.entity(added.id);added=before.duplicate(true);added.data.appearance.yaw+=0.4
	var tx:Dictionary=world.prepare_changes([{"op":"entity.put","id":added.id,"before_exists":true,"before":before,"after":added}],world.get_revision())
	if tx.ok:world.commit_prepared(tx.capability)
	var trigger:Dictionary=tree.duplicate(true);trigger.id="fixture:entity-refresh:gap-trigger"
	replace_entity(trigger,a,b,"isolated missed notification revision-gap fallback")
	check("gap fallback updates both changed entities from full current authority",b._entities_by_id[added.id]==world.entity(added.id))
	before=world.entity(added.id);added=before.duplicate(true);added.data.appearance.yaw+=0.5
	tx=world.prepare_changes([{"op":"entity.put","id":added.id,"before_exists":true,"before":before,"after":added}],world.get_revision())
	if tx.ok:world.commit_prepared(tx.capability)
	a.on_world_changed({"entities":[added.id]});b.on_world_changed({"entities":[added.id]})
	compare(a,b,"unknown missing chunks summary full fallback")
	a.on_world_changed({"reload":true});b.on_world_changed({"reload":true})
	compare(a,b,"explicit reload full fallback")
	# Unknown malformed operation summaries take the full path, never trust IDs.
	a.sync();b.on_world_changed({"operations":["unknown"],"entities":[added.id],"chunks":[]})
	compare(a,b,"unknown operation payload full fallback")
	var checkpoint:Dictionary=world.snapshot()
	var encoded:Dictionary=Codec.encode_checkpoint(checkpoint,{},"entity-refresh-fixture-cold")
	var decoded:Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
	var loaded:Dictionary=world.load_snapshot(decoded.state) if decoded.ok else decoded
	check("isolated edited authority cold codec restore",loaded.ok)
	a.on_world_changed({"reload":true});b.on_world_changed({"reload":true})
	compare(a,b,"cold codec consumer reload")
	var revived:Dictionary=world.prepare_region_residency(region,true,world.get_revision())
	commit_pair(revived.world_changes,a,b,"isolated edited saved region revisit")
	check("save revisit preserves tree identities and retired deleted identity",b._roots.has(added.id) and world.entity(remove_id).is_empty())
func send_actual(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={})->Dictionary:
	command_sequence+=1
	return runtime.command({"command_id":"r34:c:entity-refresh:%d"%command_sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload})
func raw_differences(a:Variant,b:Variant,path:String,rows:Array)->void:
	if Data.json_equal(a,b) or rows.size()>=64:return
	if a is Dictionary and b is Dictionary:
		for key:Variant in a:
			if b.has(key):raw_differences(a[key],b[key],path+"/"+str(key),rows)
			else:rows.append({"path":path+"/"+str(key),"missing":true})
	elif a is Array and b is Array and a.size()==b.size():
		for i:int in a.size():raw_differences(a[i],b[i],path+"/"+str(i),rows)
	else:
		var row:Dictionary={"path":path,"before":a,"decoded":b}
		if (a is int or a is float) and (b is int or b is float):row.before_f64_le=PackedFloat64Array([float(a)]).to_byte_array().hex_encode();row.decoded_f64_le=PackedFloat64Array([float(b)]).to_byte_array().hex_encode()
		rows.append(row)
func actual_notification(notification:Dictionary)->void:
	var ops:Array=notification.get("world",[])
	if not ops.any(func(op:Dictionary)->bool:return op.get("op")=="entity.put"):return
	var row:Dictionary={"notification":notification,"old_environment_usec":actual_old.statistics().last_environment_sync_usec,"new_environment_usec":actual_new.statistics().last_environment_sync_usec,"old_terrain_notify_usec":actual_old.statistics().last_notification_usec,"new_terrain_notify_usec":actual_new.statistics().last_notification_usec,"exact_native_output":signature(actual_old.environment)==signature(actual_new.environment),"old_stats":actual_old.environment.statistics(),"new_stats":actual_new.environment.statistics()}
	actual_events.append(row)
func real_harvest(host:Node3D,input:String,output:String)->void:
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input))
	var built:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded
	check("unaltered original19 normal53 loads through actual Native",built.get("ok",false))
	if not built.get("ok",false):return
	var runtime:RefCounted=built.runtime;var live:RefCounted=built.world
	actual_old=BaselineTerrain.new();actual_new=Terrain.new();root.add_child(actual_old);root.add_child(actual_new);actual_old.set_process(false);actual_new.set_process(false)
	actual_old.configure({"world":live,"runtime":runtime});actual_new.configure({"world":live,"runtime":runtime});actual_old.cancel_pending();actual_new.cancel_pending()
	var initial:Dictionary=runtime.capture_checkpoint();var axe:String="r34:generated:RH-HOME:woodwork:tool:salvaged_axe";var commands:Array=[]
	check("actual normal tool is held and has durability",runtime.tool(axe).get("holderId")=="pack:player" and float(runtime.tool(axe).get("durability",0))>15)
	var trees:Array=live.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a.position).distance_squared_to(Geometry.point(runtime.actor("player")))<Geometry.point(b.position).distance_squared_to(Geometry.point(runtime.actor("player"))))
	var felled:int=0
	for tree:Dictionary in trees.slice(0,12):
		if felled==2:break
		if float(runtime.actor("player").stamina)<70:
			var rest:Dictionary=send_actual(runtime,"rest");var rest_ticks:int=0
			while rest.ok and runtime.actor("player").get("intent")!=null and rest_ticks<500:runtime.tick(0.1);rest_ticks+=1
			commands.append({"kind":"actual-rest-before-next-harvest","command":rest,"ticks":rest_ticks,"actual_stamina":runtime.actor("player").stamina})
			check("normal rest restores actual stamina before subsequent harvest",rest.ok and runtime.actor("player").get("intent")==null and float(runtime.actor("player").stamina)>70)
		var available:Dictionary=runtime.availability({"actor_id":"player","kind":"harvest","target_id":tree.id,"payload":{"direct":false,"tool_ids":[axe]}})
		if not available.ok:commands.append({"target":tree.id,"availability":available});continue
		# Actual signal order is reversed on the second real harvest.
		runtime.changed.disconnect(actual_old.on_world_changed);runtime.changed.disconnect(actual_new.on_world_changed)
		if runtime.changed.is_connected(actual_notification):runtime.changed.disconnect(actual_notification)
		if felled%2==0:runtime.changed.connect(actual_old.on_world_changed);runtime.changed.connect(actual_new.on_world_changed)
		else:runtime.changed.connect(actual_new.on_world_changed);runtime.changed.connect(actual_old.on_world_changed)
		runtime.changed.connect(actual_notification)
		var before_actor:Dictionary=runtime.actor("player");var before_tool:Dictionary=runtime.tool(axe);var drop:Dictionary=runtime.stock(tree.data.outputId)
		var request:Dictionary=send_actual(runtime,"harvest",tree.id,{"direct":false,"tool_ids":[axe]});var intent:Variant=runtime.actor("player").get("intent");var ticks:int=0
		while request.ok and runtime.actor("player").get("intent")!=null and ticks<1600:runtime.tick(0.1);ticks+=1
		var after:Dictionary=live.entity(tree.id)
		var ok:bool=request.ok and runtime.actor("player").get("intent")==null and after.data.harvest.phase=="stump" and runtime.stock(tree.data.outputId).items.get("log",0)==drop.items.get("log",0)+3
		commands.append({"target":tree.id,"command":request,"initial_actual_intent":intent,"before_actor":before_actor,"after_actor":runtime.actor("player"),"before_tool":before_tool,"after_tool":runtime.tool(axe),"before_drop":drop,"after_drop":runtime.stock(tree.data.outputId),"tree_before":tree,"tree_after":after,"ticks":ticks,"actual":ok})
		check("real command B approach labor tool wear unique stump and3log "+str(felled+1),ok and float(runtime.tool(axe).durability)<float(before_tool.durability),request.get("reason"))
		if not ok:break
		felled+=1
	check("two real Runtime harvests without fixture supply or relocation",felled==2)
	check("every actual entity event synchronously matches exact old native output",not actual_events.is_empty() and actual_events.all(func(e:Dictionary)->bool:return e.exact_native_output),actual_events.size())
	var final:Dictionary=runtime.capture_checkpoint();var saved:Dictionary=Store.encode(final);var recovered:Dictionary=Store.decode(saved.text) if saved.get("ok",false) else saved
	check("actual post-harvest full Native cold checkpoint recovers",recovered.get("ok",false))
	if recovered.get("ok",false):
		FileAccess.open(output.get_base_dir()+"/actual-before-encode.json",FileAccess.WRITE).store_string(JSON.stringify({"facts":final.facts,"receipts":final.receipts,"simulation":final.simulation},"\t",true,true))
		FileAccess.open(output.get_base_dir()+"/actual-after-decode.json",FileAccess.WRITE).store_string(JSON.stringify({"facts":recovered.capture.facts,"receipts":recovered.capture.receipts,"simulation":recovered.capture.simulation},"\t",true,true))
	var raw:Dictionary={"facts_exact":Data.json_equal(final.facts,recovered.capture.facts),"receipts_exact":Data.json_equal(final.receipts,recovered.capture.receipts),"simulation_exact":Data.json_equal(final.simulation,recovered.capture.simulation),"differences":[],"difference_sample_limit":64}
	for key:String in ["facts","receipts","simulation"]:raw_differences(final[key],recovered.capture[key],key,raw.differences)
	raw.sample_truncated=raw.differences.size()>=64
	var restored:Dictionary=host._assemble(recovered.capture) if recovered.get("ok",false) else recovered
	check("actual canonical decoded facts tools ledger receipts and simulation restore strictly",restored.get("ok",false) and Data.json_equal(recovered.capture.facts,restored.runtime.capture_checkpoint().facts) and Data.json_equal(recovered.capture.receipts,restored.runtime.capture_checkpoint().receipts) and Data.json_equal(recovered.capture.simulation,restored.runtime.capture_checkpoint().simulation))
	if restored.get("ok",false):restored.runtime.retire()

	var saved_stumps:bool=true
	for command:Dictionary in commands:
		if command.get("actual",false):saved_stumps=saved_stumps and recovered.capture.world.entities[command.target].data.harvest.phase=="stump"
	check("actual harvested persistent IDs stay stumps after native cold decode",saved_stumps)
	if saved.get("ok",false):FileAccess.open(output.get_base_dir()+"/actual-harvest-completed.native.json",FileAccess.WRITE).store_string(saved.text)
	costs.actual_normal={"input":input,"input_sha256":FileAccess.get_sha256(input),"commands":commands,"events":actual_events,"raw_live_to_decoded_observation":raw,"initial_clock":initial.facts.time,"final_clock":final.facts.time,"scope":"real19 normal53 immutable input, original commands/Runtime/B approach/tool wear/yield; no fixture, inventory grant, teleport or OS/renderer/FPS qualification"}
	actual_old.cancel_pending();actual_new.cancel_pending();actual_old.free();actual_new.free();runtime.retire()
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=3:quit(2);return
	var output:String=args[0];var input:String=args[1];var normal:String=args[2]
	var sha_input:String=FileAccess.get_sha256(input);var sha_normal:String=FileAccess.get_sha256(normal)
	check("exact A original24 input",sha_input=="ef226d9ddcc26834acb691bfec09623fbb32c7408804a1575ce9887a2f26ae48")
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input));var host:=DiagnosticClient.new();root.add_child(host);host.set_process(false)
	var built:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded
	check("actual Native real24 assembly",built.get("ok",false) and built.world.chunk_keys().size()==6144)
	if not built.get("ok",false):return finish(output)
	world=built.world
	costs.real24_entity_count=world.entities().size()
	var a:=Baseline.new();var b:=EnvironmentView.new();root.add_child(a);root.add_child(b)
	a.configure({"world":world});b.configure({"world":world,"materials":a.materials})
	compare(a,b,"initial adopted86 vs entity candidate")
	fixtures(a,b)
	a.free();b.free();built.runtime.retire()
	real_harvest(host,normal,output)
	host.free()
	check("both explicit input files unchanged",FileAccess.get_sha256(input)==sha_input and FileAccess.get_sha256(normal)==sha_normal)
	costs.scope="C source actual entity notification/derived consistency and explicit isolated fixture CPU; not candidate20 adoption, original19 package execution or OS/FPS/RSS/VA/G5"
	finish(output)
