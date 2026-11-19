extends "res://tests/gameplay/generated_cooperation.gd"
## Continue a recorded no-grant original-NPC route. Incapacity is a separately
## labelled lifecycle fixture; all work/cancel/consent uses existing A/B APIs.

func active_order(id:String)->Dictionary:
	for order:Dictionary in runtime.world.extension("r3:production").orders:
		if order.actorId==id and order.status in ["active","blocked"]:return order
	return {}

func order_by_id(id:String)->Dictionary:
	for order:Dictionary in runtime.world.extension("r3:production").orders:
		if order.id==id:return order
	return {}

func at_work(id:String)->bool:
	var a:Dictionary=runtime.actor(id)
	return a.get("intent") is Dictionary and a.intent.get("kind")=="craft" and not active_order(id).is_empty() and float(active_order(id).elapsed)>0.2

func assign(target:String)->bool:
	return perform("assign actual existing handle work","job","repair-resident",{"job":"craft","work_target_id":target}) and wait_fact("original NPC enters actual paid craft order",func()->bool:return at_work("repair-resident"),350)

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	output_dir=args[0];DirAccess.make_dir_recursive_absolute(output_dir)
	command_prefix="E-recovery:"
	evidence_kind="recorded-route-recovery-with-explicit-incapacity-fixture"
	host=Client.new()
	if args.size()!=2:check("recorded real route capture explicitly supplied",false);finish();return
	var capture:Variant=JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	check("recorded route checkpoint is a real capture",capture is Dictionary and capture.has_all(["world","facts"]))
	if not capture is Dictionary or not mount(capture):finish();return
	check("original cooperative actors remain actual joined home arrivals",runtime.actor("repair-resident").relationship.get("home_arrived",false) and runtime.actor("village-resident").relationship.get("home_arrived",false))
	recovery_route()
	finish()

func recovery_route()->void:
	var id:="repair-resident"
	var choices:Array=runtime.work_targets().filter(func(t:Dictionary)->bool:return t.work_payload.get("recipe_id")=="make_handle" and runtime.world.entity(t.actual_target_id).regionId=="RH-HOME")
	check("recorded real constructed station exposes handle work",choices.size()==1,choices)
	if choices.size()!=1:return
	var target:String=choices[0].id
	if not approach(id):return
	var saw:=""
	for tool:Dictionary in runtime.world.extension("r3:production").tools:
		if tool.kind=="hand_saw" and tool.holderId=="pack:"+id:saw=tool.id
	check("recorded owned saw and remaining finite timber present",not saw.is_empty() and float(runtime.actor(id).pack.get("timber",0))>=1)
	if saw.is_empty():return
	if not assign(target):return
	var order:String=active_order(id).id
	var before_pack:Dictionary=runtime.actor(id).pack.duplicate(true)
	var before_pause:Dictionary=runtime.capture_checkpoint()
	runtime.set_paused(true);runtime.tick(5)
	check("pause freezes actual active original-NPC order and one clock",Data.json_equal(before_pause,runtime.capture_checkpoint()))
	runtime.set_paused(false)
	if not roundtrip("actual active original-NPC craft"):return
	check("restored original order retains real tool/material holds",active_order(id).id==order and runtime._services.production.tool_reserved(saw) and runtime._services.production.reserved("pack:"+id,"timber")==1)
	if not perform("voluntary rest interrupts actual B work","job",id,{"job":"rest"}):return
	step()
	var elapsed:float=float(order_by_id(order).elapsed)
	check("rest saves same work intent rather than a replacement order",runtime.actor(id).has("suspended_work") and runtime.actor(id).suspended_work.intent.order_id==order)
	for i:int in 10:step()
	check("rest does not finish work consume inputs or release held tool",float(order_by_id(order).elapsed)==elapsed and runtime.actor(id).pack==before_pack and runtime._services.production.tool_reserved(saw))
	if not perform("resume same voluntarily selected work","job",id,{"job":"craft","work_target_id":target}):return
	if not wait_fact("existing B executor resumes same order",func()->bool:return at_work(id) and active_order(id).id==order,180):return
	seq+=1
	var cancelled:Dictionary=runtime.command({"command_id":"E-recovery-cancel:"+str(seq),"actor_id":id,"kind":"cancel","expected_revision":runtime.get_revision()})
	check("canonical actor cancel releases order without consumption",cancelled.ok and order_by_id(order).status=="cancelled" and runtime.actor(id).pack==before_pack and not runtime._services.production.tool_reserved(saw) and runtime._services.production.reserved("pack:"+id,"timber")==0,cancelled)
	if not perform("rest assignment prevents automatic restart after cancellation","job",id,{"job":"rest"}):return
	if not assign(target):return
	order=active_order(id).id
	if not approach(id):return
	if not perform("actual nearby revocation of consent","consent",id,{"enabled":false}):return
	step()
	check("revocation cancels real original-NPC work and releases holds",order_by_id(order).status=="cancelled" and not runtime._services.production.tool_reserved(saw) and runtime._services.production.reserved("pack:"+id,"timber")==0)
	var revoked_pack:Dictionary=runtime.actor(id).pack.duplicate(true)
	for i:int in 20:step()
	check("revoked person resumes own activity without producing or consuming team stock",not runtime.actor(id).relationship.consent and runtime.actor(id).pack==revoked_pack and active_order(id).is_empty())
	if not approach(id):return
	if not perform("explicit nearby renewed voluntary consent","consent",id,{"enabled":true}):return
	if not perform("rest before new post-consent order","job",id,{"job":"rest"}):return
	if not assign(target):return
	order=active_order(id).id
	var fixture:Dictionary=runtime.capture_checkpoint()
	for a:Dictionary in fixture.facts.actors:
		if a.id==id:a.hp=0.0
	write_json("explicit-incapacity-fixture.json",fixture)
	if not mount(fixture):return
	var still_pack:Dictionary=runtime.actor(id).pack.duplicate(true)
	var old_at:Vector3=Geometry.point(runtime.actor(id))
	step()
	check("explicit incapacity cancels actual work without a free product or step",runtime.actor(id).intent==null and order_by_id(order).status=="cancelled" and runtime.actor(id).pack==still_pack and Geometry.point(runtime.actor(id))==old_at and not runtime._services.production.tool_reserved(saw) and runtime._services.production.reserved("pack:"+id,"timber")==0)
	roundtrip("cancelled incapacitated original-NPC work")
