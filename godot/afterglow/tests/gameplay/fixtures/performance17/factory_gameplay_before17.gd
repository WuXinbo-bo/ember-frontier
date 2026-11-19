extends RefCounted
## Pure opening/event DTOs. A commits, B registers stock and executes work/combat.
const Initial=preload("res://scripts/runtime/initial_state.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Regional=preload("res://scripts/runtime/factory_gameplay_region.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Story=preload("res://scripts/runtime/factory_gameplay_story.gd")
const Village=preload("res://scripts/runtime/village_progression.gd")
const KEY="r34:gameplay"
const SCENARIO="factory-settlement-r34"
const MAX_EVENTS=4096

static func initial_state(layout:Dictionary={})->Dictionary:
	return {"version":1,"layout":layout.duplicate(true),"last_event_revision":-1,"event_ids":[],"regional_events":[],"flags":{},"defense":{"status":"dormant","warning_id":"","warning_at":0.0,"arrival_at":0.0,"cause_event_id":"","actors":[]}}

static func initial(layout:Dictionary,module_registration:Dictionary)->Dictionary:
	if layout.is_empty() or not module_registration.get("ok",false):return _bad("INITIAL_INPUT_UNAVAILABLE","需要C布局与A/B一次性模块登记DTO")
	# A may pass the flat B registration or a combined {seed_result, ...} DTO.
	# Nested seed_result is authoritative. Flat arrays are compatibility aliases
	# only: unequal aliases reject rather than appending a second grant.
	var seed:Dictionary=module_registration.get("seed_result",module_registration).duplicate(true)
	var spawns:Variant=seed.get("spawn_points",layout.get("spawn_points"))
	if not spawns is Dictionary or not spawns.has_all(["player","village-resident","repair-resident"]):return _bad("INITIAL_SPAWNS_MISSING","需要三名原人物的真实生成锚点")
	for id:String in ["player","village-resident","repair-resident"]:
		if not _location(spawns[id]):return _bad("INITIAL_SPAWN_INVALID","人物生成锚点无效："+id)
	var home:Variant=layout.get("home",seed.get("home",spawns.player))
	if not _location(home):return _bad("INITIAL_HOME_INVALID","需要真实据点锚点")
	seed.spawn_points=spawns.duplicate(true);seed.home=home.duplicate(true)
	for field:String in ["initial_stocks","initial_tools","initial_records"]:
		var values:Variant=seed.get(field,[])
		if not values is Array:return _bad("INITIAL_CONTENT_INVALID","起步登记表无效："+field)
		values=values.duplicate(true)
		if module_registration.has("seed_result"):
			if not module_registration.get(field,[]) is Array:return _bad("INITIAL_CONTENT_INVALID","起步登记表无效："+field)
			if module_registration.has(field) and not Data.json_equal(values,module_registration[field]):return _bad("INITIAL_ALIAS_CONFLICT","起步登记兼容别名与唯一seed_result不一致："+field)
		var ids:Dictionary={}
		for row:Variant in values:
			if not row is Dictionary or not Data.valid_id(row.get("id")) or ids.has(row.id):return _bad("INITIAL_DUPLICATE_CONTENT","起步登记ID缺失或重复："+field)
			ids[row.id]=true
		seed[field]=values
	var actors:Array=[Initial.actor("player","归乡者",spawns.player,home,{"food":1,"water":1}),Initial.actor("village-resident","周婶",spawns["village-resident"],home,{}),Initial.actor("repair-resident","老许",spawns["repair-resident"],home,{})]
	var quests:Array=[]
	for item:Array in [["R34-Q01","让工具重新工作","找到旧工具与木工手册，采运原木，复用现成手工点分批锯切。体力不足先停工休息和补给，不必另造手工点。"],["R34-Q02","把物资安置下来","用实际材料与施工建成完整仓储模块，检查有限容量和装卸通路。"],["R34-Q03","让生产继续","恢复燃料木作坊并提供实际原料与能源；分段加工、休息后继续，可邀请自愿成员承担取送。"],["R34-Q04","守住运输路线","勘察后知情开始清障。可暂停劳动回去补给、恢复体力并准备防线；预告仍按同一模拟推进。处理威胁后恢复供给。"]]:
		quests.append({"id":item[0],"name":item[1],"description":item[2],"status":"active" if quests.is_empty() else "available","completed":false})
	if Village.enabled(layout):
		Village.companions(actors,layout);quests=Village.initial_quests()
	var facts:Dictionary={"version":5,"scenario":SCENARIO,"time":0.0,"status":"playing","actors":actors,"stocks":seed.initial_stocks.duplicate(true),"actions":[],"quests":quests,"ledger":[],"log":[{"id":"r34:opening","text":quests[0].description,"time":0.0}],"visited":[str(spawns.player.regionId)],"milestones":{},"nextId":1}
	var production:Dictionary=Initial.production(seed)
	# Physical tools/records must have their one real item holder.
	var stocks:Dictionary={}
	for s:Dictionary in facts.stocks:stocks[s.id]=s
	for tool:Dictionary in production.tools:
		if not stocks.has(tool.get("holderId")):return _bad("INITIAL_TOOL_HOLDER_MISSING","起步工具没有真实库存持有人")
	for record:Dictionary in production.records:
		if not stocks.has(record.get("holderId")) or float(stocks[record.holderId].get("items",{}).get(record.get("itemId"),0))<1:return _bad("INITIAL_RECORD_SOURCE_MISSING","起步书册没有唯一实物来源")
	var workforce:Dictionary={"version":1,"assignments":[],"interrupted":[],"events":[],"next_id":1,"layout":layout.duplicate(true)}
	var changes:Array=module_registration.get("world_changes",[]).duplicate(true)
	for change:Variant in changes:
		if not change is Dictionary or (change.get("op")=="extension.set" and change.get("id") in ["r34:workforce",KEY]):return _bad("INITIAL_EXTENSION_CONFLICT","登记DTO不能预发E起步状态")
	changes.append({"op":"extension.set","id":"r34:workforce","before_exists":false,"before":null,"after":workforce})
	var story_state:Dictionary=initial_state(layout);story_state.stories=_initial_stories(facts,production)
	if Village.enabled(layout):Village.refresh_quests(facts,story_state)
	changes.append({"op":"extension.set","id":KEY,"before_exists":false,"before":null,"after":story_state})
	return {"ok":true,"code":"OK","facts":facts,"production_state":production,"world_changes":changes,"module_world_changes":changes.duplicate(true),"content_card":content_card(layout,seed)}

static func validate_state(value:Variant)->Dictionary:
	if not value is Dictionary or value.get("version")!=1 or not Data.json_value(value):return _bad("INVALID_FACTORY_GAMEPLAY","地区事件状态版本或数据无效")
	if not value.get("event_ids") is Array or not value.get("regional_events") is Array or value.event_ids.size()>MAX_EVENTS or value.regional_events.size()>MAX_EVENTS:return _bad("INVALID_FACTORY_GAMEPLAY","地区事件日志无效")
	if not Data.integer(value.get("last_event_revision")) or int(value.last_event_revision)<-1 or not value.get("flags") is Dictionary:return _bad("INVALID_FACTORY_GAMEPLAY","地区事件游标无效")
	var ids:Dictionary={}
	for id:Variant in value.event_ids:
		if not Data.valid_id(id) or ids.has(id):return _bad("INVALID_FACTORY_EVENT_ID","地区事件身份无效或重复")
		ids[id]=true
	for event:Variant in value.regional_events:
		if not event is Dictionary or not ids.has(event.get("id")) or not Data.valid_id(event.get("kind")) or not _number(event.get("time")) or float(event.time)<0:return _bad("INVALID_FACTORY_EVENT","地区事件来源或时间无效")
	var d:Variant=value.get("defense")
	if not d is Dictionary or d.get("status") not in ["dormant","warning","awaiting_execution","active","cleared"] or not d.get("actors") is Array:return _bad("INVALID_FACTORY_DEFENSE","防守状态无效")
	if not _number(d.get("warning_at")) or not _number(d.get("arrival_at")) or float(d.warning_at)<0 or float(d.arrival_at)<float(d.warning_at):return _bad("INVALID_FACTORY_DEFENSE","防守预告时间无效")
	if d.has("warning_remaining") and (not _number(d.warning_remaining) or float(d.warning_remaining)<0 or float(d.warning_remaining)>3600):return _bad("INVALID_FACTORY_DEFENSE","防守有效预告余时无效")
	if d.status!="dormant" and (not Data.valid_id(d.get("warning_id")) or not ids.has(d.get("cause_event_id"))):return _bad("INVALID_FACTORY_DEFENSE","防守预告缺少真实前因")
	if d.status in ["active","cleared"] and d.actors.is_empty():return _bad("INVALID_FACTORY_DEFENSE","不能把无敌人或生成失败称为防守清除")
	var actors:Dictionary={}
	for id:Variant in d.actors:
		if not Data.valid_id(id) or actors.has(id):return _bad("INVALID_FACTORY_DEFENSE","防守人物ID无效或重复")
		actors[id]=true
	if value.has("stories"):
		if not value.stories is Dictionary:return _bad("INVALID_FACTORY_STORY","故事状态无效")
		for key:Variant in value.stories:
			if key not in ["ST01","ST02","ST03","ST04"] or not value.stories[key] is Dictionary:return _bad("INVALID_FACTORY_STORY","故事身份无效")
			var story:Dictionary=value.stories[key]
			if not story.get("sources") is Array or not story.get("flags") is Dictionary or not story.get("people") is Dictionary:return _bad("INVALID_FACTORY_STORY","故事来源／人物记录无效")
			for source:Variant in story.sources:
				if not Data.valid_id(source):return _bad("INVALID_FACTORY_STORY","故事地点来源无效")
			for flag:Variant in story.flags.values():
				if not flag is bool:return _bad("INVALID_FACTORY_STORY","故事阶段不能是虚构数值奖励")
			for person:Variant in story.people:
				if person not in ["village-resident","repair-resident"] or not story.people[person] is Dictionary:return _bad("INVALID_FACTORY_STORY","故事永久人物引用无效")
				for flag:Variant in story.people[person].values():
					if not flag is bool:return _bad("INVALID_FACTORY_STORY","故事关系事实无效")
			if key=="ST02" and not Story.validate_experiences(story):return _bad("INVALID_FACTORY_STORY","共同经历须引用原居民、原事件和实际地点")
	return Regional.validate_objectives(value)

static func advance_in(tx:RefCounted,now:float,dt:float=0.0)->Dictionary:
	if tx.staged.get("scenario")!=SCENARIO:return {"ok":true}
	if not _number(dt) or dt<0 or dt>1:return _bad("INVALID_STEP","地区事件仅消费A同一固定步")
	var state:Dictionary=tx.extension(KEY,initial_state())
	var valid:Dictionary=validate_state(state)
	if not valid.ok:return valid
	var cutoff:int=int(state.last_event_revision);var latest:int=cutoff
	if not state.has("stories"):state.stories=_initial_stories(tx.staged,tx.extension("r3:production"))
	_bind_story_sources(tx,state.stories)
	# Upgrade an old save once, using only its still-present real ledger.
	# New events use the normal observer; never rescan the ledger every STEP.
	if not state.stories.ST02.has("experiences"):
		state.stories.ST02.experiences={}
		for event:Dictionary in tx.staged.get("ledger",[]):_observe_shared(tx,state.stories,event)
	var defense_was_warning:bool=state.defense.status=="warning"
	# IDs, rather than a global revision cutoff, allow a paused region's earlier
	# event to resume after another detailed region has observed a newer event.
	for source:Variant in tx.staged.get("ledger",[]):
		if not source is Dictionary or not Data.integer(source.get("revision")):continue
		if source.get("kind") not in ["talk","invite","consent","help","life-completed","tree-felled","factory-batch-completed","inventory-transfer","learned","crafted","module-project-completed","logistics-delivery-completed","combat-hit","settlement-member-arrived","settlement-site-surveyed","settlement-route-work-started","water-collected","zonework-completed","radio-completed"]:continue
		if state.event_ids.has(source.get("id")):continue
		if not _detailed(tx,_event_region(tx,state,source)):continue
		if not Data.valid_id(source.get("id")) or not _number(source.get("time")) or float(source.time)>now or float(source.time)<0:return _bad("INVALID_FACTORY_EVENT_SOURCE","地区事件缺少A已提交的来源身份／时间")
		latest=maxi(latest,int(source.revision))
		if state.event_ids.has(source.id):continue
		if state.event_ids.size()>=MAX_EVENTS:return _bad("FACTORY_EVENT_LIMIT","地区事件账已达容量，保留原事实")
		state.event_ids.append(source.id)
		state.regional_events.append({"id":source.id,"kind":source.kind,"actor_id":source.get("actor_id",""),"target_id":source.get("target_id",""),"time":float(source.time)})
		_observe_stories(tx,state.stories,source)
		Village.observe(state,source)
		if source.kind=="help":state.flags.helped_someone=true
		elif source.kind=="invite":state.flags.invited_member=true
		elif source.kind=="life-completed":state.flags.real_self_care=true
		elif source.kind=="tree-felled":state.flags.real_harvest=true
		elif source.kind=="factory-batch-completed":
			state.flags.real_machine_output=true
		elif source.kind=="module-project-completed" and source.get("operation")=="build":
			var built:Dictionary=_find(tx.extension("r34:modules").get("instances",[]),str(source.get("module_id","")))
			if built.get("player_built",false) and not built.get("paid_cost",{}).is_empty() and built.get("status")=="operational":
				var shape:String=str(Catalog.definition(str(built.get("definition_id",""))).get("shape",""))
				if shape=="warehouse":state.flags.real_warehouse_built=true
				if shape=="woodshop":state.flags.real_machine_built=true
		elif source.kind=="settlement-route-work-started" and state.defense.status=="dormant":
			var site:Dictionary=Regional.find_site(tx.context,state.get("layout",{}),str(source.get("site_id","")))
			var objective:Dictionary=state.get("regional_objectives",{}).get(source.get("site_id"),{})
			if site.is_empty() or not objective.get("surveyed",false) or not objective.get("risk_accepted",false) or absf(float(objective.get("started_at",-1))-float(source.time))>0.000001:return _bad("INVALID_REGIONAL_EVENT_CAUSE","清障预告缺少真实勘察及知情承诺")
			var lead:float=float(objective.get("warning_seconds",0))
			if lead<60 or lead>3600:return _bad("INVALID_REGIONAL_EVENT_CAUSE","清障预告缺少实际返程准备预算")
			state.defense={"status":"warning","site_id":site.id,"warning_id":"r34:defense:"+str(site.id),"warning_at":now,"arrival_at":now+lead,"warning_remaining":lead,"cause_event_id":source.id,"actors":[],"encounter_positions":site.encounter_positions.duplicate(true)}
			tx.events.append({"kind":"settlement-defense-warning","actor_id":"player","site_id":site.id,"cause_event_id":source.id,"warning_id":state.defense.warning_id,"arrival_at":state.defense.arrival_at})
	state.last_event_revision=latest
	_refresh_stories(tx,state.stories)
	# No accepted/surveyed objective means there is no corridor to test. Do not
	# repeatedly copy and validate generation plans for a dormant normal world.
	for site_id:String in state.get("regional_objectives",{}):
		var site:Dictionary=Regional.find_site(tx.context,state.get("layout",{}),site_id)
		if not site.is_empty() and _detailed(tx,str(site.region_id)):
			state.regional_objectives[site.id].corridor_clear=Regional.corridor_clear(tx.context,site)
	var home_region:String=str(state.get("layout",{}).get("home",{}).get("regionId",""))
	if not _detailed(tx,home_region):return validate_state(state)
	if state.defense.status=="warning":
		# A's elapsed fixed step is the only progress; elapsed remote wall/game
		# time never completes a warning on first revisit.
		var remaining:float=float(state.defense.get("warning_remaining",maxf(0.0,float(state.defense.arrival_at)-now)))
		state.defense.warning_remaining=maxf(0.0,remaining-(dt if defense_was_warning else 0.0))
		state.defense.arrival_at=now+float(state.defense.warning_remaining)
		if float(state.defense.warning_remaining)<=0.000001:state.defense.status="awaiting_execution"
	# Spawn and existing combat remain their owning executor's work. No actors
	# means no victory, including when an encounter anchor failed validation.
	if state.defense.status=="active":
		var all_dead:bool=not state.defense.actors.is_empty()
		for id:String in state.defense.actors:
			var actor:Dictionary=tx.actor(id)
			if actor.is_empty() or not _detailed(tx,str(actor.get("regionId",""))) or actor.get("faction")!="infected" or float(actor.get("hp",0))>0:all_dead=false
		if all_dead:state.defense.status="cleared"
	if state.defense.status=="cleared" and state.get("regional_objectives",{}).has(state.defense.get("site_id")):
		var objective:Dictionary=state.regional_objectives[state.defense.site_id]
		objective.completed=objective.corridor_clear
	_refresh_quests(tx,state)
	return validate_state(state)

static func _refresh_quests(tx:RefCounted,state:Dictionary)->void:
	if Village.enabled(state.get("layout",{})):
		Village.reconcile(tx,state);return
	var story:Dictionary=state.stories.ST01.flags
	if story.get("real_frame_restored",false):state.flags.real_machine_restored=true
	var regional_complete:bool=false
	for objective:Dictionary in state.get("regional_objectives",{}).values():
		if objective.get("completed",false):regional_complete=true
	var requirements:Dictionary={"R34-Q01":[["取得现场工具",story.get("tools_taken",false)],["阅读真实木工记录",story.get("read_woodwork_record",false)],["亲手完成一次锯切",story.get("real_hand_saw_work",false)]],"R34-Q02":[["实际付料建成仓储模块",state.flags.get("real_warehouse_built",false)]],"R34-Q03":[["实际恢复或建成燃料木作坊",state.flags.get("real_machine_built",false) or state.flags.get("real_machine_restored",false)],["真实完成机器批次",state.flags.get("real_machine_output",false)]],"R34-Q04":[["实际通路与地区事件均得到解决",regional_complete]]}
	var previous:=true
	for quest:Dictionary in tx.staged.get("quests",[]):
		if not requirements.has(quest.id):continue
		quest.objectives=[];var done:int=0
		for index:int in requirements[quest.id].size():
			var requirement:Array=requirements[quest.id][index];var fulfilled:bool=bool(requirement[1])
			quest.objectives.append({"id":str(quest.id)+":"+str(index),"text":requirement[0],"status":"已完成" if fulfilled else "待完成"})
			if fulfilled:done+=1
		quest.completed=bool(quest.get("completed",false)) or done==requirements[quest.id].size()
		quest.status="已完成" if quest.completed else "进行中" if previous else "可提前准备"
		quest.progress="%s / %s"%[done,requirements[quest.id].size()];previous=quest.completed

static func _detailed(tx:RefCounted,region_id:String)->bool:
	return tx.context.get("region_is_detailed") is Callable and tx.context.region_is_detailed.call(region_id)

static func _event_region(tx:RefCounted,state:Dictionary,event:Dictionary)->String:
	if event.has("site_id"):
		var site:Dictionary=Regional.find_site(tx.context,state.get("layout",{}),str(event.site_id))
		if not site.is_empty():return str(site.region_id)
	if event.has("module_id"):
		var modules:Dictionary=tx.extension("r34:modules")
		for instance:Dictionary in modules.get("instances",[]):
			if instance.id==event.module_id:return str(instance.get("region",""))
	var actor:Dictionary=tx.actor(str(event.get("actor_id",event.get("actorId",""))))
	return str(actor.get("regionId",state.get("layout",{}).get("home",{}).get("regionId","")))

static func _initial_stories(facts:Dictionary,production:Dictionary)->Dictionary:
	var stories:Dictionary={}
	for id:String in ["ST01","ST02","ST03","ST04"]:stories[id]={"sources":[],"flags":{},"people":{}}
	stories.ST02.experiences={}
	for record:Dictionary in production.get("records",[]):
		if record.get("itemId")=="book_woodwork" and not stories.ST01.sources.has(record.holderId):stories.ST01.sources.append(record.holderId)
	for stock:Dictionary in facts.get("stocks",[]):
		if float(stock.get("items",{}).get("r34:salvaged_drive_unit",0))>0:stories.ST04.sources.append(stock.id)
	return stories

static func _bind_story_sources(tx:RefCounted,stories:Dictionary)->void:
	var modules:Dictionary=tx.extension("r34:modules",{"instances":[],"source_receipts":{}})
	var fields:Array[String]=["module_seeds"]
	var region_ids:Array=tx.context.world.region_ids() if tx.context.world.has_method("region_ids") else tx.context.world.regions().map(func(region:Dictionary)->String:return str(region.id))
	for region_id:String in region_ids:
		var plan:Dictionary=Regional.generation_fields(tx.context,region_id,fields)
		for seed:Dictionary in plan.get("module_seeds",[]):
			if seed.get("purpose")!="store":continue
			var receipt:Dictionary=modules.get("source_receipts",{}).get(seed.get("source_key"),{})
			if receipt.get("module_id")!=seed.id:continue
			for id:String in receipt.get("stock_ids",[]):
				var stock:Dictionary=tx.stock(id)
				if stock.get("module_id")==seed.id and not stories.ST03.sources.has(id):stories.ST03.sources.append(id)

static func _observe_stories(tx:RefCounted,stories:Dictionary,event:Dictionary)->void:
	var actor_id:String=str(event.get("actor_id",event.get("actorId","")))
	_observe_shared(tx,stories,event)
	if actor_id=="player" and event.kind=="learned":
		var production:Dictionary=tx.extension("r3:production")
		var record:Dictionary=_find(production.get("records",[]),str(event.get("targetId","")))
		if _completed_woodwork_read(tx,stories,event,record):stories.ST01.flags.read_woodwork_record=true
		if event.get("source_kind")=="teacher" and event.get("teacher_id")=="repair-resident" and event.get("knowledge_id")=="basic_tool_repair":
			var order:Dictionary=_find(production.get("orders",[]),str(event.get("orderId","")))
			if order.get("status")=="completed" and order.get("kind")=="study" and order.get("learning_source")=="teacher" and order.get("actorId")=="player" and order.get("targetId")=="repair-resident" and order.get("teacher_id")=="repair-resident" and order.get("knowledge_id")=="basic_tool_repair" and production.get("knowledge",{}).get("player",[]).has("basic_tool_repair"):
				var person:Dictionary=stories.ST02.people.get("repair-resident",{})
				person.taught=true;stories.ST02.people["repair-resident"]=person
	if actor_id=="player" and event.kind=="crafted" and event.get("targetId")=="saw_timber":stories.ST01.flags.real_hand_saw_work=true
	if actor_id=="player" and event.kind=="inventory-transfer" and event.get("output_id")=="pack:player":
		var source:String=str(event.get("source_id",""));var items:Dictionary=event.get("items",{})
		if stories.ST01.sources.has(source) and not event.get("tool_ids",[]).is_empty():stories.ST01.flags.tools_taken=true
		if stories.ST03.sources.has(source) and (float(items.get("food",0))>0 or float(items.get("water",0))>0):stories.ST03.flags.real_supplies_taken=true
		if stories.ST04.sources.has(source) and float(items.get("r34:salvaged_drive_unit",0))>0:stories.ST04.flags.drive_unit_taken=true
	if event.kind=="factory-batch-completed":stories.ST01.flags.real_machine_output=true
	if event.kind=="logistics-delivery-completed" and actor_id in ["village-resident","repair-resident"]:
		var person:Dictionary=tx.actor(actor_id)
		if person.get("relationship",{}).get("member",false) and person.get("relationship",{}).get("consent",false):
			var participation:Dictionary=stories.ST02.people.get(actor_id,{})
			participation.real_delivery=true;stories.ST02.people[actor_id]=participation

static func _refresh_stories(tx:RefCounted,stories:Dictionary)->void:
	# Completed production facts survive the short ledger and old save cursors.
	# Reconcile only these missing consequences; this never grants knowledge.
	if not stories.ST01.flags.get("read_woodwork_record",false):
		var production:Dictionary=tx.extension("r3:production")
		for event:Dictionary in production.get("facts",[]):
			if event.get("kind")!="learned" or event.get("actorId")!="player":continue
			var record:Dictionary=_find(production.get("records",[]),str(event.get("targetId","")))
			if _completed_woodwork_read(tx,stories,event,record):stories.ST01.flags.read_woodwork_record=true;break
	if not stories.ST01.flags.get("real_frame_restored",false):
		var modules:Dictionary=tx.extension("r34:modules")
		for instance:Dictionary in modules.get("instances",[]):
			var restoration:Dictionary=instance.get("restoration",{})
			if not instance.get("discovered",false) or instance.get("player_built",false) or restoration.get("policy")!="s01-frame-v1" or not restoration.get("completed",false):continue
			var project:Dictionary=_find(modules.get("projects",[]),str(restoration.get("project_id","")))
			if project.get("module_id")==instance.id and project.get("operation")=="restore" and project.get("status")=="completed" and Data.json_equal(project.get("cost"),{"timber":8,"scrap":4,"r34:salvaged_drive_unit":1}) and is_equal_approx(float(project.get("progress_seconds",0)),40):stories.ST01.flags.real_frame_restored=true;break
	for id:String in ["village-resident","repair-resident"]:
		var actor:Dictionary=tx.actor(id)
		if actor.is_empty() or not _detailed(tx,str(actor.regionId)):continue
		var person:Dictionary=stories.ST02.people.get(id,{})
		for flag:String in ["met","helped","member","consent","home_arrived"]:person[flag]=bool(actor.get("relationship",{}).get(flag,false))
		stories.ST02.people[id]=person

static func _observe_shared(tx:RefCounted,stories:Dictionary,event:Dictionary)->void:
	if event.get("kind") not in ["logistics-delivery-completed","combat-hit"]:return
	var id:String=str(event.get("actor_id",""))
	if id not in ["village-resident","repair-resident"] or stories.ST02.get("experiences",{}).has(id):return
	var actor:Dictionary=tx.actor(id)
	if actor.is_empty() or not actor.get("relationship",{}).get("member",false) or not _detailed(tx,str(actor.regionId)):return
	if not Data.valid_id(event.get("id")) or not _number(event.get("time")) or float(event.time)<0 or float(event.time)>float(tx.staged.time):return
	var memory:Dictionary={"event_id":event.id,"time":float(event.time)}
	if event.kind=="logistics-delivery-completed":
		var stock:Dictionary=tx.stock(str(event.get("destination_id","")))
		if stock.is_empty() or not _location(stock.get("location")) or not _detailed(tx,str(stock.location.regionId)) or not Data.valid_id(event.get("source_id")) or not Data.valid_id(event.get("task_id")):return
		memory.merge({"action":"delivery","task_id":event.task_id,"source_id":event.source_id,"destination_id":event.destination_id,"location":stock.location.duplicate(true)})
	else:
		var target:Dictionary=tx.actor(str(event.get("target_id","")))
		if target.get("faction")!="infected" or target.get("regionId")!=actor.regionId or not _number(event.get("damage")) or float(event.damage)<=0 or not Data.vec(event.get("position")):return
		memory.merge({"action":"defense","target_id":target.id,"location":event.position.merged({"regionId":actor.regionId})})
	if not stories.ST02.has("experiences"):stories.ST02.experiences={}
	stories.ST02.experiences[id]=memory
	var person:Dictionary=stories.ST02.people.get(id,{})
	person["real_delivery" if memory.action=="delivery" else "real_defense"]=true
	stories.ST02.people[id]=person

static func _completed_woodwork_read(tx:RefCounted,stories:Dictionary,event:Dictionary,record:Dictionary)->bool:
	if record.get("itemId")!="book_woodwork" or event.get("source_kind","book")!="book":return false
	var production:Dictionary=tx.extension("r3:production")
	var order:Dictionary=_find(production.get("orders",[]),str(event.get("orderId","")))
	if order.get("kind")!="study" or order.get("status")!="completed" or order.get("actorId")!="player" or order.get("targetId")!=record.get("id") or order.get("learning_source","book")!="book" or not production.get("knowledge",{}).get("player",[]).has("basic_woodwork"):return false
	if stories.ST01.sources.has(record.get("holderId")):return true
	# A transferred record keeps B's original registered identity. Its current
	# holder is the real player pack, not its workshop source container.
	for source:String in stories.ST01.sources:
		var stock:Dictionary=tx.stock(source);var module_id:String=str(stock.get("module_id",""))
		if not module_id.is_empty() and record.get("id")==module_id+":record:book_woodwork":return true
	return false

static func _find(rows:Array,id:String)->Dictionary:
	for row:Dictionary in rows:
		if row.id==id:return row
	return {}

static func story_projection(state:Dictionary,facts:Dictionary={},context:Dictionary={})->Array:
	return Story.projection(state,facts,context)

static func content_card(layout:Dictionary={},seed:Dictionary={})->Dictionary:
	if Village.enabled(layout):
		return {"scenario":SCENARIO,"opening_version":3,"player_pack":{"food":1,"water":1},"npc_packs":{"village-resident":{"food":1,"water":1},"repair-resident":{"food":1,"water":1}},"sources":seed.get("initial_stocks",[]).duplicate(true),"tools":seed.get("initial_tools",[]).duplicate(true),"records":seed.get("initial_records",[]).duplicate(true),"registration_owner":"Original one-time A/B source receipts; this card grants no additional inventory.","route":["settle","harvest-and-haul","hand-saw","restore-warehouse","stable-food-water","production-and-upgrades","radio","regional-expansion"]}
	return {"scenario":SCENARIO,"player_pack":{"food":1,"water":1},"npc_packs":{},"sources":[
		{"role":"home","owner":"home-residents","searched":true,"items":{"food":2,"water":3,"cloth":2,"timber":2,"scrap":1}},
		{"role":"woodwork","owner":"home-residents","searched":false,"items":{"timber":8,"scrap":6,"book_woodwork":1,"book_tool_repair":1},"tools":[{"kind":"salvaged_axe","durability":85.0},{"kind":"hand_saw","durability":100.0},{"kind":"hammer","durability":100.0}],"records":[{"itemId":"book_woodwork","grants":["basic_woodwork"],"seconds":12.0},{"itemId":"book_tool_repair","grants":["basic_tool_repair"],"seconds":12.0}]},
		{"role":"store","owner":null,"searched":false,"items":{"food":6,"water":6,"scrap":3}},
		{"role":"stockyard-content","owner":null,"searched":false,"items":{"axe_head":1,"tool_handle":1,"scrap":4,"r34:salvaged_drive_unit":1},"tools":[{"kind":"shovel","durability":100.0},{"kind":"pickaxe","durability":100.0}]}],
		"registration_owner":"A/B; each source must bind a C stable anchor and one persistent registration receipt; this card issues no inventory",
		"power_component":{"status":"A_registered","item_id":"r34:salvaged_drive_unit","source":"C stockyard-content anchor, one B registration receipt","quantity":1},"machine_recipe":{"inputs":{"log":1},"outputs":{"timber":4},"seconds":10.0,"fuel":{"item_id":"log","seconds_per_item":20.0},"registration":"B owns recipe/energy and A owns catalog; this card emits no production"}}

static func _location(value:Variant)->bool:
	return value is Dictionary and Data.vec(value) and Data.valid_id(value.get("regionId"))
static func _number(value:Variant)->bool:return (value is int or value is float) and is_finite(float(value))
static func _bad(code:String,reason:String)->Dictionary:return {"ok":false,"code":code,"reason":reason}
