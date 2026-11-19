extends SceneTree
## Finite, explicitly isolated prerequisite fixtures against the real Native
## services. Not evidence of a naturally played NPC farming/logistics journey.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Supply=preload("res://scripts/planning/zone_work_supply.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var host:Node
var rt:RefCounted
var zonework:RefCounted
var base_facts:Dictionary
var base_p:Dictionary
var zone:Dictionary
var job:Dictionary
var req:Dictionary
var output:String
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail.duplicate(true) if detail is Dictionary or detail is Array else detail})
	if not ok:print("FAIL "+name+" "+str(detail))
func draft()->RefCounted:
	var tx:=Draft.new(zonework.context)
	tx.staged=base_facts.duplicate(true)
	tx.extensions["r3:production"]=base_p.duplicate(true)
	tx.extensions["r34:modules"]=rt.world.extension("r34:modules")
	tx.extensions["r34:modules"].instances=[]
	return tx
func rows(tx:RefCounted,requirements:Dictionary=req,design:Dictionary=zone,target:Dictionary=job)->Array:
	return Supply.candidates(zonework,tx,tx.actor("player"),design,target,requirements)
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var profiles:Dictionary=Assembly.generation_profiles()
	var opening:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.get("profiles",[])))
	check("real new12 opening composes",opening.get("ok",false),opening.get("reason"))
	if not opening.get("ok",false):return finish()
	host=Native.new()
	var built:Dictionary=host._assemble(opening.capture)
	check("shipping Native services mount",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	rt=built.runtime;zonework=rt.domain_service("zonework")
	var before:Dictionary=rt.capture_checkpoint()
	base_facts=rt.facts();base_p=rt.world.extension("r3:production")
	var a:Dictionary=Draft.find(base_facts.actors,"player");a.pack={};a.intent=null
	var at:Dictionary={"regionId":a.regionId,"x":a.x,"y":a.y,"z":a.z,"buildingId":null,"storeyId":null}
	base_facts.stocks=[{"id":"A:finite-supply","owner":"home-residents","searched":true,"location":at,"items":{"r34:potato_seed":2,"r34:water_bucket":1}}]
	base_p.tools=[{"id":"A:finite-axe","holderId":"A:finite-supply","kind":"salvaged_axe","durability":50}];base_p.orders=[]
	zone={"id":"A:supply-zone","revision":1,"region_id":a.regionId,"enabled":true,"kind":"farm","policy":{"priority":4}}
	job={"id":"A:finite-job","kind":"sow","location":at,"work_id":"A:work","zone_id":zone.id}
	req={"cost":{"r34:potato_seed":2},"reusable":{"r34:water_bucket":1},"tool_quality":{"chopping":1},"location":at,"target":at}
	var tx:RefCounted=draft();var result:Array=rows(tx)
	check("one source offers only finite exact materials and actual tool",result.size()==1 and Data.json_equal(result[0].items,req.cost.merged(req.reusable)) and result[0].tool_ids==["A:finite-axe"],result)
	if result.is_empty():return finish()
	check("DTO routes execution to original actions with stable zone identity",result[0].valid and result[0].owner=="actions" and result[0].executor=="actions" and result[0].kind=="supply" and result[0].destination_id=="pack:player" and result[0].zone_revision==1 and result[0].critical_supply and not result[0].carrying)
	check("repeated reads retain IDs and amounts",Data.json_equal(result,rows(draft())))
	var summary:Dictionary=result[0]
	check("public source location and fallback label describe the already admitted source",summary.source_name=="A:finite-supply" and Data.json_equal(summary.source_location,at))
	check("selected tool summary retains actual identity and original owner definition",summary.tools.size()==1 and summary.tools[0].id=="A:finite-axe" and summary.tools[0].kind=="salvaged_axe" and summary.tools[0].durability==50 and summary.tools[0].name==rt.domain_service("production").tool_definition(base_p.tools[0]).name)
	summary.source_location.x=999;summary.tools[0].qualities.chopping=999
	check("public metadata is detached from source coordinates and tool qualities",Data.json_equal(rows(draft())[0].source_location,at) and rows(draft())[0].tools[0].qualities.chopping!=999)
	tx=draft();tx.staged.stocks[0].name="已搜索工具架"
	check("public source uses the actual searched container label",rows(tx)[0].source_name=="已搜索工具架")
	result[0].items["r34:potato_seed"]=900;result[0].tool_ids.clear()
	check("DTO mutation cannot alter future candidates or authority",rows(draft())[0].items["r34:potato_seed"]==2 and rows(draft())[0].tool_ids.size()==1)
	tx=draft();tx.actor("player").pack["r34:potato_seed"]=1
	check("actor already holding one seed only fetches the actual gap",rows(tx)[0].items["r34:potato_seed"]==1)
	tx=draft();tx.actor("player").pack=req.cost.merged(req.reusable);tx.extensions["r3:production"].tools[0].holderId="pack:player"
	check("fully supplied actor does not fetch duplicate inputs or tools",rows(tx).is_empty())
	var reusable:Dictionary={"cost":{"r34:water_bucket":1},"reusable":{"r34:water_bucket":1},"tool_quality":{}}
	check("reusable possession is not an additional material charge",rows(draft(),reusable)[0].items["r34:water_bucket"]==1)
	for change:Dictionary in [{"searched":false},{"owner":"private-owner"},{"location":at.merged({"regionId":"unknown-region"},true)},{"id":"pack:another-actor"}]:
		tx=draft();tx.staged.stocks[0].merge(change,true)
		check("ineligible source is not disclosed "+str(change.keys()[0]),rows(tx).is_empty())
	for state:Dictionary in [{"discovered":false,"status":"operational"},{"discovered":true,"status":"ruined"},{"discovered":true,"status":"operational","owner":"private-owner"}]:
		tx=draft();var module:Dictionary={"id":"A:hidden-module","definition_id":rt.world.extension("r34:modules").instances[0].definition_id,"owner":"home-residents","stock_refs":{"storage":"A:finite-supply"},"config":{}}
		module.merge(state,true);tx.extensions["r34:modules"].instances=[module]
		check("module stock_refs guard works without trusting stock.module_id "+str(state),rows(tx).is_empty())
	tx=draft();tx.staged.stocks[0].module_id="A:missing-module"
	check("orphan explicit module source is hidden",rows(tx).is_empty())
	tx=draft();tx.staged.stocks[0].items={};tx.extensions["r3:production"].tools[0].durability=0
	check("empty source and broken tool cannot produce a supply",rows(tx).is_empty())
	tx=draft();tx.staged.stocks[0].items["r34:potato_seed"]=1
	check("partial source never promises absent inventory",rows(tx)[0].items["r34:potato_seed"]==1)
	tx=draft();tx.actor("player").intent={"owner":"runtime","kind":"rest"}
	check("busy actor remains blocked pending safe handoff",not rows(tx)[0].valid)
	tx=draft();tx.extensions["r34:modules"].instances=[{"id":"A:reserved-module","definition_id":rt.world.extension("r34:modules").instances[0].definition_id,"owner":"home-residents","discovered":true,"status":"operational","stock_refs":{"storage":"A:finite-supply"},"config":{"stock_policies":{"storage":{"filter":[],"reserve":{"r34:potato_seed":2},"target":{}}}}}]
	check("production reserve floor is respected",not rows(tx)[0].items.has("r34:potato_seed"))
	tx=draft();tx.staged.stocks[0].items={"soil_m3":.125}
	check("terrain supply retains exact real eighth-cubic-metre gap",rows(tx,{"cost":{"soil_m3":.125},"tool_quality":{}})[0].items=={"soil_m3":.125})
	check("cancelled zone gives no supplies",rows(draft(),req,zone.merged({"enabled":false},true)).is_empty())
	check("worker filter denies unassigned player",rows(draft(),req,zone.merged({"policy":{"worker_ids":["other"]}},true)).is_empty())
	check("job from a different region cannot borrow zone authority",rows(draft(),req,zone,job.merged({"location":at.merged({"regionId":"other"},true)},true)).is_empty())
	check("source policy constrains materials but permits real tools",rows(draft(),req,zone.merged({"policy":{"source_stock_id":"other"}},true))[0].items.is_empty())
	for invalid:Dictionary in [{"cost":{"r34:potato_seed":.5}},{"cost":{"r34:potato_seed":-1}},{"reusable":{"r34:water_bucket":INF}},{"tool_quality":{"chopping":NAN}},{"cost":{"not-a-real-item":1}}]:
		check("invalid requirement fails closed "+str(invalid),rows(draft(),invalid).is_empty())
	var next_zone:Dictionary=zone.duplicate(true);next_zone.revision=2
	check("zone revision produces a new stable candidate identity",rows(draft())[0].id!=rows(draft(),req,next_zone)[0].id)
	tx=draft();tx.extensions["r3:production"].orders=[{"id":"A:other-work","actorId":"player","kind":"craft","status":"active","targetId":"missing-no-material-cost","sourceId":"A:finite-supply","outputId":"pack:player","stationId":null,"toolIds":["A:finite-axe"]}]
	check("tool held by another actual production order is not offered",rows(tx)[0].tool_ids.is_empty())
	var stranger:Dictionary=tx.actor("player").duplicate(true);stranger.id="non-consenting-npc";stranger.relationship={"member":true,"consent":false}
	check("nonconsenting NPC cannot obtain offers",Supply.candidates(zonework,draft(),stranger,zone,job,req).is_empty())
	check("real authority and clock are unchanged by all fixture queries",Data.json_equal(before,rt.capture_checkpoint()))
	check("missing actor cannot query source offers",Supply.candidates(zonework,draft(),{},zone,job,req).is_empty())
	finish()
func finish()->void:
	var failed:Array=checks.filter(func(c:Dictionary)->bool:return not c.ok)
	var report:Dictionary={"ok":failed.is_empty(),"checks":checks,"failed":failed.size(),"scope":"Finite detached fixture queries through real Native services only; no actual NPC transfer/journey, renderer, OS or performance qualification."}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	if rt!=null:rt.retire()
	if host!=null:host.free()
	quit(0 if failed.is_empty() else 1)
