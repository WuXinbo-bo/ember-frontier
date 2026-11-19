extends "res://tests/world/environment_refresh_followup.gd"
## Actual unchanged own22 input and real Runtime commands, no fixture mutation.
const CurrentBeforeTerrain=preload("res://tests/world/fixtures/terrain_before_refresh_followup.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
var actual_old:Node3D
var actual_new:Node3D
var actual_events:Array=[]
var command_sequence:int=0
var ordinary_events:int=0
var ordinary_max_refresh_delta:int=0
var prior_counts:Array=[]
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
	if ops.is_empty():
		ordinary_events+=1
		var counts:Array=[actual_old.environment.sync_passes,actual_new.environment.sync_passes]
		if not prior_counts.is_empty():ordinary_max_refresh_delta=maxi(ordinary_max_refresh_delta,maxi(counts[0]-prior_counts[0],counts[1]-prior_counts[1]))
		prior_counts=counts
		return
	prior_counts=[actual_old.environment.sync_passes,actual_new.environment.sync_passes]
	if not ops.any(func(op:Dictionary)->bool:return op.get("op")=="entity.put"):return
	var row:Dictionary={"notification":notification,"old_environment_usec":actual_old.statistics().last_environment_sync_usec,"new_environment_usec":actual_new.statistics().last_environment_sync_usec,"old_terrain_notify_usec":actual_old.statistics().last_notification_usec,"new_terrain_notify_usec":actual_new.statistics().last_notification_usec,"exact_native_output":signature(actual_old.environment)==signature(actual_new.environment),"old_stats":actual_old.environment.statistics(),"new_stats":actual_new.environment.statistics()}
	actual_events.append(row)
func real_harvest(host:Node3D,input:String,output:String)->void:
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input))
	var built:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded
	check("unaltered own22 normal53 loads through actual Native",built.get("ok",false))
	if not built.get("ok",false):return
	var runtime:RefCounted=built.runtime;var live:RefCounted=built.world
	actual_old=CurrentBeforeTerrain.new();actual_new=Terrain.new();root.add_child(actual_old);root.add_child(actual_new);actual_old.set_process(false);actual_new.set_process(false)
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
		prior_counts=[actual_old.environment.sync_passes,actual_new.environment.sync_passes]
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
	costs.actual_normal={"input":input,"input_sha256":FileAccess.get_sha256(input),"commands":commands,"events":actual_events,"raw_live_to_decoded_observation":raw,"initial_clock":initial.facts.time,"final_clock":final.facts.time,"scope":"own22 normal53 immutable input, original commands/Runtime/B approach/tool wear/yield; no fixture, inventory grant, teleport or OS/renderer/FPS qualification"}
	actual_old.cancel_pending();actual_new.cancel_pending();actual_old.free();actual_new.free();runtime.retire()
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2:quit(2);return
	var output:String=args[0];var normal:String=args[1];var input_sha:String=FileAccess.get_sha256(normal)
	check("exact own22 real normal53 input",input_sha=="0fa0c1fa5710e1e28ea6d4641b949e8d3175cf4d3d9d4e3be089c16ff0c39566")
	var host:=DiagnosticClient.new();root.add_child(host);host.set_process(false)
	await real_harvest(host,normal,output)
	check("ordinary real clock/movement/labor notifications never invoke environment sync",ordinary_events>0 and ordinary_max_refresh_delta==0,{"events":ordinary_events,"max_refresh_delta":ordinary_max_refresh_delta})
	check("direct input byte identity preserved",FileAccess.get_sha256(normal)==input_sha)
	costs.ordinary={"events":ordinary_events,"max_refresh_delta":ordinary_max_refresh_delta}
	host.free();finish(output)
