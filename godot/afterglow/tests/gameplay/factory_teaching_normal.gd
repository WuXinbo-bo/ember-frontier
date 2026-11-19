extends "res://tests/gameplay/factory_knowledge_pressure.gd"
## S02 original normal1 social route; no met/helped/body/capture fixture.
var commands:Array=[]
var command_namespace:String="r34:e:s02-normal"
var live:RefCounted
var snapshots:Array=[]
var violations:Array=[]
func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	var request:Dictionary={"command_id":command_namespace+":%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination}
	var result:Dictionary=runtime.command(request);commands.append({"time":runtime.clock(),"request":request,"result":result});return result
func observe(runtime:RefCounted)->void:
	for actor:Dictionary in runtime.facts().actors:
		if actor.hp!=100:violations.append({"id":actor.id,"time":runtime.clock(),"reason":"original_hp_changed"})
func person(runtime:RefCounted)->Dictionary:
	return runtime.world.extension(Gameplay.KEY).stories.ST02.people.get("repair-resident",{})
func lesson(runtime:RefCounted)->Dictionary:
	for attempt:int in 28:
		var offers:Array=runtime._services.production.teaching_projection().offers
		if not offers.is_empty() and offers[0].can_start:
			return send(runtime,"study","repair-resident",{"learning_source":"teacher","knowledge_id":"basic_tool_repair"})
		if not social_contact(runtime,"repair-resident"):return {"ok":false,"reason":"real social approach unavailable"}
		for i:int in 12:
			step(runtime)
			offers=runtime._services.production.teaching_projection().offers
			if not offers.is_empty() and offers[0].can_start:return send(runtime,"study","repair-resident",{"learning_source":"teacher","knowledge_id":"basic_tool_repair"})
	return {"ok":false,"reason":"real idle teacher contact did not become available"}
func remember(label:String)->void:
	snapshots.append({"label":label,"time":live.clock(),"actors":live.facts().actors,"story":live.world.extension(Gameplay.KEY).stories.ST02,"production":live.world.extension("r3:production")})
func run()->void:
	output_dir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output_dir)
	var options:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[2]))
	if options.get("probe_mode")=="urgent":
		command_namespace="r34:e:s02-urgent"
		return urgent_need()
	if options.get("probe_mode")=="observe_completion":
		command_namespace="r34:e:s02-observe-completion"
		return observe_completion()
	if str(options.get("probe_mode","")).begins_with("passive"):
		return passive_actual()
	var built:Dictionary=normal_tools()
	if not built.get("ok",false):return finish()
	var r:RefCounted=built.runtime;live=r
	check("real fresh opening is not already met/helped/taught or knowledgeable",not r.actor("repair-resident").relationship.met and not r.actor("repair-resident").relationship.helped and not person(r).get("taught",false) and not r.world.extension("r3:production").knowledge.get("player",[]).has("basic_tool_repair"))
	if not transfer(r,"take",TOOLSTOCK,{},[HAMMER]):return finish()
	check("carrying original finite hammer is not learning",not r.world.extension("r3:production").knowledge.get("player",[]).has("basic_tool_repair"))
	if not social_contact(r,"repair-resident"):check("normal actual teacher contact",false);return finish()
	check("normal talk records actual meeting only",send(r,"talk","repair-resident").get("ok",false) and r.actor("repair-resident").relationship.met and not r.actor("repair-resident").relationship.helped)
	var before_help:Dictionary=r.actor("player").pack.duplicate(true)
	check("actual finite help pays original food and water without recruitment",send(r,"help","repair-resident",{"items":{"food":1,"water":1}}).get("ok",false) and r.actor("player").pack.food==before_help.food-1 and r.actor("player").pack.water==before_help.water-1 and not r.actor("repair-resident").relationship.member)
	remember("normal real tools meeting and finite help")
	var started:Dictionary=lesson(r)
	check("real nonmember teacher accepts original study",started.get("ok",false),started)
	if not started.get("ok",false):return finish()
	step(r,50)
	check("teacher use hold prevents ordinary autonomous walk before completion",r.actor("repair-resident").get("intent")==null and not person(r).get("taught",false) and not r.world.extension("r3:production").knowledge.get("player",[]).has("basic_tool_repair"))
	var cold:Dictionary=cold_restore(r,"normal-teacher-active-five-seconds")
	if not cold.get("ok",false):return finish()
	r=cold.runtime;live=r
	check("normal cancellation gives neither knowledge nor story teaching",send(r,"cancel").get("ok",false) and not r._services.production.use_reserved("repair-resident") and not person(r).get("taught",false) and not r.world.extension("r3:production").knowledge.get("player",[]).has("basic_tool_repair"))
	var tools:Dictionary={};for tool:Dictionary in r.world.extension("r3:production").tools:tools[tool.id]=tool.duplicate(true)
	var records:Array=r.world.extension("r3:production").records.duplicate(true)
	var packs:Array=r.facts().actors.map(func(a:Dictionary)->Dictionary:return a.pack)
	started=lesson(r)
	check("real teacher restarts after cancellation without a book",started.get("ok",false),started)
	if not started.get("ok",false):return finish()
	var order_id:String=str(r.actor("player").intent.get("orderId",r.actor("player").intent.get("order_id","")))
	var at:float=r.clock();var completed:Dictionary=progress(r,200)
	step(r)
	var production:Dictionary=r.world.extension("r3:production");var done:Array=production.orders.filter(func(o:Dictionary)->bool:return o.get("learning_source")=="teacher" and o.status=="completed")
	check("normal teacher completes exactly12 effective seconds through unique production",completed.finished and done.size()==1 and is_equal_approx(done[0].elapsed,12) and production.knowledge.player==["basic_tool_repair"],{"order_id":order_id,"elapsed_wall_sim":r.clock()-at,"orders":done})
	check("E taught consumes actual completed original learned fact only",person(r).get("taught",false) and production.facts.filter(func(e:Dictionary)->bool:return e.kind=="learned" and e.get("source_kind")=="teacher").size()==1)
	var projected:Dictionary=story(r)
	check("same S02 read model explains actual teaching without recruiting",projected.people.get("repair-resident",{}).get("taught",false) and str(projected.text).contains("已经在现场教过你") and not r.actor("repair-resident").relationship.member and not r.actor("repair-resident").relationship.consent)
	check("teaching creates no book tool repair or material reward",Data.json_equal(records,production.records) and production.tools.all(func(t:Dictionary)->bool:return Data.json_equal(t,tools[t.id])) and Data.json_equal(packs,r.facts().actors.map(func(a:Dictionary)->Dictionary:return a.pack)))
	remember("real teacher completed original knowledge and story consequence")
	cold=cold_restore(r,"normal-teacher-completed")
	check("full canonical cold preserves unique teacher knowledge and story",cold.get("ok",false) and person(cold.runtime).get("taught",false))
	check("normal original people keep100HP",violations.is_empty(),violations)
	finish()
func urgent_need()->void:
	var path:String=OS.get_cmdline_user_args()[1];var raw:String=FileAccess.get_file_as_string(path)
	sources.append({"path":path,"sha256":raw.sha256_text()})
	var decoded:Dictionary=Store.decode(raw);var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded;host.free()
	check("actual normal active5 Native mounts without edits",built.get("ok",false))
	if not built.get("ok",false):return finish()
	var r:RefCounted=built.runtime;live=r
	var order_id:String=r.actor("player").intent.order_id
	check("original legal held false pauses existing teacher order",send(r,"held","",{"held":false}).get("ok",false))
	var order:Dictionary=_find_order(r,order_id);var elapsed:float=order.elapsed;var initial_thirst:float=r.actor("repair-resident").thirst
	for i:int in 7000:
		if r.actor("repair-resident").thirst<=35.14:break
		step(r)
	check("only unique Runtime advances actual thirst while original held order gains nothing",r.actor("repair-resident").thirst<initial_thirst and r.actor("repair-resident").thirst>35 and _find_order(r,order_id).elapsed==elapsed and not person(r).get("taught",false),{"thirst":r.actor("repair-resident").thirst,"elapsed":_find_order(r,order_id).elapsed,"time":r.clock()})
	check("original held true resumes same active order",send(r,"held","",{"held":true}).get("ok",false))
	var need_observed:bool=false;var need_cold:bool=false;var blocked_samples:int=0;var false_progress:int=0
	for i:int in 240:
		var old_elapsed:float=_find_order(r,order_id).elapsed
		step(r)
		var teacher:Dictionary=r.actor("repair-resident");var current:Dictionary=_find_order(r,order_id)
		if teacher.get("intent") is Dictionary and teacher.intent.get("kind")=="drink":
			need_observed=true;blocked_samples+=1
			if current.elapsed!=old_elapsed:false_progress+=1
			if not need_cold:
				var restored:Dictionary=cold_restore(r,"normal-teacher-real-N2-drinking")
				need_cold=restored.get("ok",false)
				if need_cold:r=restored.runtime;live=r
		if current.status=="completed":break
	step(r) # Workforce consumes the prior committed actions learned event.
	var drank:bool=r.facts().ledger.any(func(e:Dictionary)->bool:return e.kind=="life-completed" and e.get("actor_id")=="repair-resident" and e.get("operation")=="drink")
	check("real N2 drinking preempts ordinary teaching hold with no hidden learning",need_observed and blocked_samples>0 and false_progress==0 and need_cold,{"samples":blocked_samples,"false_progress":false_progress})
	check("teacher actually pays helped finite water through original care rule",drank and r.actor("repair-resident").pack.get("water",0)==0 and r.actor("repair-resident").thirst>35 and not r.actor("repair-resident").relationship.member)
	check("same12 effective lesson resumes only after real need resolves",_find_order(r,order_id).status=="completed" and is_equal_approx(_find_order(r,order_id).elapsed,12) and person(r).get("taught",false) and r.world.extension("r3:production").knowledge.player==["basic_tool_repair"])
	remember("normal real N2 interrupted then original12 effective lesson finished")
	var restored:Dictionary=cold_restore(r,"normal-teacher-N2-completed")
	check("natural need branch preserves full final canonical authority",restored.get("ok",false) and violations.is_empty())
	finish()
func observe_completion()->void:
	var path:String=OS.get_cmdline_user_args()[1];var raw:String=FileAccess.get_file_as_string(path)
	sources.append({"path":path,"sha256":raw.sha256_text()})
	var decoded:Dictionary=Store.decode(raw);var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded;host.free()
	check("untouched actual natural N2 final boundary mounts",built.get("ok",false))
	if not built.get("ok",false):return finish()
	var r:RefCounted=built.runtime;live=r;var production:Dictionary=r.world.extension("r3:production")
	check("prior actual action commit already has unique12 second teacher knowledge before next workforce",production.orders.any(func(o:Dictionary)->bool:return o.get("learning_source")=="teacher" and o.status=="completed" and is_equal_approx(o.elapsed,12)) and production.knowledge.player==["basic_tool_repair"] and not person(r).get("taught",false))
	var packs:Array=r.facts().actors.map(func(a:Dictionary)->Dictionary:return a.pack);var stocks:Array=r.facts().stocks.duplicate(true)
	step(r)
	check("next original workforce phase consumes prior real learned fact",person(r).get("taught",false) and story(r).people["repair-resident"].taught)
	check("consumer adds no second knowledge or material reward",Data.json_equal(production,r.world.extension("r3:production")) and Data.json_equal(stocks,r.facts().stocks) and Data.json_equal(packs,r.facts().actors.map(func(a:Dictionary)->Dictionary:return a.pack)))
	var cold:Dictionary=cold_restore(r,"natural-N2-next-workforce-taught")
	check("actual natural N2 route and story fully cold restore",cold.get("ok",false) and person(cold.runtime).get("taught",false) and violations.is_empty())
	remember("one next original workforce phase after actual N2 lesson completion")
	finish()
func passive_actual()->void:
	var path:String=OS.get_cmdline_user_args()[1];var raw:String=FileAccess.get_file_as_string(path)
	sources.append({"path":path,"sha256":raw.sha256_text()})
	var decoded:Dictionary=Store.decode(raw);var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded;host.free()
	check("same untouched own22 normal53 capture mounts",built.get("ok",false))
	if not built.get("ok",false):return finish()
	var r:RefCounted=built.runtime;live=r
	check("actual completed normal route has no active teacher reservation",not r._services.production.use_reserved("repair-resident"))
	step(r,60)
	FileAccess.open(output_dir+"/complete-capture.json",FileAccess.WRITE).store_string(JSON.stringify(r.capture_checkpoint(),"\t",true,true))
	check("bounded original normal continuation preserves living three people",r.facts().actors.size()==3 and r.facts().actors.all(func(a:Dictionary)->bool:return a.hp>0))
	finish()
func _find_order(runtime:RefCounted,id:String)->Dictionary:
	for order:Dictionary in runtime.world.extension("r3:production").orders:
		if order.id==id:return order
	return {}
func finish()->void:
	if live!=null:save(live,"teaching-normal-final")
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"commands":commands,"snapshots":snapshots,"sources":sources,"violations":violations,"fixed_steps":ticks,"scope":"Real fresh original normal1 seed713 plus frozen B teacher overlay and E consumer; no fixture relationships/capture/body/position/material/knowledge edits. Bounded functional fixed0.1 steps, not long/OS/VA/new package."},"\t",true,true));print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
