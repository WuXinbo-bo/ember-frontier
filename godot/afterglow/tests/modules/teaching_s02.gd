extends "res://tests/modules/factory_boundary_fixture.gd"
const Teaching=preload("res://scripts/production/production_teaching.gd")
func study(rt:RefCounted,payload:Dictionary={},target:String="repair-resident",identity:String="")->Dictionary:
	return command(rt,"study",target,{"learning_source":"teacher","knowledge_id":"basic_tool_repair"}.merged(payload,true),"player",identity)
func run()->void:
	var base:=opening();if base.is_empty():finish();return
	var teacher:=Draft.find(base.facts.actors,"repair-resident");teacher.relationship.met=true;teacher.relationship.helped=true;teacher.intent=null
	base.world.extensions["r3:production"].knowledge["player"]=[]
	var initial:=mount(base,"explicit met/helped, independent nonmember teacher fixture")
	if not initial.ok:finish();return
	var points:Array=initial.services.actions.work_points({"kind":"study","actor_id":"player","target_id":"repair-resident","payload":{"learning_source":"teacher","knowledge_id":"basic_tool_repair"}})
	check("original planner gives supported contact points around real teacher",not points.is_empty())
	if points.is_empty():finish();return
	put_actor(base,points[0]);var built:=mount(base,"real supported teacher/student placement")
	if not built.ok:finish();return
	var rt:RefCounted=built.runtime;var prod:RefCounted=built.services.production;var before:Dictionary=rt.capture_checkpoint()
	var dto:Dictionary=prod.teaching_projection();check("provider offers same actual12-second command",dto.available and dto.offers.size()==1 and dto.offers[0].can_start and dto.offers[0].seconds==12 and not dto.offers[0].known)
	dto.offers[0].command.payload.knowledge_id="forged"
	check("provider deep data and preflight never mutate authority",Data.json_equal(before,rt.capture_checkpoint()) and prod.teaching_projection().offers[0].command.payload.knowledge_id==Teaching.KNOWLEDGE)
	check("NPC and unknown teacher cannot receive offers",not prod.teaching_projection("repair-resident").available and not prod.teaching_projection("player","unknown").available)
	for payload:Dictionary in [{"learning_source":"other"},{"knowledge_id":"anything"},{"record_id":"forged"},{"source_id":"pack:player"},{"output_id":"pack:player"},{"tool_ids":[]},{"grants":["basic_tool_repair"]},{"seconds":.1}]:
		var result:=study(rt,payload)
		check("conflicting/forged learning payload rejected "+str(payload),not result.ok and Data.json_equal(before,rt.capture_checkpoint()),result)
	check("alternate teacher rejected",not study(rt,{},"village-resident").ok and Data.json_equal(before,rt.capture_checkpoint()))
	for variant:String in ["unmet","unhelped","dead_teacher","far"]:
		var altered:Dictionary=base.duplicate(true);var t:=Draft.find(altered.facts.actors,"repair-resident")
		match variant:
			"unmet":t.relationship.met=false
			"unhelped":t.relationship.helped=false
			"dead_teacher":t.hp=0
			"far":Draft.find(altered.facts.actors,"player").x+=4
		var negative:=mount(altered,variant+" teaching fixture")
		if negative.ok:
			var untouched:Dictionary=negative.runtime.capture_checkpoint();var result:=study(negative.runtime)
			check(variant+" cannot teach or grant",not result.ok and Data.json_equal(untouched,negative.runtime.capture_checkpoint()))
			if variant=="unmet":check("unknown teacher hides actual offer",negative.services.production.teaching_projection().offers.is_empty())
	var goods:Dictionary=rt.facts();var legacy:Dictionary=prod.state()
	check("real teacher study begins without membership or book",study(rt,{},"repair-resident","B:S02:cancel").ok and not rt.actor("repair-resident").relationship.get("member",false))
	tick(rt,20);var order:=Draft.find(prod.state().orders,"B:S02:cancel:order")
	check("study uses original order explicit teacher/null references",order.learning_source=="teacher" and order.duration==12 and order.sourceId==null and order.outputId==null and order.stationId==null and order.repairToolId==null and order.toolIds.is_empty())
	var hold:Array=prod.hold_descriptors(rt.facts()).filter(func(h:Dictionary)->bool:return h.intent_id==order.id)
	check("one teacher-use hold with no books materials tools",hold.size()==1 and hold[0].use_target_id=="repair-resident" and hold[0].source_id=="" and hold[0].cost.is_empty() and hold[0].tool_ids.is_empty())
	check("original held pauses teacher study",command(rt,"held","",{"held":false}).ok)
	var elapsed:float=Draft.find(prod.state().orders,order.id).elapsed;tick(rt,20)
	check("pause earns no hidden learning",Draft.find(prod.state().orders,order.id).elapsed==elapsed and prod.state().knowledge.player.is_empty())
	var cold:=mount(rt.capture_checkpoint(),"active paused teacher cold")
	check("cold keeps original teacher order/holds without book",cold.ok and Data.json_equal(prod.state(),cold.services.production.state()))
	if cold.ok:rt=cold.runtime;prod=cold.services.production
	check("cancel existing study releases teacher with no knowledge",command(rt,"cancel").ok and not prod.state().knowledge.player.has(Teaching.KNOWLEDGE) and not prod.use_reserved("repair-resident"))
	var restarted:=study(rt,{},"repair-resident","B:S02:learn")
	check("fresh original teacher study can restart",restarted.ok,restarted)
	if not restarted.ok:finish();return
	var at:float=rt.clock()
	for i:int in 150:
		rt.tick(.1)
		if Draft.find(prod.state().orders,"B:S02:learn:order").status=="completed":break
	order=Draft.find(prod.state().orders,"B:S02:learn:order")
	check("exact12 effective seconds grants one original knowledge",order.status=="completed" and is_equal_approx(order.elapsed,12) and prod.state().knowledge.player==[Teaching.KNOWLEDGE],order)
	check("teacher source event preserves real identity",prod.state().facts.any(func(f:Dictionary)->bool:return f.orderId==order.id and f.kind=="learned" and f.get("source_kind")=="teacher" and f.get("teacher_id")==Teaching.TEACHER))
	check("no book/tool/material invented or consumed",Data.json_equal(legacy.tools,prod.state().tools) and Data.json_equal(legacy.records,prod.state().records) and Data.json_equal(goods.actors.map(func(a:Dictionary)->Dictionary:return a.pack),rt.facts().actors.map(func(a:Dictionary)->Dictionary:return a.pack)))
	before=rt.capture_checkpoint();var known:=study(rt)
	check("known rejects without additional work or reward",not known.ok and known.code=="KNOWN" and Data.json_equal(before,rt.capture_checkpoint()))
	check("read model reports actual known state",prod.teaching_projection().offers[0].known and not prod.teaching_projection().offers[0].can_start)
	var final:=mount(before,"completed teaching cold")
	check("completed teacher source survives canonical cold",final.ok and Data.json_equal(prod.state(),final.services.production.state()))
	for change:Dictionary in [{"learning_source":"unknown"},{"duration":1},{"sourceId":"pack:player"},{"teacher_id":"village-resident"},{"knowledge_id":"anything"}]:
		var bad:Dictionary=before.duplicate(true);Draft.find(bad.world.extensions["r3:production"].orders,order.id).merge(change,true)
		var host:=Native.new();hosts.append(host);check("forged saved teacher source rejected "+str(change),not host._assemble(bad).ok)
	var interrupted:=mount(base,"independent real teacher interruption")
	if interrupted.ok:
		var ir:RefCounted=interrupted.runtime;var ip:RefCounted=interrupted.services.production
		check("interruptible teaching actually starts",study(ir,{},"repair-resident","B:S02:interrupted").ok)
		tick(ir,10);var passed:float=Draft.find(ip.state().orders,"B:S02:interrupted:order").elapsed
		var tx:=Draft.new(ip.context);tx.actor("repair-resident").hp=0
		check("teacher incapacity enters same original Runtime transaction",ir._commit(tx.result()).ok)
		tick(ir,30)
		var stopped:=Draft.find(ip.state().orders,"B:S02:interrupted:order")
		check("actual mid-study incapacity earns no remaining seconds or knowledge",stopped.elapsed==passed and stopped.status=="blocked" and ip.state().knowledge.player.is_empty(),stopped)
		check("blocked teacher can be cancelled without phantom book",command(ir,"cancel").ok and not ip.use_reserved(Teaching.TEACHER))
	# The original book is not a teacher fixture: retain its real holder,
	# item count, record identity, duration and validator branch.
	var book_base:Dictionary=base.duplicate(true);var record:Dictionary=book_base.world.extensions["r3:production"].records[0]
	var holder:Dictionary=Draft.find(book_base.facts.stocks,record.holderId);put_actor(book_base,holder.location)
	var original_book:=mount(book_base,"original finite book and holder regression")
	if original_book.ok:
		var br:RefCounted=original_book.runtime;var bp:RefCounted=original_book.services.production
		var searched:=command(br,"search",record.holderId)
		check("original book holder must still be actually searched",searched.ok,searched)
		if not searched.ok:finish();return
		tick(br,50)
		var book_started:=command(br,"study",record.id,{},"player","B:S02:book")
		check("original book study command still starts",book_started.ok,book_started)
		if not book_started.ok:finish();return
		for i:int in 150:
			br.tick(.1)
			if Draft.find(bp.state().orders,"B:S02:book:order").get("status")=="completed":break
		var old_order:=Draft.find(bp.state().orders,"B:S02:book:order")
		check("book order retains old shape and actual holder/item",old_order.status=="completed" and not old_order.has("learning_source") and old_order.sourceId==record.holderId and br.stock(record.holderId).items.get(record.itemId)==holder.items[record.itemId] and record.grants.all(func(k:String)->bool:return bp.state().knowledge.player.has(k)))
	evidence.append({"scope":"Explicit met/helped/nonmember and supported placement fixture; original real Runtime commands/ticks/holds and knowledge settlement. Not normal social journey or OS.","learning_wall_simulation":rt.clock()-at,"knowledge":prod.state().knowledge.player})
	finish()
