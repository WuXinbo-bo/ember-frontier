extends RefCounted
## Read-only story stages and a source-bound, physical reading transaction.
## C supplies environmental records; B retains stock/contact authority.
const Data=preload("res://scripts/world/world_data.gd")
const Regional=preload("res://scripts/runtime/factory_gameplay_region.gd")
const KEY="r34:gameplay"
const Village=preload("res://scripts/runtime/village_progression.gd")

static func records(context:Dictionary,state:Dictionary)->Array:
	var result:Array=[]
	if context.is_empty():return result
	var sources:Array=state.get("stories",{}).get("ST03",{}).get("sources",[])
	if sources.is_empty():return result
	var modules:Dictionary=context.world.extension("r34:modules")
	var fields:Array[String]=["module_seeds"]
	for region:Dictionary in context.world.regions():
		var plan:Dictionary=Regional.generation_fields(context,str(region.id),fields)
		for seed:Dictionary in plan.get("module_seeds",[]):
			if seed.get("purpose")!="store":continue
			var receipt:Dictionary=modules.get("source_receipts",{}).get(seed.get("source_key"),{})
			if receipt.get("module_id")!=seed.id:continue
			for source:String in receipt.get("stock_ids",[]):
				if not sources.has(source):continue
				var stock:Dictionary=context.stock.call(source)
				if stock.get("module_id")!=seed.id or not stock.get("searched",false):continue
				for clue:Variant in seed.get("story_clues",[]):
					if not clue is Dictionary or clue.get("version")!=1 or clue.get("story_id")!="ST03" or clue.get("kind")!="route-record" or not clue.get("text") is String:continue
					if clue.get("source_key")!=seed.get("source_key") or clue.get("module_id")!=seed.id or clue.get("id")!=str(seed.source_key)+":route-record:"+str(clue.get("site_id","")):continue
					var site:Dictionary=Regional.find_site(context,state.get("layout",{}),str(clue.get("site_id","")))
					if site.is_empty():continue
					result.append({"id":clue.id,"story_id":"ST03","source_id":source,"site_id":site.id,"text":clue.text,"location":site.survey_point.duplicate(true)})
	return result

static func read_availability(context:Dictionary,state:Dictionary,request:Dictionary,production:RefCounted)->Dictionary:
	var payload:Variant=request.get("payload",{})
	if payload is Dictionary and payload.get("story_id")=="ST02":return review_availability(context,state,request,context.get("story_social",Callable()))
	if not payload is Dictionary or payload.get("story_id")!="ST03" or not Data.valid_id(payload.get("source_id")):return Regional.bad("INVALID_STORY_SOURCE","需要已发现小店的真实路线记录来源")
	var actor:Dictionary=context.actor.call(str(request.get("actor_id","")))
	if actor.is_empty() or actor.id!="player" or float(actor.get("hp",0))<=0:return Regional.bad("ACTOR_UNAVAILABLE","由玩家在现场阅读路线记录")
	if actor.get("intent")!=null:return Regional.bad("BUSY","先结束当前行动再阅读")
	var matching:Array=records(context,state).filter(func(row:Dictionary)->bool:return row.source_id==payload.source_id)
	if matching.is_empty():return Regional.bad("STORY_RECORD_UNAVAILABLE","没有此来源登记且可核对的真实路线记录")
	var stock:Dictionary=context.stock.call(str(payload.source_id))
	if not context.region_is_detailed.call(str(actor.regionId)) or not context.region_is_detailed.call(str(stock.get("location",{}).get("regionId",""))):return Regional.bad("REGION_PAUSED","记录所在地区未详细模拟")
	var problem:Variant=production.reach(str(actor.id),str(stock.id),stock)
	if problem!=null:return Regional.bad("OUT_OF_REACH",str(problem))
	return {"ok":true,"code":"OK","reason":null,"records":matching}

static func prepare_read(tx:RefCounted,state:Dictionary,request:Dictionary,production:RefCounted)->Dictionary:
	var ready:Dictionary=read_availability(tx.context,state,request,production)
	if not ready.ok:return ready
	if request.payload.story_id=="ST02":
		var id:String=request.payload.person_id
		state.stories.ST02.people[id].reviewed=true
		var event:Dictionary=ready.experience.duplicate(true)
		event.merge({"kind":"settlement-story-reviewed","actor_id":"player","story_id":"ST02","person_id":id},true)
		event.erase("time") # Runtime stamps this command, not the original memory time.
		tx.events.append(event)
		return {"ok":true}
	var source:String=request.payload.source_id
	var flags:Dictionary=state.stories.ST03.flags
	if flags.get("read_source:"+source,false):return {"ok":true}
	flags["read_source:"+source]=true;flags.read_route_record=true
	for row:Dictionary in ready.records:tx.events.append({"kind":"settlement-story-read","actor_id":"player","story_id":"ST03","source_id":source,"clue_id":row.id,"site_id":row.site_id})
	return {"ok":true}

static func review_availability(context:Dictionary,state:Dictionary,request:Dictionary,social:Callable)->Dictionary:
	var payload:Dictionary=request.payload;var id:Variant=payload.get("person_id")
	if id not in ["village-resident","repair-resident"] or request.get("target_id")!=id:return Regional.bad("INVALID_STORY_PERSON","回顾对象须是原居民本人")
	var person:Dictionary=state.get("stories",{}).get("ST02",{}).get("people",{}).get(id,{})
	var memory:Dictionary=state.get("stories",{}).get("ST02",{}).get("experiences",{}).get(id,{})
	if not person.get("met",false) or memory.is_empty() or payload.get("event_id")!=memory.get("event_id"):return Regional.bad("SHARED_EXPERIENCE_REQUIRED","需要这位居民已实际完成的交付或协防记录")
	if person.get("reviewed",false):return Regional.bad("ALREADY_REVIEWED","这次共同经历已在现场回顾过")
	var player:Dictionary=context.actor.call(str(request.get("actor_id","")))
	var other:Dictionary=context.actor.call(id)
	if player.get("id")!="player" or float(player.get("hp",0))<=0 or float(other.get("hp",0))<=0:return Regional.bad("ACTOR_UNAVAILABLE","双方须仍能在现场交流")
	if player.get("intent")!=null:return Regional.bad("BUSY","先结束当前行动再回顾")
	if not context.region_is_detailed.call(str(player.regionId)) or not context.region_is_detailed.call(str(other.regionId)):return Regional.bad("REGION_PAUSED","双方所在地区须正在详细模拟")
	if not social.is_valid():return Regional.bad("SOCIAL_UNAVAILABLE","原现场交流检查尚未装配")
	var ready:Dictionary=social.call({"kind":"talk","actor_id":"player","target_id":id})
	return {"ok":true,"code":"OK","reason":null,"experience":memory.duplicate(true)} if ready.ok else ready

static func validate_experiences(story:Dictionary)->bool:
	var memories:Variant=story.get("experiences",{})
	if not memories is Dictionary or memories.size()>2:return false
	for id:Variant in memories:
		var row:Variant=memories[id]
		if id not in ["village-resident","repair-resident"] or not row is Dictionary:return false
		if not Data.valid_id(row.get("event_id")) or row.get("action") not in ["delivery","defense"] or not row.get("time") is float and not row.get("time") is int:return false
		if not is_finite(float(row.time)) or float(row.time)<0 or not row.get("location") is Dictionary or not Data.vec(row.location) or not Data.valid_id(row.location.get("regionId")):return false
		if row.action=="delivery" and (not Data.valid_id(row.get("source_id")) or not Data.valid_id(row.get("destination_id")) or not Data.valid_id(row.get("task_id"))):return false
		if row.action=="defense" and not Data.valid_id(row.get("target_id")):return false
	return true

static func projection(state:Dictionary,facts:Dictionary={},context:Dictionary={})->Array:
	var result:Array=[];var stories:Dictionary=state.get("stories",{})
	var village:bool=Village.enabled(state.get("layout",{}))
	var first_chapter:bool=Village.first_chapter(state.get("layout",{}))
	var titles:Dictionary={"ST01":"主人离开的木工小院","ST02":"有人居住的邻里小院","ST03":"被搜过的临路小店","ST04":"田边仓棚与旧料场"}
	if village:
		titles.ST01="旧村手工棚与第一批板材";titles.ST02="一起归来的两位同伴";titles.ST04="待修仓棚与田边旧料场"
	for id:String in titles:
		var story:Dictionary=stories.get(id,{"sources":[],"flags":{},"people":{}})
		var flags:Dictionary=story.flags;var known:Array=[];var people:Dictionary={}
		for source:String in story.sources:
			for stock:Dictionary in facts.get("stocks",[]):
				if stock.id==source and stock.get("searched",false):known.append(source);break
		for person:String in story.people:
			if story.people[person].get("met",false) or story.people[person].get("member",false):people[person]=story.people[person].duplicate(true)
		# Consent commands commit before the next fixed STEP. Display their
		# current authority immediately; persisted memories remain unchanged.
		for actor:Dictionary in facts.get("actors",[]):
			if not people.has(actor.id):continue
			for flag:String in ["met","helped","member","consent","home_arrived"]:people[actor.id][flag]=bool(actor.get("relationship",{}).get(flag,false))
		var text:String="";var stage:String="unseen";var clues:Array=[];var commands:Array=[];var experiences:Dictionary={};var followups:Array=[]
		if id=="ST01":
			text="记录写着：‘机器停了，手锯还能用。总成送到田边仓棚检修。’主人去向尚不明确。先取有权工具与材料、阅读原木工手册；现成手工点可分批锯切，累了就停工休息。"
			if village:text="三人带来的基础工具放在旧村手工棚。先取工具、读木工手册，采运原木后亲手锯板，再修复原址仓棚。锯木机器要之后实际付料建设，空场地不会自动变成工厂。"
			stage="tools_found" if flags.get("tools_taken",false) else "workshop_found"
			if first_chapter:text="打开同伴头像就能下单。圈一片近林，把原木送回手工作坊；修复缺板材时，同伴会先锯料。你也可以自己读手册并锯板。修好旧宅和仓棚后，再决定修旧锯木站还是另建一台。"
			if flags.get("read_woodwork_record",false):stage="record_learned";text+="\n你已经读过真实手册；知识不依赖邀请任何居民，教学也不会自动招募。"
			if flags.get("real_hand_saw_work",false):stage="hand_worked";text+="\n亲手锯出的板件已经进入实际库存，后续建设仍需实付材料与劳动，没有额外任务赠品。"
			if flags.get("real_frame_restored",false):stage="frame_restored";text+="\n原址旧框架已实际付料恢复；它保留原身份，继续生产仍需运入原木和燃料。"
			if flags.get("real_machine_output",false):stage="machine_worked";text+="\n机器已真实产出；继续运作仍要补充原料、燃料并检查输出空间。"
		elif id=="ST02":
			text="院内物资有主人，看到料架不代表有权取走。交谈、实际物资交接、邀请、返家和岗位安排分别进行；认识一人不会替另一人作决定。"
			if village:text="%s和%s与你一起抵达旧村，已自愿加入共同生活。可以直接商量真实搬运与生产岗位；同伴会照顾食水和休息，也可以撤回合作。"%[_person_name(facts,"village-resident"),_person_name(facts,"repair-resident")]
			stage="met" if not people.is_empty() else "unseen"
			for person:String in people:
				var p:Dictionary=people[person];var name:String=_person_name(facts,person)
				var line:String="我暂时不搬走。你愿意把需要的物资当面交给我，咱们再谈。"
				if person=="repair-resident" and not p.get("helped",false):line+="先把真实手锤带回来，确认还可以干修理活。"
				if p.get("helped",false):line="东西已经收到了。你可以再问我是否愿意同行；这次帮助不等于替我答应工作。"
				if p.get("member",false):
					if not p.get("consent",false):line="我已撤回合作，先照顾自己的生活。以前的交接记录保留，不能再替我派活。"
					elif not p.get("home_arrived",false):line="我愿意同行，正沿实际道路返家。到家前先别把我算作已经在工位。"
					else:line="已经到家了。可以商量岗位；缺食水或累了先停工补给，货物交接仍要实际完成。"
				if p.get("real_delivery",false):line+="你备下的东西，我确实送到过。以后仍按这趟的实际路程和容量来安排。"
				if p.get("taught",false):line+="基础工具维修已经在现场教过你；学到的知识会保留，同行与岗位仍由我自己决定。"
				var memory:Dictionary=story.get("experiences",{}).get(person,{})
				if not memory.is_empty():
					experiences[person]=memory.duplicate(true)
					if p.get("reviewed",false):
						var place:Dictionary=memory.location
						line+="我们已经在现场回顾过：在%s（%.1f，%.1f）的%s。"%[place.regionId,place.x,place.z,"实际交付至 "+str(memory.destination_id) if memory.action=="delivery" else "实际协防 "+str(memory.target_id)]
						followups.append({"panel":"workforce","target_id":person,"label":"查看岗位"})
						if p.get("member",false) and p.get("consent",false):followups.append({"kind":"job","target_id":person,"payload":{"job":"rest"},"label":"先补给休息"})
					else:commands.append({"kind":"settlement.read_story","target_id":person,"payload":{"story_id":"ST02","person_id":person,"event_id":memory.event_id},"label":"在现场回顾共同经历"})
				text+="\n"+name+"：‘"+line+"’"
		elif id=="ST03":
			text="货架已经被搜过，剩余食水只以现场容器为准。取走后重访仍为空；没有刷新补给或额外奖励。"
			stage="supplies_taken" if flags.get("real_supplies_taken",false) else "store_searched"
			for row:Dictionary in records(context,state):
				if not flags.get("read_source:"+str(row.source_id),false):
					var request:Dictionary={"kind":"settlement.read_story","actor_id":"player","payload":{"story_id":"ST03","source_id":row.source_id}}
					commands.append({"kind":request.kind,"payload":request.payload,"label":"在现场阅读路线记录"})
					text+="\n已搜到路线记录，须回到这处真实来源旁阅读，才记入已知线索。"
					continue
				stage="route_read";text+="\n记录：‘"+str(row.text)+"’先实际勘察再决定是否清障；读记录不触发来袭。"
				clues.append({"id":row.site_id,"kind":"route_clue","title":"路线记录：待勘察塌石","location":row.location.duplicate(true),"completed":false})
		elif id=="ST04":
			text="田边料场留下可回收物和一件真实动力总成。可先沿现有路手搬，再决定是否整理场地、清理瓶颈或实付材料设置暂存；暂存后仍需要第二趟转运。清障不会额外赠送材料。"
			stage="stockyard_found"
			if flags.get("drive_unit_taken",false):stage="drive_carried";text+="\n总成已从原容器取出。携带、放入和建设沿同一库存结算，保存或重访不会再补一件。"
			if state.get("flags",{}).get("real_machine_built",false):stage="machine_built";text+="\n自建燃料木作坊已实际付料建成；搬走总成或另设暂存点不会凭文字复制机器。"
		var available:bool=not people.is_empty() if id=="ST02" else not known.is_empty() or flags.values().has(true)
		result.append({"id":id,"title":titles[id],"text":text if available else "尚未发现此地点的真实线索。","stage":stage if available else "unseen","available":available,"sources":known,"flags":flags.duplicate(true) if available else {},"people":people,"clues":clues if available else [],"commands":commands if available else [],"experiences":experiences,"followups":followups,"reward":null})
	return result

static func _person_name(facts:Dictionary,id:String)->String:
	for actor:Dictionary in facts.get("actors",[]):
		if actor.get("id")==id:return str(actor.get("name",id))
	return "周婶" if id=="village-resident" else "老许" if id=="repair-resident" else id
