extends SceneTree
## Finite isolated placement/consent fixture; every pickup, stop, retarget,
## damage, route and delivery uses the actual A/B/E authority.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
var checks:Array=[]
var hosts:Array=[]
var sequence:int=0
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail.get("code") if detail is Dictionary else detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func command(rt:RefCounted,kind:String,target:String="",payload:Dictionary={})->Dictionary:
	sequence+=1
	return rt.command({"kind":kind,"actor_id":"player","command_id":"B:recover:"+str(sequence),"target_id":target,"payload":payload})
func mount(capture:Dictionary)->Dictionary:
	var host:=Native.new();hosts.append(host);return host._assemble(capture)
func task(rt:RefCounted)->Dictionary:return rt.world.extension("r34:logistics").tasks[0]
func carried(rt:RefCounted)->bool:
	for i:int in 100:
		rt.tick(0.1)
		if task(rt).phase=="deliver":return true
	return false
func deliver(rt:RefCounted)->void:
	for i:int in 200:
		rt.tick(0.1)
		if task(rt).status=="completed":return
func run()->void:
	var profiles:Dictionary=Assembly.generation_profiles();var opening:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("real C B E A opening",opening.ok,opening)
	if not opening.ok:finish();return
	var capture:Dictionary=opening.capture.duplicate(true);var state:Dictionary=capture.world.extensions[Modules.KEY]
	var workshop:Dictionary=state.instances.filter(func(v:Dictionary)->bool:return Modules.definition(v.definition_id).shape=="manual")[0]
	var work:Dictionary=Draft.find(Shape.ports(workshop,Modules.definition(workshop.definition_id)),"work").location
	var actor:=Draft.find(capture.facts.actors,"repair-resident");actor.x=work.x;actor.y=work.y;actor.z=work.z;actor.regionId=work.regionId;actor.buildingId=null;actor.storeyId=null;actor.intent=null;actor.pack={};actor.householdId="home-residents";actor.relationship.member=true;actor.relationship.consent=true;actor.relationship.home_arrived=true;actor.job="rest";actor.thirst=90;actor.hunger=90;actor.fatigue=0
	var source:=Draft.find(capture.facts.stocks,str(workshop.stock_refs.tools));source.searched=true
	# Both finite destinations use the same real graded apron. The second is a
	# salvage receiving crate, not a new source/reward or production shortcut.
	var receiving:Dictionary=work.duplicate(true);receiving.z-=1.0
	capture.facts.stocks.append({"id":"B:recovery:receiver","location":receiving,"items":{},"owner":"home-residents","searched":true})
	var to:String=workshop.stock_refs.input;Draft.find(capture.facts.stocks,to).searched=true
	var mounted:=mount(capture);check("finite fixture passes physical restore",mounted.ok,mounted)
	if not mounted.ok:finish();return
	var rt:RefCounted=mounted.runtime;var services:Dictionary=mounted.services
	var created:=command(rt,"logistics.create","",{"source_id":source.id,"destination_id":to,"items":{"timber":1}});check("real queue creates no cargo",created.ok,created)
	var id:String=task(rt).id
	check("pre-pickup cancellation clears order without taking goods",command(rt,"logistics.cancel",id).ok)
	for i:int in 30:rt.tick(0.1)
	check("cancelled queued task remains stopped under real E scheduling",task(rt).status=="cancelled" and float(rt.stock(source.id).items.timber)==8 and rt.actor(actor.id).pack.get("timber",0)==0)
	mounted=mount(capture);rt=mounted.runtime;services=mounted.services
	command(rt,"logistics.create","",{"source_id":source.id,"destination_id":to,"items":{"timber":1}});id=task(rt).id
	check("E B actual path picks up one real timber",carried(rt) and rt.actor(actor.id).pack.get("timber")==1)
	check("carried cancellation clears matching action and promises",command(rt,"logistics.cancel",id).ok and rt.actor(actor.id).intent==null and rt.world.extension("r34:logistics").reservations.is_empty())
	var candidate:Dictionary=services.actions.workforce_candidate(actor.id,id)
	check("explicit cancel candidate requires retarget",not candidate.valid and candidate.reason=="needs_retarget")
	var stopped_alerts:Array=services.production.logistics_projection().alerts
	check("carried cancellation exposes stable same-task alert and does not reveal unknown actor data",stopped_alerts.size()==1 and stopped_alerts[0].key==id+":cancelled" and stopped_alerts[0].episode_id==id and stopped_alerts==services.production.logistics_projection().alerts and services.production.logistics_projection("unknown-person").alerts.is_empty())
	for i:int in 30:rt.tick(0.1)
	check("N5 does not silently undo player cancellation",task(rt).status=="cargo_held" and rt.actor(actor.id).pack.get("timber")==1 and rt.stock(to).items.get("timber",0)==0)
	var stopped:Dictionary=rt.capture_checkpoint();var bad:=command(rt,"logistics.retarget",id,{"destination_id":"missing"})
	check("invalid retarget is atomic and retains cargo",not bad.ok and rt.actor(actor.id).pack.get("timber")==1 and task(rt).destination_id==to)
	check("explicit retarget only changes same destination reference",command(rt,"logistics.retarget",id,{"destination_id":"B:recovery:receiver"}).ok and task(rt).id==id and task(rt).source_id==source.id and rt.actor(actor.id).pack.get("timber")==1 and rt.stock("B:recovery:receiver").items.is_empty())
	deliver(rt)
	check("N5 resumes real route into replacement stock once",task(rt).status=="completed" and task(rt).trips==1 and rt.stock("B:recovery:receiver").items.get("timber")==1 and rt.actor(actor.id).pack.get("timber",0)==0)
	check("actual delivery resolves the real logistics alert",services.production.logistics_projection().alerts.is_empty())
	# Repeat with real source and destination destruction while already carrying.
	mounted=mount(capture);rt=mounted.runtime;services=mounted.services
	command(rt,"logistics.create","",{"source_id":source.id,"destination_id":to,"items":{"timber":1}});id=task(rt).id
	check("damage branch starts with actual carried timber",carried(rt))
	var before_tools:Array=services.production.state().tools.duplicate(true);var before_records:Array=services.production.state().records.duplicate(true)
	var damaged:Dictionary=rt._commit(services.modules.prepare_damage(workshop.id,1000,"B:logistics:destroy"))
	check("destroying both logistics endpoints commits without losing cargo",damaged.ok and rt.actor(actor.id).pack.get("timber")==1 and task(rt).status=="cargo_held" and rt.actor(actor.id).intent==null,damaged)
	var ruin:Dictionary=services.modules.instance(workshop.id)
	var legacy:Dictionary=services.production.state()
	check("damage retains tools books and unique identities at real ruin",legacy.tools.size()==before_tools.size() and legacy.records.size()==before_records.size() and legacy.tools.all(func(t:Dictionary)->bool:return not str(t.holderId).begins_with(workshop.id+":stock:")) and legacy.records.all(func(r:Dictionary)->bool:return not str(r.holderId).begins_with(workshop.id+":stock:")) and rt.stock(ruin.stock_refs.tools).items.timber==7)
	check("ruined endpoints expose explicit recovery reason",services.actions.workforce_candidate(actor.id,id).reason=="needs_retarget")
	check("destroyed endpoint and ruin alerts are visible immediately from committed facts",services.production.logistics_projection().alerts.any(func(row:Dictionary)->bool:return row.key==id+":target_ruined" and row.severity=="danger") and services.modules.projection().alerts.any(func(row:Dictionary)->bool:return row.key==workshop.id+":ruined" and row.episode_id==ruin.ruin_id and row.severity=="critical"))
	var cold:=mount(rt.capture_checkpoint());check("in-transit ruin task cold restores unchanged",cold.ok,cold)
	if cold.ok:
		rt=cold.runtime;services=cold.services
		check("retarget after lost origin permits same held physical task",command(rt,"logistics.retarget",id,{"destination_id":"B:recovery:receiver"}).ok and services.actions.workforce_candidate(actor.id,id).valid)
		deliver(rt)
		check("lost origin does not prevent true replacement delivery",task(rt).status=="completed" and task(rt).source_id==source.id and task(rt).trips==1 and rt.stock("B:recovery:receiver").items.get("timber")==1 and rt.actor(actor.id).pack.get("timber",0)==0)
		for i:int in 20:rt.tick(0.1)
		check("same task cannot deliver or refund cargo twice",rt.stock("B:recovery:receiver").items.get("timber")==1 and rt.stock(ruin.stock_refs.tools).items.timber==7)
	# Keep this snapshot referenced as explicit cancelled-state evidence.
	check("cancelled checkpoint never rewrites origin as a new pickup",stopped.world.extensions["r34:logistics"].tasks[0].phase=="deliver")
	finish()
func finish()->void:
	var report:Dictionary={"ok":checks.all(func(c:Dictionary)->bool:return c.ok),"checks":checks,"scope":"isolated finite fixtures, actual Runtime/E/B/C logistics cancellation/retarget/ruin/cold restore; not normal economy/OS/VA/package acceptance"}
	print(JSON.stringify(report))
	for host:Node in hosts:host.free()
	quit(0 if report.ok else 1)
