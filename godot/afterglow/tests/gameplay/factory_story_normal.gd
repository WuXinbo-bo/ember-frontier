extends "res://tests/gameplay/factory_knowledge_pressure.gd"
## Content7 original finite social/economic world, no fixture edits.
const Shape=preload("res://scripts/modules/module_geometry.gd")
var live:RefCounted
var commands:Array=[]
var checkpoints:Array=[]
var violations:Array=[]
var frame_id:String=""
var branch:String="restore"
func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	var req:Dictionary={"command_id":"r34:e:s01-normal:"+branch+":%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination}
	var result:Dictionary=runtime.command(req);commands.append({"time":runtime.clock(),"request":req,"result":result});return result
func observe(runtime:RefCounted)->void:
	for actor:Dictionary in runtime.facts().actors:
		if actor.hp!=100:violations.append({"time":runtime.clock(),"id":actor.id,"reason":"original_hp_changed"})
func remember(label:String)->void:
	checkpoints.append({"label":label,"time":live.clock(),"facts":live.facts(),"modules":live.world.extension("r34:modules"),"production":live.world.extension("r34:production"),"gameplay":live.world.extension(Gameplay.KEY)})
func frame(runtime:RefCounted)->Dictionary:return runtime._services.modules.instance(frame_id)
func port(runtime:RefCounted,id:String,name:String)->Dictionary:
	var instance:Dictionary=runtime._services.modules.instance(id)
	for p:Dictionary in Catalog.definition(instance.definition_id).ports:
		if p.id==name:return Shape.at(instance,Vector3(float(p.position[0]),float(p.position[1]),float(p.position[2])))
	return {}
func approach(runtime:RefCounted,at:Dictionary)->bool:
	if walk(runtime,at).get("ok",false):return true
	return walk(runtime,runtime.world.extension(Gameplay.KEY).layout.home).get("ok",false) and walk(runtime,at).get("ok",false)
func recover_stamina(runtime:RefCounted)->bool:
	for i:int in 6:
		if runtime.actor("player").stamina>=78:return true
		var rested:Dictionary=send(runtime,"rest")
		if not rested.get("ok",false) or not progress(runtime,150).finished:return false
	return runtime.actor("player").stamina>=78
func run()->void:
	output_dir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output_dir)
	var options:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[2]))
	branch=str(options.get("probe_mode","restore"))
	if branch.begins_with("consequence"):return actual_consequences()
	if branch=="audit":return audit_actual()
	if branch=="relocate":return relocate_actual()
	var config:Dictionary=Contract.fresh(Modules.generation_profiles(),7,1)
	check("actual adopted content7 generation contract",config.get("ok",false))
	if not config.get("ok",false):return finish()
	var built:Dictionary=normal_tools(config.contract)
	if not built.get("ok",false):return finish()
	var r:RefCounted=built.runtime;live=r
	var frames:Array=r.world.extension("r34:modules").instances.filter(func(i:Dictionary)->bool:return i.has("restoration"))
	check("same normal opening contains exactly one real original damaged frame",frames.size()==1 and frames[0].hp==120 and frames[0].status=="damaged" and not frames[0].restoration.completed and not frames[0].player_built)
	if frames.size()!=1:return finish()
	frame_id=frames[0].id
	if not transfer(r,"take",built.yard_stock,{"r34:salvaged_drive_unit":1}):return finish()
	if not transfer(r,"take",TOOLSTOCK,{"timber":8,"scrap":4,"book_woodwork":1},[HAMMER]):return finish()
	var learned:Dictionary=send(r,"study",SHED+":record:book_woodwork",{"direct":false})
	check("actual original woodwork book learned through paid time",learned.get("ok",false) and progress(r,300).finished and r.world.extension("r3:production").knowledge.player.has("basic_woodwork"))
	if not learned.get("ok",false):return finish()
	check("original finite tools and drive sources depleted exactly",r.stock(built.yard_stock).items.get("r34:salvaged_drive_unit",0)==0 and r.stock(TOOLSTOCK).items.timber==0 and r.stock(TOOLSTOCK).items.scrap==2 and r.tool(HAMMER).holderId=="pack:player")
	if not recover_stamina(r):check("normal rest before restoration",false);return finish()
	check("real player carries finite8boards4scrap drive and hammer to frame work port",approach(r,port(r,frame_id,"work")))
	var discover:Dictionary=send(r,"module.discover",frame_id)
	check("actual frame discovery onsite",discover.get("ok",false),discover)
	if not discover.get("ok",false):return finish()
	var bypass:Dictionary=send(r,"module.repair",frame_id,{"source_id":"pack:player","tool_id":HAMMER})
	check("ordinary repair cannot bypass real missing frame components",not bypass.get("ok",false) and bypass.get("code")=="MODULE_RESTORATION_REQUIRED",bypass)
	var before_pack:Dictionary=r.actor("player").pack.duplicate(true);var hammer_before:float=r.tool(HAMMER).durability
	remember("actual finite source components carried to original damaged frame")
	save(r,"normal-frame-ready")
	var restored:Dictionary=send(r,"module.restore",frame_id,{"source_id":"pack:player","tool_id":HAMMER})
	check("normal finite original same-id restoration begins",restored.get("ok",false),restored)
	if not restored.get("ok",false):return finish()
	step(r,100)
	var cold:Dictionary=cold_restore(r,"normal-frame-restoration-ten-seconds")
	if not cold.get("ok",false):return finish()
	r=cold.runtime;live=r
	check("real40 effective labor finishes same frame after active cold",progress(r,500).finished and frame(r).restoration.completed and frame(r).hp==300 and frame(r).status=="operational")
	check("exact original8boards4scrap and unique drive paid with real6 hammer wear",r.actor("player").pack.timber==before_pack.timber-8 and r.actor("player").pack.scrap==before_pack.scrap-4 and r.actor("player").pack.get("r34:salvaged_drive_unit",0)==0 and absf(hammer_before-r.tool(HAMMER).durability-6)<0.000001 and Data.json_equal(frame(r).restoration.historical_cost,{"timber":12,"scrap":4}))
	remember("original frame restored by real paid40 labor")
	if not recover_stamina(r):check("real rest before actual harvest",false);return finish()
	var trees:Array=r.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a.position).distance_squared_to(Geometry.point(r.actor("player")))<Geometry.point(b.position).distance_squared_to(Geometry.point(r.actor("player"))))
	var harvested:bool=false
	for tree:Dictionary in trees.slice(0,10):
		var action:Dictionary=send(r,"harvest",tree.id,{"direct":false,"tool_ids":[built.axe]})
		if not action.get("ok",false):continue
		if not progress(r,1000).finished:break
		if r.world.entity(tree.id).data.harvest.phase!="stump":break
		harvested=transfer(r,"take",str(tree.data.outputId),{"log":3});break
	check("actual original finite tree harvested and three logs carried",harvested)
	if not harvested:return finish()
	for spec:Array in [["input",2],["fuel",1]]:
		var stock:String=frame(r).stock_refs[spec[0]]
		if not contact(r,stock):
			if not approach(r,r.world.extension(Gameplay.KEY).layout.home) or not contact(r,stock):check("real frame feed port unavailable",false,stock);return finish()
		check("actual carried logs deposited into frame "+str(spec[0]),send(r,"deposit",stock,{"items":{"log":spec[1]}}).get("ok",false))
	var configure:Dictionary=send(r,"factory.configure",frame_id,{"recipe_id":"saw_timber","batches":2})
	check("restored original machine configured onsite",configure.get("ok",false),configure)
	if not configure.get("ok",false):return finish()
	var output:String=frame(r).stock_refs.output;var baseline:float=r.stock(output).items.get("timber",0)
	for i:int in 600:
		step(r)
		if float(r.stock(output).items.get("timber",0))==baseline+8:break
	check("same restored frame really produces eight boards from finite3log",r.stock(output).items.get("timber",0)==baseline+8 and r.stock(frame(r).stock_refs.input).items.get("log",0)==0 and r.stock(frame(r).stock_refs.fuel).items.get("log",0)==0)
	remember("actual original restored frame produces finite two batches")
	cold=cold_restore(r,"normal-restored-frame-real-production")
	check("complete normal recovery and production full cold keeps same frame",cold.get("ok",false) and cold.runtime._services.modules.instance(frame_id).restoration.completed and cold.runtime.stock(output).items.timber==8)
	check("normal recovery never alters original people HP or recruitment",violations.is_empty() and r.facts().actors.size()==3 and r.facts().actors.filter(func(a:Dictionary)->bool:return a.id!="player").all(func(a:Dictionary)->bool:return not a.relationship.member))
	finish()
func mount_actual(path:String)->Dictionary:
	var raw:String=FileAccess.get_file_as_string(path);sources.append({"path":path,"sha256":raw.sha256_text()})
	var decoded:Dictionary=Store.decode(raw);var n:=Native.new();var mounted:Dictionary=n._assemble(decoded.capture) if decoded.get("ok",false) else decoded;n.free()
	check("untouched actual normal source mounts "+path.get_file(),mounted.get("ok",false))
	return mounted
func audit_actual()->void:
	var args:=OS.get_cmdline_user_args();var made:Dictionary=mount_actual(args[1])
	if not made.get("ok",false):return finish()
	var r:RefCounted=made.runtime;live=r;frame_id="RH-HOME:woodshop-old-frame"
	var base:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1].get_base_dir()+"/normal-frame-ready.native.json"))
	check("actual pre-recovery source decodes without editing",base.get("ok",false))
	if not base.get("ok",false):return finish()
	var old:Dictionary=Tx.find(base.capture.facts.actors,"player");var pack:Dictionary=r.actor("player").pack
	check("original completed journey pays exact8boards4scrap and unique drive",pack.timber==old.pack.timber-8 and pack.scrap==old.pack.scrap-4 and pack.get("r34:salvaged_drive_unit",0)==0)
	check("original same hammer pays exact6 wear and preserved historical12/4 canonical values",absf(100-r.tool(HAMMER).durability-6)<0.000001 and Data.json_equal(frame(r).restoration.historical_cost,{"timber":12,"scrap":4}) and frame(r).restoration.completed and frame(r).hp==300)
	var production:Dictionary=r.world.extension("r34:production")
	check("actual original recovery already made exactly two paid batches",production.batches.filter(func(b:Dictionary)->bool:return b.module_id==frame_id and b.status=="completed").size()==2 and r.stock(frame(r).stock_refs.output).items.timber==8)
	var cold:Dictionary=cold_restore(r,"normal-recovery-audited-original-success")
	check("original whole recovery and finite output cold authority intact",cold.get("ok",false) and violations.is_empty())
	remember("original actual success audited without replaying its green actions")
	finish()
func harvest_three(runtime:RefCounted)->bool:
	if not recover_stamina(runtime):return false
	var trees:Array=runtime.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a.position).distance_squared_to(Geometry.point(runtime.actor("player")))<Geometry.point(b.position).distance_squared_to(Geometry.point(runtime.actor("player"))))
	for tree:Dictionary in trees.slice(0,10):
		var action:Dictionary=send(runtime,"harvest",tree.id,{"direct":false,"tool_ids":[SHED+":tool:salvaged_axe"]})
		if not action.get("ok",false):continue
		if not progress(runtime,1000).finished:return false
		if runtime.world.entity(tree.id).data.harvest.phase!="stump":return false
		return transfer(runtime,"take",str(tree.data.outputId),{"log":3})
	return false
func construct_relocated(runtime:RefCounted)->String:
	if not recover_stamina(runtime):return ""
	var chosen:Dictionary={};var tried:Dictionary={};var identity:String="r34:e:s01-normal-relocated"
	for z:int in range(10,57,2):
		for x:int in range(18,57,2):
			if Vector2(x,z).distance_to(Vector2(frame(runtime).position.x,frame(runtime).position.z))<8:continue
			var at:Dictionary={"x":float(x),"y":runtime.world.surface_height(x,z),"z":float(z),"regionId":"RH-HOME"}
			var request:Dictionary={"kind":"module.plan","actor_id":"player","command_id":identity+":plan","target_id":identity,"payload":{"definition_id":"r34.module.fuel_woodshop","position":at,"quarter_turn":0,"source_id":"pack:player","tool_id":HAMMER}}
			var preview:Dictionary=runtime._services.modules.preview(request)
			if not preview.get("ok",false):tried[preview.get("code","unknown")]=int(tried.get(preview.get("code","unknown"),0))+1;continue
			for p:Dictionary in preview.ports:
				if p.purpose!="work":continue
				if runtime._services.actions.route("player",Geometry.location(runtime.actor("player")),p.location).get("ok",false):chosen={"request":request,"port":p.location};break
			if not chosen.is_empty():break
		if not chosen.is_empty():break
	check("original generated land has a different fully legal build position",not chosen.is_empty(),tried)
	if chosen.is_empty():return ""
	check("player really carries full cost to distinct new site",approach(runtime,chosen.port))
	var begun:Dictionary=send(runtime,"module.plan",identity,chosen.request.payload)
	check("new building reserves full20boards8scrap and original drive",begun.get("ok",false),begun)
	if not begun.get("ok",false):return ""
	step(runtime,100)
	var cold:Dictionary=cold_restore(runtime,"normal-relocation-new-build-ten-seconds")
	if not cold.get("ok",false):return ""
	runtime=cold.runtime;live=runtime
	check("real full-cost new construction completes after active cold",progress(runtime,500).finished and runtime._services.modules.instance(identity).status=="operational")
	return identity if runtime._services.modules.instance(identity).status=="operational" else ""
func relocate_actual()->void:
	var made:Dictionary=mount_actual(OS.get_cmdline_user_args()[1])
	if not made.get("ok",false):return finish()
	var r:RefCounted=made.runtime;live=r;frame_id="RH-HOME:woodshop-old-frame"
	check("alternate real pre-choice source still has one unique uninstalled drive",not frame(r).restoration.completed and r.actor("player").pack.get("r34:salvaged_drive_unit",0)==1 and frame(r).status=="damaged")
	var before_pack:Dictionary=r.actor("player").pack.duplicate(true)
	var dismantled:Dictionary=send(r,"module.dismantle",frame_id,{"source_id":"pack:player","output_id":"pack:player","tool_id":HAMMER})
	check("normal alternate choice starts original controlled frame dismantle",dismantled.get("ok",false),dismantled)
	if not dismantled.get("ok",false):return finish()
	check("actual old historical components return only6boards2scrap no second drive",progress(r,200).finished and frame(r).status=="dismantled" and r.actor("player").pack.timber==before_pack.timber+6 and r.actor("player").pack.scrap==before_pack.scrap+2 and r.actor("player").pack.get("r34:salvaged_drive_unit",0)==1)
	var cold:Dictionary=cold_restore(r,"normal-unrestored-frame-dismantled")
	if not cold.get("ok",false):return finish()
	r=cold.runtime;live=r
	if not transfer(r,"take",TOOLSTOCK,{"scrap":2},[SAW]):return finish()
	check("actual single remaining workshop2scrap exhausted for full price",r.actor("player").pack.scrap==8 and r.stock(TOOLSTOCK).items.scrap==0)
	check("normal source first tree truly harvested for extra building boards",harvest_three(r))
	if r.actor("player").pack.get("log",0)<3:return finish()
	if not approach(r,port(r,SHED,"work")):check("actual manual work port contact",false);return finish()
	for i:int in 2:
		if not recover_stamina(r):return finish()
		var crafted:Dictionary=send(r,"craft",SHED+":workbench",{"direct":false,"recipe_id":"saw_timber","source_id":"pack:player","output_id":"pack:player","tool_ids":[SAW]})
		check("original manual saw batch actually pays log and real saw wear "+str(i),crafted.get("ok",false) and progress(r,400).finished,crafted)
		if not crafted.get("ok",false):return finish()
	check("real salvage plus two paid hand batches supplies22boards8scrap unique drive",r.actor("player").pack.timber==22 and r.actor("player").pack.scrap==8 and r.actor("player").pack.log==1 and r.actor("player").pack["r34:salvaged_drive_unit"]==1 and absf(r.tool(SAW).durability-96)<0.000001)
	remember("original dismantle and real additional finite source handwork ready for full build")
	var identity:String=construct_relocated(r)
	if identity.is_empty():return finish()
	r=live
	check("actual full-cost new identity spends20boards8scrap and same drive while old remains retired",r.actor("player").pack.timber==2 and r.actor("player").pack.scrap==0 and r.actor("player").pack.get("r34:salvaged_drive_unit",0)==0 and frame(r).status=="dismantled" and Data.json_equal(r._services.modules.instance(identity).paid_cost,{"timber":20,"scrap":8,"r34:salvaged_drive_unit":1}))
	check("second original finite tree really supplies production feed",harvest_three(r))
	if r.actor("player").pack.get("log",0)<3:return finish()
	var machine:Dictionary=r._services.modules.instance(identity)
	for spec:Array in [["input",2],["fuel",1]]:
		var target:String=machine.stock_refs[spec[0]]
		if not contact(r,target):
			if not approach(r,r.world.extension(Gameplay.KEY).layout.home) or not contact(r,target):check("real new site feed contact",false,target);return finish()
		check("actual carried feed deposited to new identity "+str(spec[0]),send(r,"deposit",target,{"items":{"log":spec[1]}}).get("ok",false))
	var configure:Dictionary=send(r,"factory.configure",identity,{"recipe_id":"saw_timber","batches":2})
	check("actual full-price new machine configured",configure.get("ok",false),configure)
	if not configure.get("ok",false):return finish()
	for i:int in 600:
		step(r)
		if r.stock(machine.stock_refs.output).items.get("timber",0)==8:break
	check("normal alternate dismantle carry full-price rebuild really produces8boards",r.stock(machine.stock_refs.output).items.get("timber",0)==8 and frame(r).status=="dismantled" and r.actor("player").pack.log==1)
	remember("actual alternate full-cost new site two paid batches")
	cold=cold_restore(r,"normal-alternate-relocation-real-output")
	check("whole alternative normal economy full cold preserves unique drive lifecycle",cold.get("ok",false) and cold.runtime._services.modules.instance(frame_id).status=="dismantled" and cold.runtime.stock(machine.stock_refs.output).items.get("timber",0)==8 and violations.is_empty())
	finish()
func actual_consequences()->void:
	var source_root:String=OS.get_cmdline_user_args()[1].get_base_dir().get_base_dir().get_base_dir()
	for spec:Array in [["restore02/actual/story-normal-final.native.json",true,false],["relocate01/actual/story-normal-final.native.json",false,true],["restore02/actual/normal-frame-ready.native.json",false,false]]:
		var made:Dictionary=mount_actual(source_root+"/"+str(spec[0]))
		if not made.get("ok",false):return finish()
		var r:RefCounted=made.runtime;live=r;frame_id="RH-HOME:woodshop-old-frame"
		step(r)
		var g:Dictionary=r.world.extension(Gameplay.KEY);var flags:Dictionary=g.stories.ST01.flags
		check("actual taken original book plus completed study is read "+str(spec[0]),flags.get("read_woodwork_record",false) and r.world.extension("r3:production").knowledge.player.has("basic_woodwork"))
		check("restored fact remains distinct from player built "+str(spec[0]),bool(g.flags.get("real_machine_restored",false))==bool(spec[1]) and bool(g.flags.get("real_machine_built",false))==bool(spec[2]),g.flags)
		var q:Dictionary={}
		for row:Dictionary in r.facts().quests:
			if row.id=="R34-Q03":q=row
		check("Q03 recognizes only actually restored or new built plus real output "+str(spec[0]),bool(q.get("completed",false))==(bool(spec[1]) or bool(spec[2])),q)
		if spec[1]:check("S01 actual read projection explains original paid frame recovery",str(r._services.workforce.projection().stories.filter(func(t:Dictionary)->bool:return t.id=="ST01")[0].text).contains("原址旧框架已实际付料恢复"))
		var tx:=Tx.new(r._services.workforce.context)
		var record:Dictionary={}
		for row:Dictionary in r.world.extension("r3:production").records:
			if row.id==SHED+":record:book_woodwork":record=row
		var prior:Dictionary=r.capture_checkpoint()
		var policy:Variant=Gameplay
		if policy.has_method("_completed_woodwork_read"):
			check("uncompleted or teacher event cannot count as original book study",not policy._completed_woodwork_read(tx,g.stories,{"orderId":"not-a-real-completion","source_kind":"book"},record) and not policy._completed_woodwork_read(tx,g.stories,{"orderId":"not-a-real-completion","source_kind":"teacher"},record) and Data.json_equal(prior,r.capture_checkpoint()))
		remember("actual consequence "+str(spec[0]))
		FileAccess.open(output_dir+"/"+str(spec[1])+"-"+str(spec[2])+"-capture.json",FileAccess.WRITE).store_string(JSON.stringify(r.capture_checkpoint(),"\t",true,true))
		var cold:Dictionary=cold_restore(r,"actual-consequence-"+str(spec[1])+"-"+str(spec[2]))
		check("full canonical cold keeps actual corrected consequences "+str(spec[0]),cold.get("ok",false))
	finish()
func finish()->void:
	if live!=null:save(live,"story-normal-final")
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"commands":commands,"checkpoints":checkpoints,"sources":sources,"violations":violations,"fixed_steps":ticks,"frame_id":frame_id,"scope":"Immutable23 PCK real fresh content7 seed713 normal finite recovery route. No fixtures/capture edits/stock or body/position/knowledge changes. Fixed-step functional only, no OS/VA/long/fullS01/G5."},"\t",true,true));print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
