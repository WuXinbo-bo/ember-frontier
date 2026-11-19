extends SceneTree
## Tests only: actual Native scheduler/registration from build18 normal53.
## No renderer, actor relocation, altered capture, resource grant or second tick.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Factory=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Residency=preload("res://scripts/runtime/region_residency.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const TOTAL_MSEC:int=90000
const REGION_MSEC:int=15000
class HeadlessNative extends Native:
	func _ready()->void:pass
var host:Node3D
var checks:Array=[]
var rows:Array=[]
var tiers:Array=[]
var storage_rows:Array=[]
var restore_rows:Array=[]
var original:Dictionary={}
var original_modules:Dictionary={}
var original_stocks:Dictionary={}
var original_plans:Dictionary={}
var original_rasters:Dictionary={}
var expected_ledger:Array=[]
var observed_events:Dictionary={}
var report_path:String
var output:String
var input_path:String
var input_sha:String
var target:int=24
var began:int
var stop_reason:String=""
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func failed()->int:return checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
static func index(rows_in:Array)->Dictionary:
	var found:Dictionary={}
	for row:Dictionary in rows_in:
		if found.has(row.id):return {}
		found[row.id]=row
	return found
func raster(id:String)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	var keys:Array=host.world.region_chunk_keys(id);keys.sort()
	for key:String in keys:
		hash.update(key.to_utf8_buffer());hash.update(host.world.chunk(key).cells.to_byte_array())
	return hash.finish().hex_encode()
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<2:quit(2);return
	report_path=args[0];output=report_path.get_base_dir();input_path=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	target=int(args[2]) if args.size()>2 else 24;began=Time.get_ticks_msec()
	check("explicit bounded target is 4/8/12/24",target in [4,8,12,24])
	if failed()>0:finish();return
	input_sha=FileAccess.get_sha256(input_path)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input_path))
	check("actual explicit build18 normal53 envelope decodes",decoded.get("ok",false),decoded.get("reason"))
	if not decoded.get("ok",false):finish();return
	var policy:Dictionary=decoded.capture.world.extensions.get(Factory.CONFIG_KEY,{})
	check("source retains real content4/story1 configuration",policy.get("content_version")==4 and policy.get("story_clue_version")==1 and decoded.capture.facts.scenario==Factory.SCENARIO)
	if failed()>0:finish();return
	host=HeadlessNative.new();host.store=Store.new(output+"/isolated-manual/saves");host.controls_path=output+"/controls.json"
	root.add_child(host);host.set_process(false);host.set_physics_process(false)
	var built:Dictionary=host._assemble(decoded.capture)
	check("actual Native validates all original owners and bodies",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):finish();return
	host.world=built.world;host.runtime=built.runtime;host._world_epoch=1
	host._regions.attach(built.runtime,built.services.buildings,1,built.services.modules)
	host._stream_store=Store.new(output+"/isolated-stream/saves")
	original=host.runtime.capture_checkpoint()
	expected_ledger=original.facts.get("ledger",[]).duplicate(true)
	host.runtime.changed.connect(observe_commit)
	check("assembly preserves complete canonical source facts",Data.json_equal(original.facts,decoded.capture.facts))
	check("three original identities and no fabricated population",original.facts.actors.size()==3)
	original_modules=index(host.runtime._services.modules.state().instances)
	original_stocks=index(original.facts.stocks)
	for region:Dictionary in host.world.regions():
		original_plans[region.id]=host.world.extension("generation:"+str(region.id));original_rasters[region.id]=raster(region.id)
	check("normal53 contains actual paid expansion and original generated places",original_modules.size()>2 and original_modules.values().any(func(v:Dictionary)->bool:return v.get("player_built",false)))
	var known:Array[Vector2i]=[]
	for region:Dictionary in host.world.regions():
		var at:Dictionary=region.data.regionCoord;known.append(Vector2i(int(at.x),int(at.z)))
	var remaining:Array[Vector2i]=[]
	for z:int in range(-2,3):
		for x:int in range(-2,3):
			var p:=Vector2i(x,z)
			if p not in known and p!=Vector2i(2,2):remaining.append(p)
	while host.world.regions().size()<target:
		if Time.get_ticks_msec()-began>TOTAL_MSEC:stop_reason="bounded total CPU/wall precheck budget";break
		var selected:int=-1
		for i:int in remaining.size():
			if known.any(func(p:Vector2i)->bool:return absi(p.x-remaining[i].x)+absi(p.y-remaining[i].y)==1):selected=i;break
		if selected<0:stop_reason="no adjacent coordinate in bounded lattice";break
		var at:Vector2i=remaining.pop_at(selected);var id:String=Factory.region_id(at)
		var started:int=Time.get_ticks_usec();var before_rev:int=host.runtime.get_revision()
		var request:Dictionary=host._regions.request(at)
		if not request.get("ok",false):check("real scheduler admits adjacent "+id,false,request);stop_reason="request rejection";break
		var completed:Dictionary={}
		while host.world.region(id).is_empty() and (Time.get_ticks_usec()-started)/1000<REGION_MSEC:
			var result:Dictionary=host._regions.poll(0.0,true)
			if not result.is_empty():completed=result
			if not completed.is_empty() and not completed.get("ok",false):break
			await create_timer(0.005).timeout
		var done:bool=not host.world.region(id).is_empty() and completed.get("ok",false)
		rows.append({"region_id":id,"coord":{"x":at.x,"z":at.y},"elapsed_usec":Time.get_ticks_usec()-started,"ok":done,"code":completed.get("code",request.get("code")),"command_revision_before":before_rev,"command_revision_after":host.runtime.get_revision(),"scheduler":host._regions.status()})
		check("real Native scheduler C+B registration commits "+id,done,rows[-1])
		if not done:stop_reason="generation/registration/authority rejected or timed out";break
		known.append(at)
		var count:int=host.world.regions().size()
		if count in [4,8,12,24]:
			if not milestone(count):stop_reason="joint milestone invariant failure";break
			if count in [4,12,24]:
				if not await storage_cycle(count):stop_reason="Native cold/warm storage failure";break
				if not save_restore(count):stop_reason="Native full save/cold assembly failure";break
			write_report(true)
	check("bounded requested joint scale actually reached",host.world.regions().size()==target,{"actual":host.world.regions().size(),"target":target,"stop_reason":stop_reason})
	if host.world.regions().size()==24:
		var before:Dictionary=host.runtime.capture_checkpoint()
		var refusal:Dictionary=host._regions.request(Vector2i(2,2))
		check("25th real adjacent request refuses finite capacity atomically",not refusal.ok and refusal.code=="GENERATION_CAPACITY" and Data.json_equal(before,host.runtime.capture_checkpoint()),refusal)
	if failed()==0:
		var before:Dictionary=host.runtime.capture_checkpoint();var ids:Array=host.world.regions().map(func(r:Dictionary)->String:return r.id);ids.reverse()
		var revisit:bool=true
		for id:String in ids:
			var at:Dictionary=host.world.region(id).data.regionCoord
			var again:Dictionary=host._regions.request(Vector2i(int(at.x),int(at.z)))
			if not again.ok or again.code!="ALREADY_GENERATED":revisit=false
		var registration:Dictionary=host.runtime._services.modules.prepare_generation(host.world)
		check("reverse data revisit never regenerates known regions",revisit and Data.json_equal(before,host.runtime.capture_checkpoint()))
		check("B once-only receipts prevent duplicate buffers or supplies",registration.ok and registration.world_changes.is_empty() and registration.initial_stocks.is_empty() and registration.initial_tools.is_empty() and registration.initial_records.is_empty(),registration.get("code"))
		check("original normal53 identities work and inventory remain exact",original_exact())
	check("real input envelope bytes remain untouched",input_sha==FileAccess.get_sha256(input_path))
	finish()
func original_exact()->bool:
	return original_difference().is_empty()
func observe_commit(changes:Dictionary)->void:
	for i:int in changes.get("events",[]).size():
		var event:Dictionary=changes.events[i].duplicate(true)
		var kind:String=str(event.get("kind",""))
		check("only requested generation/storage events without simulation",kind in ["region_generated","region-storage-changed"],event)
		observed_events[kind]=int(observed_events.get(kind,0))+1
		event.id="event:%s:%s"%[changes.revision,i];event.revision=changes.revision;event.time=host.runtime.clock()
		expected_ledger.append(event)
	while expected_ledger.size()>256:expected_ledger.pop_front()
static func without_ledger(facts:Dictionary)->Dictionary:
	var result:Dictionary=facts.duplicate(true);result.erase("ledger");return result
func original_difference()->Dictionary:
	var facts:Dictionary=host.runtime.facts()
	for key:Variant in original.facts:
		if key not in ["stocks","ledger"] and not Data.json_equal(original.facts[key],facts.get(key)):return first_difference(original.facts[key],facts.get(key),"original/facts/"+str(key))
	if not Data.json_equal(expected_ledger,facts.get("ledger")):return first_difference(expected_ledger,facts.get("ledger"),"expected-bounded-ledger")
	var stocks:Dictionary=index(facts.stocks);var instances:Dictionary=index(host.runtime._services.modules.state().instances)
	for id:String in original_stocks:
		if not Data.json_equal(original_stocks[id],stocks.get(id)):return first_difference(original_stocks[id],stocks.get(id),"original/stock/"+id)
	for id:String in original_modules:
		if not Data.json_equal(original_modules[id],instances.get(id)):return first_difference(original_modules[id],instances.get(id),"original/module/"+id)
	for id:String in original_plans:
		if not Data.json_equal(original_plans[id],host.world.extension("generation:"+id)):return first_difference(original_plans[id],host.world.extension("generation:"+id),"original/plan/"+id)
		if original_rasters[id]!=raster(id):return {"path":"original/raster/"+id,"before":original_rasters[id],"after":raster(id)}
	var captured:Dictionary=host.runtime.capture_checkpoint()
	for key:String in ["schemaVersion","worldId","seed","generatorVersion","config","retiredEntityIds"]:
		if not Data.json_equal(original.world.get(key),captured.world.get(key)):return first_difference(original.world.get(key),captured.world.get(key),"original/world/"+key)
	for collection:String in ["regions","entities"]:
		for id:String in original.world[collection]:
			if not Data.json_equal(original.world[collection][id],captured.world[collection].get(id)):return first_difference(original.world[collection][id],captured.world[collection].get(id),"original/"+collection+"/"+id)
	for id:String in original.world.extensions:
		if id.begins_with("generation:"):continue
		var before:Variant=original.world.extensions[id];var after:Variant=captured.world.extensions.get(id)
		var append_fields:Array=["instances","source_receipts"] if id==Modules.KEY else ["instances","storeys"] if id=="r3:structures" else ["tools","records"] if id=="r3:production" else []
		if append_fields.is_empty():
			if not Data.json_equal(before,after):return first_difference(before,after,"original/extension/"+id)
			continue
		if not after is Dictionary or before.size()!=after.size():return {"path":"original/extension/"+id,"reason":"owner field cardinality"}
		for field:String in before:
			if field not in append_fields:
				if not Data.json_equal(before[field],after.get(field)):return first_difference(before[field],after.get(field),"original/extension/"+id+"/"+field)
			elif before[field] is Array:
				var current:Dictionary=index(after[field])
				for row:Dictionary in before[field]:
					if not Data.json_equal(row,current.get(row.id)):return first_difference(row,current.get(row.id),"original/extension/"+id+"/"+field+"/"+str(row.id))
			else:
				for key:String in before[field]:
					if not Data.json_equal(before[field][key],after[field].get(key)):return first_difference(before[field][key],after[field].get(key),"original/extension/"+id+"/"+field+"/"+key)
	for key:String in ["content","source","simulation","receipts"]:
		if not Data.json_equal(original.get(key),captured.get(key)):return first_difference(original.get(key),captured.get(key),"original/"+key)
	return {}
func milestone(count:int)->bool:
	var was:int=failed();var started:int=Time.get_ticks_usec()
	var modules:Dictionary=host.runtime._services.modules.state();var instances:Dictionary=index(modules.instances)
	var facts:Dictionary=host.runtime.facts();var stocks:Dictionary=index(facts.stocks)
	var structure_ids:Dictionary=index(host.runtime._services.buildings.structures(host.world).instances)
	var errors:Array=[];var buffers:int=0;var generated:int=0;var member_ids:Dictionary={};var allowed_stocks:Dictionary={}
	var source_ids:Dictionary={}
	for region:Dictionary in host.world.regions():
		var plan:Dictionary=host.world.extension("generation:"+str(region.id))
		if plan.get("generation_content_version")!=4 or plan.get("configuration_sha256")!=Contract.digest(original.world.extensions[Factory.CONFIG_KEY]):errors.append("plan contract "+str(region.id))
		for seed:Dictionary in plan.get("module_seeds",[]):
			generated+=1;var v:Dictionary=instances.get(seed.id,{});var receipt:Dictionary=modules.source_receipts.get(seed.source_key,{})
			if v.is_empty() or v.get("source_key")!=seed.source_key or v.get("region")!=region.id or v.get("definition_id")!=seed.definition_id or v.get("definition_version")!=seed.definition_version or v.get("geometry_version")!=seed.geometry_version or v.get("quarter_turn")!=seed.quarter_turn or v.get("player_built")!=false:errors.append("seed-instance "+str(seed.id));continue
			var expected_stock_ids:Array=v.stock_refs.values();expected_stock_ids.sort()
			var receipt_stock_ids:Array=receipt.get("stock_ids",[]).duplicate();receipt_stock_ids.sort()
			if receipt.get("module_id")!=seed.id or receipt.get("source_key")!=seed.source_key or receipt.get("content_seed")!=seed.content_seed or source_ids.has(seed.source_key) or receipt_stock_ids!=expected_stock_ids:errors.append("source receipt "+str(seed.id))
			source_ids[seed.source_key]=true
	for v:Dictionary in modules.instances:
		for buffer:String in v.stock_refs:
			buffers+=1;var id:String=v.stock_refs[buffer];allowed_stocks[id]=true;var stock:Dictionary=stocks.get(id,{})
			if stock.is_empty() or stock.get("module_id")!=v.id or stock.get("buffer_id")!=buffer or stock.get("owner")!=v.owner:errors.append("real buffer "+id)
		for member:Dictionary in v.members:
			if member_ids.has(member.id) or host.world.entity(str(member.id)).is_empty() or (member.kind=="structure" and not structure_ids.has(member.id)):errors.append("member "+str(member.id))
			member_ids[member.id]=true
	for stock:Dictionary in Factory.initial_resource_stocks(host.world):allowed_stocks[stock.id]=true
	var unexplained:Array=[]
	for id:String in stocks:
		if not original_stocks.has(id) and not allowed_stocks.has(id):unexplained.append(id)
	check("joint region/module/buffer/member/source identities at "+str(count),errors.is_empty() and instances.size()==modules.instances.size() and stocks.size()==facts.stocks.size() and unexplained.is_empty(),{"errors":errors.slice(0,16),"unexplained_new_stocks":unexplained})
	var original_diff:Dictionary=original_difference()
	check("all original actors jobs quantities plans and voxels retained at "+str(count),original_diff.is_empty(),original_diff)
	check("generation lock and normal content lock stay exact at "+str(count),Data.json_equal(original.world.extensions[Factory.CONFIG_KEY],host.world.extension(Factory.CONFIG_KEY)))
	var owners:Dictionary={}
	for name:String in ["modules","production","workforce"]:
		var service:RefCounted=host.runtime._services[name]
		var result:Dictionary=service.validate_extensions(facts) if service.has_method("validate_extensions") else service.validate_extension(facts)
		owners[name]=result
	check("complete actual owner validators still accept at "+str(count),owners.values().all(func(v:Dictionary)->bool:return v.get("ok",false)),owners)
	tiers.append({"regions":count,"chunks":host.world.chunk_keys().size(),"modules":instances.size(),"generated_modules":generated,"buffers":buffers,"source_receipts":modules.source_receipts.size(),"module_member_entities":member_ids.size(),"world_entities":host.world.entities().size(),"stocks":stocks.size(),"actors":facts.actors.size(),"original_actor_ids":facts.actors.map(func(a:Dictionary)->String:return a.id),"world_revision":host.world.get_revision(),"command_revision":host.runtime.get_revision(),"validation_usec":Time.get_ticks_usec()-started,"simulated_time":host.runtime.clock(),"all_original_exact":original_exact()})
	print("JOINT TIER "+JSON.stringify(tiers[-1]));return failed()==was
func storage_cycle(count:int)->bool:
	var was:int=failed();var pins:Dictionary=Residency.required_regions(host.runtime);var id:String=""
	for region:Dictionary in host.world.regions():
		if not pins.has(region.id) and not original_plans.has(region.id):id=region.id;break
	check("actual unpinned generated region exists for storage at "+str(count),not id.is_empty(),pins.keys())
	if id.is_empty():return false
	var before_raster:String=raster(id);var before_facts:Dictionary=host.runtime.facts();var before_modules:Dictionary=host.runtime._services.modules.state()
	var cold:Dictionary=await host._change_residency({"region_id":id,"resident":false})
	check("real Native working checkpoint and cold pages at "+str(count),cold.get("ok",false) and host.world.region_residency_state(id).get("paged",false) and not str(cold.get("checkpoint_sha256","")).is_empty(),cold)
	if not cold.get("ok",false):return false
	var loaded:Dictionary=host._stream_store.load_current()
	check("real isolated stream slot checksum loads at "+str(count),loaded.get("ok",false),loaded.get("reason"))
	var warm:Dictionary=await host._change_residency({"region_id":id,"resident":true})
	check("real Native warm keeps exact raster and authority at "+str(count),warm.get("ok",false) and host.world.region_is_resident(id) and raster(id)==before_raster and Data.json_equal(without_ledger(before_facts),without_ledger(host.runtime.facts())) and Data.json_equal(before_modules,host.runtime._services.modules.state()) and original_exact(),warm.merged({"original_difference":original_difference()}))
	storage_rows.append({"regions":count,"region_id":id,"pins":pins,"cold":cold,"warm":warm,"working_slot":loaded.get("path"),"working_slot_sha256":FileAccess.get_sha256(str(loaded.get("path",""))) if loaded.get("ok",false) else "","raster_sha256":before_raster,"scope":"actual Native storage/data, no derived geometry or renderer readiness assertion"})
	return failed()==was
static func first_difference(a:Variant,b:Variant,path:String="capture")->Dictionary:
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return {"path":path,"reason":"dictionary size"}
		for key:Variant in a:
			if not b.has(key):return {"path":path+"/"+str(key),"reason":"missing"}
			var found:Dictionary=first_difference(a[key],b[key],path+"/"+str(key))
			if not found.is_empty():return found
	elif a is Array and b is Array:
		if a.size()!=b.size():return {"path":path,"reason":"array size"}
		for i:int in a.size():
			var found:Dictionary=first_difference(a[i],b[i],path+"/"+str(i))
			if not found.is_empty():return found
	elif a!=b:return {"path":path,"before":a,"after":b,"before_type":typeof(a),"after_type":typeof(b)}
	return {}
func restored_world_difference(before:Dictionary,built:Dictionary,after:Dictionary)->Dictionary:
	# Codec deliberately stores all resident flags false. Native warms only
	# real dependency pins in batches of 32; compare that exact storage-only
	# transition, including each chunk/global revision. Never change input.
	var pins:Dictionary=Residency.required_regions(built.runtime)
	var expected_revisions:Dictionary={};var revision:int=int(before.revision)
	for id:String in pins:
		var pending:int=0
		for key:String in built.world.region_chunk_keys(id):
			var old:Dictionary=before.chunks[key]
			if old.resident and not old.has("cell_page"):continue
			if pending%32==0:revision+=1
			expected_revisions[key]=revision;pending+=1
	if after.size()!=before.size():return {"path":"world","reason":"root cardinality"}
	for key:Variant in before:
		if key in ["chunks","revision"]:continue
		if not Data.json_equal(before[key],after.get(key)):return first_difference(before[key],after.get(key),"world/"+str(key))
	if after.revision!=revision:return {"path":"world/revision","expected":revision,"after":after.revision}
	if before.chunks.size()!=after.chunks.size():return {"path":"world/chunks","reason":"cardinality"}
	for key:String in before.chunks:
		var expected:Dictionary=before.chunks[key].duplicate(true)
		if expected_revisions.has(key):
			expected.resident=true;expected.revision=expected_revisions[key]
			if expected.has("cell_page"):
				var unpacked:Dictionary=Data.ChunkPage.unpack(expected.cell_page,int(before.config.chunkCells)**3,Data.MATERIALS)
				if not unpacked.ok:return {"path":"world/chunks/"+key,"reason":"saved page invalid"}
				expected.cells=unpacked.cells;expected.erase("cell_page")
		if not Data.json_equal(expected,after.chunks.get(key)):return first_difference(expected,after.chunks.get(key),"world/chunks/"+key)
	return {}
func save_restore(count:int)->bool:
	var was:int=failed();var started:int=Time.get_ticks_usec();var live:Dictionary=host.runtime.capture_checkpoint()
	var path:String=output+"/joint-"+str(count)+".native.json"
	var saved:Dictionary=host.export_checkpoint_file(path,"ccc-joint-"+str(count))
	check("actual Native export writes complete joint checkpoint at "+str(count),saved.get("ok",false),saved)
	if not saved.get("ok",false):return false
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(path))
	check("joint complete Native envelope decodes at "+str(count),decoded.get("ok",false),decoded.get("reason"))
	if not decoded.get("ok",false):return false
	var built:Dictionary=host._assemble(decoded.capture)
	check("actual Native cold assembly restores all generated modules at "+str(count),built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return false
	var again:Dictionary=built.runtime.capture_checkpoint()
	var world_diff:Dictionary=restored_world_difference(decoded.capture.world,built,again.world)
	check("decoded entire world restores with exact Native pin activation only at "+str(count),world_diff.is_empty(),world_diff)
	check("decoded facts receipts source content simulation and command revision restore strictly at "+str(count),Data.json_equal(decoded.capture.facts,again.facts) and ["content","source","simulation","receipts","command_revision"].all(func(key:String)->bool:return Data.json_equal(decoded.capture.get(key),again.get(key))),{"facts":first_difference(decoded.capture.facts,again.facts,"facts")})
	check("module stock original residents and work IDs survive cold restore at "+str(count),Data.json_equal(decoded.capture.world.extensions[Modules.KEY],built.services.modules.state()) and index(decoded.capture.facts.stocks).keys()==index(again.facts.stocks).keys() and Data.json_equal(decoded.capture.facts.actors,again.facts.actors))
	var old_runtime:RefCounted=host.runtime
	# Rebind the actual returned authority after validation, never patch a capture.
	host._regions.shutdown();old_runtime.retire();host.world=built.world;host.runtime=built.runtime
	host.runtime.changed.connect(observe_commit)
	host._world_epoch+=1;host._regions.attach(built.runtime,built.services.buildings,host._world_epoch,built.services.modules)
	var replay:Dictionary=built.services.modules.prepare_generation(built.world)
	check("restored B once-only registration returns no duplicate resources at "+str(count),replay.ok and replay.world_changes.is_empty() and replay.initial_stocks.is_empty() and replay.initial_tools.is_empty() and replay.initial_records.is_empty())
	restore_rows.append({"regions":count,"path":path,"sha256":FileAccess.get_sha256(path),"envelope_bytes":FileAccess.get_file_as_bytes(path).size(),"elapsed_usec":Time.get_ticks_usec()-started,"raw_live_to_decoded_facts_exact":Data.json_equal(live.facts,decoded.capture.facts),"raw_live_to_decoded_modules_exact":Data.json_equal(live.world.extensions[Modules.KEY],decoded.capture.world.extensions[Modules.KEY]),"raw_facts_first_difference":first_difference(live.facts,decoded.capture.facts,"facts"),"raw_modules_first_difference":first_difference(live.world.extensions[Modules.KEY],decoded.capture.world.extensions[Modules.KEY],"modules"),"canonical_decoded_facts_exact":Data.json_equal(decoded.capture.facts,again.facts),"canonical_world_with_exact_native_pin_activation":world_diff.is_empty(),"decoded_world_bitwise_same":Data.json_equal(decoded.capture.world,again.world),"native_pins":Residency.required_regions(built.runtime),"scope":"all decoded world fields exact except precisely validated Native pin/batch32 activation; strict canonical facts; raw live serialization observations; no float tolerance"})
	return failed()==was
func write_report(partial:bool)->void:
	var report:Dictionary={"scope":"build18 real normal53 to actual Native single worker/C+B generation registration/Runtime commit and isolated Native storage; no renderer/RSS/OS/VA/fixed performance or 30/60 minute qualification; reverse revisit is data-level, not physical player travel","checks":checks,"failed":failed(),"partial":partial,"target_regions":target,"actual_regions":host.world.regions().size() if is_instance_valid(host) and host.world!=null else 0,"input_path":input_path,"input_sha256":input_sha,"elapsed_msec":Time.get_ticks_msec()-began,"stop_reason":stop_reason,"generation_rows":rows,"tiers":tiers,"storage_cycles":storage_rows,"cold_restores":restore_rows,"observed_events":observed_events,"ledger_contract":"exact original ledger plus only real commit events, bounded to existing last-256 policy"}
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
func finish()->void:
	write_report(false)
	if is_instance_valid(host):host._regions.shutdown();host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed(),"target":target,"stop_reason":stop_reason}));quit(1 if failed()>0 else 0)
