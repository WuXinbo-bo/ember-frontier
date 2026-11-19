extends "res://tests/gameplay/factory_normal_cooperative.gd"
## A real normal-economy continuation. No injected actor, stock, job or need.
var task_id:String
var carrier:String
func cold_restore(runtime:RefCounted,label:String)->Dictionary:
	var encoded:Dictionary=save(runtime,label)
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	var native:=Native.new();var restored:Dictionary=native._assemble(decoded.capture) if decoded.ok else decoded;native.free()
	var same:bool=restored.get("ok",false) and persisted_restore_equal(decoded.capture,restored.runtime.facts(),restored.world)
	check("canonical native payload restores complete facts and all E production cargo states "+label,same,restored.get("reason"))
	return restored if same else {"ok":false}
func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	return runtime.command({"command_id":"r34:e:normal-cargo:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination})
func task(runtime:RefCounted)->Dictionary:
	for row:Dictionary in runtime.world.extension("r34:logistics").tasks:
		if row.id==task_id:return row
	return {}
func story(runtime:RefCounted)->Dictionary:
	for row:Dictionary in runtime._services.workforce.projection().stories:
		if row.id=="ST02":return row
	return {}
func total_timber(runtime:RefCounted)->float:
	var total:float=0
	for row:Dictionary in runtime.facts().stocks:total+=float(row.items.get("timber",0))
	for row:Dictionary in runtime.facts().actors:total+=float(row.pack.get("timber",0))
	return total
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output_dir=args[0];source_path=args[1]
	DirAccess.make_dir_recursive_absolute(output_dir)
	var text:String=FileAccess.get_file_as_string(source_path);source_sha=text.sha256_text()
	var decoded:Dictionary=Store.decode(text)
	check("explicit normal successful prerequisite decodes unedited",decoded.ok)
	if not decoded.ok:return finish()
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture);native.free()
	check("normal cargo continuation mounts actual services",built.ok,built.get("reason"))
	if not built.ok:return finish()
	var runtime:RefCounted=built.runtime
	check("original two people retain real earned consent and return",guards.all(func(id:String)->bool:return runtime.actor(id).relationship.consent and runtime.actor(id).relationship.home_arrived))
	for row:Dictionary in runtime.world.extension("r34:logistics").tasks:
		if row.status not in ["completed","cancelled"]:
			var cancelled:Dictionary=send(runtime,"logistics.cancel",row.id)
			check("normal completed repeating queue can be stopped",cancelled.ok,cancelled)
	var source:String=route_stock(runtime,"warehouse","storage")
	var destination:String=route_stock(runtime,"machine","output")
	var home_source:String="r34:generated:RH-HOME:home:stock:supplies"
	var conservation:float=total_timber(runtime)
	var approached:Dictionary=walk(runtime,runtime.stock(source).location)
	check("player physically reaches finite already produced boards",approached.get("ok",false),approached.get("reason"))
	if not approached.get("ok",false):return finish()
	var source_before:float=float(runtime.stock(source).items.get("timber",0))
	var destination_before:float=float(runtime.stock(destination).items.get("timber",0))
	var ids:Array=runtime.world.extension("r34:logistics").tasks.map(func(t:Dictionary)->String:return t.id)
	var created:Dictionary=send(runtime,"logistics.create","",{"source_id":source,"destination_id":destination,"items":{"timber":1},"repeat":false})
	check("normal task configuration moves no board",created.ok and total_timber(runtime)==conservation and runtime.stock(source).items.timber==source_before,created)
	if not created.ok:return finish()
	for row:Dictionary in runtime.world.extension("r34:logistics").tasks:
		if not ids.has(row.id):task_id=row.id
	for i:int in 700:
		step(runtime)
		if task(runtime).get("phase")=="deliver" and not str(task(runtime).get("actor_id","")).is_empty():carrier=task(runtime).actor_id;break
	check("one real voluntary original person physically picks finite cargo",carrier in guards and runtime.actor(carrier).pack.get("timber")==1 and runtime.stock(source).items.timber==source_before-1 and runtime.stock(destination).items.get("timber",0)==destination_before,{"task":task(runtime),"carrier":carrier})
	if carrier.is_empty():return finish()
	note(runtime,"actual finite pickup before consent withdrawal")
	var withdrawn:Dictionary=send(runtime,"consent",carrier,{"enabled":false})
	check("normal near-field consent command interrupts real carrying",withdrawn.ok and not runtime.actor(carrier).relationship.consent and task(runtime).status=="cargo_held",withdrawn)
	if not withdrawn.ok:return finish()
	step(runtime,25)
	check("withdrawn person retains exact physical cargo and performs no delivery",runtime.actor(carrier).pack.get("timber")==1 and task(runtime).trips==0 and runtime.stock(destination).items.get("timber",0)==destination_before and total_timber(runtime)==conservation)
	check("withdrawal releases capacity without erasing task origin",runtime.world.extension("r34:logistics").reservations.is_empty() and task(runtime).source_id==source and task(runtime).actor_id==carrier)
	var dialogue:Dictionary=story(runtime)
	check("actual withdrawal dialogue preserves that person's prior real delivery",not dialogue.people[carrier].consent and dialogue.people[carrier].real_delivery and dialogue.text.contains("撤回合作") and dialogue.text.contains("确实送到过"),dialogue)
	var logistics:Dictionary=runtime.world.extension("r34:logistics")
	var restored:Dictionary=cold_restore(runtime,"normal-withdrawn-real-cargo")
	if not restored.ok:return finish()
	runtime=restored.runtime
	check("cold restore retains withdrawn task cargo identity and all reservations",Data.json_equal(logistics,runtime.world.extension("r34:logistics")) and not runtime.actor(carrier).relationship.consent and runtime.actor(carrier).pack.get("timber")==1)
	step(runtime,25)
	check("restored withdrawal cannot silently restart delivery",task(runtime).trips==0 and runtime.actor(carrier).pack.get("timber")==1 and total_timber(runtime)==conservation)
	# Restoring consent uses the social command's own contact policy. Pack
	# handoff permission intentionally remains false while consent is revoked.
	var agreed:Dictionary=send(runtime,"consent",carrier,{"enabled":true})
	check("only a fresh real consent command enables the original carrier",agreed.ok,agreed)
	if not agreed.ok:return finish()
	for i:int in 700:
		step(runtime)
		if task(runtime).status=="completed":break
	check("renewed consent resumes the same original task through real B delivery",task(runtime).status=="completed" and task(runtime).id==task_id and task(runtime).trips==1 and runtime.stock(destination).items.get("timber",0)==destination_before+1 and float(runtime.actor(carrier).pack.get("timber",0))==0 and total_timber(runtime)==conservation,task(runtime))
	if task(runtime).status!="completed":return finish()
	note(runtime,"original cargo physically delivered after renewed consent")
	# A second original board tests cancellation plus a real alternate receiver.
	ids=runtime.world.extension("r34:logistics").tasks.map(func(t:Dictionary)->String:return t.id)
	created=send(runtime,"logistics.create","",{"source_id":source,"destination_id":destination,"items":{"timber":1},"repeat":false})
	if not created.ok:check("second finite cargo task queues",false,created);return finish()
	for row:Dictionary in runtime.world.extension("r34:logistics").tasks:
		if not ids.has(row.id):task_id=row.id
	carrier=""
	for i:int in 700:
		step(runtime)
		if task(runtime).phase=="deliver":carrier=task(runtime).actor_id;break
	check("second real board reaches a physical pack",not carrier.is_empty() and runtime.actor(carrier).pack.get("timber")==1 and total_timber(runtime)==conservation)
	if carrier.is_empty():return finish()
	var cancelled:Dictionary=send(runtime,"logistics.cancel",task_id)
	check("normal cancellation atomically stops haul and holds real cargo",cancelled.ok and task(runtime).status=="cargo_held" and runtime.actor(carrier).get("intent")==null and runtime.actor(carrier).pack.get("timber")==1,cancelled)
	step(runtime,25)
	check("cancelled cargo cannot be resumed by N5 or another worker",task(runtime).trips==0 and runtime.actor(carrier).pack.get("timber")==1 and runtime.stock(destination).items.get("timber",0)==destination_before+1 and total_timber(runtime)==conservation)
	var home_before:float=float(runtime.stock(home_source).items.get("timber",0))
	var redirected:Dictionary=send(runtime,"logistics.retarget",task_id,{"destination_id":home_source})
	check("normal retarget configures actual existing home receiver without moving cargo",redirected.ok and task(runtime).source_id==source and task(runtime).destination_id==home_source and runtime.actor(carrier).pack.get("timber")==1 and runtime.stock(home_source).items.get("timber",0)==home_before and total_timber(runtime)==conservation,redirected)
	if not redirected.ok:return finish()
	for i:int in 700:
		step(runtime)
		if task(runtime).status=="completed":break
	check("same cancelled task can physically deliver only after explicit retarget",task(runtime).status=="completed" and task(runtime).trips==1 and runtime.stock(home_source).items.get("timber",0)==home_before+1 and total_timber(runtime)==conservation,task(runtime))
	note(runtime,"original cancelled cargo physically reaches alternate home receiver")
	restored=cold_restore(runtime,"normal-cargo-boundaries-complete")
	check("normal boundary result cold restores without duplicate board or trip",restored.ok and total_timber(restored.runtime)==conservation)
	finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"stages":stage_rows,"costs":costs,"prerequisite":{"path":source_path,"sha256":source_sha},"scope":"Explicit actual A normal-economy successful save continuation; real consent/cargo/cancellation/retarget/story boundaries, no fixture facts or production simulation changes; not whole-opening rerun or PCK/OS/VA/performance qualification."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
