extends SceneTree
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
var checks:Array=[]
var hosts:Array=[]
var serial:int=0
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail.get("code") if detail is Dictionary else detail})
	if not ok:print("FAIL "+name+" "+str(detail))
func command(rt:RefCounted,kind:String,target:String="",payload:Dictionary={})->Dictionary:
	serial+=1;return rt.command({"kind":kind,"target_id":target,"payload":payload,"actor_id":"player","command_id":"B:project-test:"+str(serial)})
func mount(capture:Dictionary)->Dictionary:
	var host:=Native.new();hosts.append(host);return host._assemble(capture)
func run()->void:
	var profiles:Dictionary=Assembly.generation_profiles();var opening:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles));check("real opening",opening.ok,opening)
	if not opening.ok:finish();return
	var capture:Dictionary=opening.capture.duplicate(true);var state:Dictionary=capture.world.extensions[Modules.KEY]
	var home:Dictionary=state.instances.filter(func(v:Dictionary)->bool:return Modules.definition(v.definition_id).shape=="home" and v.region=="RH-HOME")[0]
	# Explicit fixture vacates a real graded pad; no terrain edits or user saves.
	for member:Dictionary in home.members:capture.world.entities.erase(member.id)
	state.instances.erase(home)
	for key:String in state.source_receipts.keys():
		if state.source_receipts[key].module_id==home.id:state.source_receipts.erase(key)
	capture.facts.stocks=capture.facts.stocks.filter(func(s:Dictionary)->bool:return s.get("module_id")!=home.id)
	var site:Dictionary=Modules.record_for({"id":"B:npc:warehouse","definition_id":"r34.module.warehouse","position":home.position,"region":home.region,"quarter_turn":0})
	var work:Dictionary=Shape.ports(site,Modules.definition(site.definition_id))[0].location
	var repair:Dictionary=Draft.find(Shape.ports(site,Modules.definition(site.definition_id)),"repair").location
	for a:Dictionary in capture.facts.actors:
		if a.id=="player":a.x=repair.x;a.y=repair.y;a.z=repair.z;a.regionId=repair.regionId;a.intent=null
		if a.id=="repair-resident":
			a.x=work.x;a.y=work.y;a.z=work.z-1.5;a.regionId=work.regionId;a.buildingId=null;a.storeyId=null;a.intent=null;a.householdId="home-residents";a.relationship.member=true;a.relationship.consent=true;a.relationship.home_arrived=true;a.job="rest";a.pack={"water":1};a.thirst=90;a.hunger=90;a.fatigue=0
	var supplies:Dictionary={"id":"B:project:supplies","location":work,"items":{"timber":14,"scrap":5,"r34:salvaged_drive_unit":1},"owner":"home-residents","searched":true};capture.facts.stocks.append(supplies)
	var legacy:Dictionary=capture.world.extensions["r3:production"];var hammer:Dictionary=legacy.tools.filter(func(t:Dictionary)->bool:return t.kind=="hammer")[0];hammer.holderId=supplies.id
	var mounted:=mount(capture);check("real site sources tool and remote worker restore",mounted.ok,mounted)
	if not mounted.ok:finish();return
	var rt:RefCounted=mounted.runtime;var services:Dictionary=mounted.services
	check("player creates real held construction project",command(rt,"module.plan",site.id,{"definition_id":site.definition_id,"position":home.position.merged({"regionId":home.region}),"quarter_turn":0,"source_id":supplies.id,"tool_id":hammer.id}).ok)
	var cid:String="module-project:"+site.id+":build"
	check("NPC cannot steal project from live player operator",services.actions.workforce_candidate("repair-resident",cid).get("reason")=="worker_occupied")
	check("player safe handoff pauses actual project without refund",rt._commit(services.actions.safe_handoff("player")).ok and rt.stock(supplies.id).items.timber==14)
	var candidate:Dictionary=services.actions.workforce_candidate("repair-resident",cid)
	check("NPC sees public valid physical construction candidate",candidate.get("valid",false),candidate)
	var during:Dictionary=services.actions.prepare_workforce({"actor_id":"repair-resident","candidate_id":cid,"command_id":"B:approach:cancel-check"})
	check("module claim uses real approach intent",during.ok and rt._commit(during).ok and rt.actor("repair-resident").intent.kind=="module_approach")
	var before_claim:Dictionary=services.modules.state().projects[0].duplicate(true)
	var cancel:Dictionary=rt.command({"actor_id":"repair-resident","command_id":"B:approach:cancel","kind":"cancel","target_id":"","payload":{}})
	var paused_project:Dictionary=services.modules.state().projects[0]
	check("cancelling approach releases live claim in same transaction and preserves actual project",cancel.ok and rt.actor("repair-resident").intent==null and paused_project.status=="paused" and paused_project.paused_reason=="safe_handoff" and paused_project.progress_seconds==before_claim.progress_seconds and rt.stock(supplies.id).items.timber==14,cancel)
	var walking:bool=false;var arrived:bool=false
	for i:int in 80:
		rt.tick(0.1)
		var intent:Variant=rt.actor("repair-resident").intent
		if intent is Dictionary and intent.owner=="actions" and intent.kind=="module_approach":walking=true
		if intent is Dictionary and intent.owner=="modules":arrived=true;break
	check("E chooses and B actually walks before unique module labor",walking and arrived,rt.actor("repair-resident"))
	var p:Dictionary=services.modules.state().projects[0]
	check("real worker reaches grounded port and preserves unspent cost",p.actor_id=="repair-resident" and float(p.progress_seconds)>0 and rt.stock(supplies.id).items.timber==14)
	# A genuine urgent-need mutation invokes E->B prepared handoff->A drink.
	var before:Dictionary=rt.actor("repair-resident");var after:Dictionary=before.duplicate(true);after.thirst=20
	rt._commit({"world_changes":[],"fact_changes":[{"collection":"actors","id":before.id,"before":before,"after":after}],"events":[{"kind":"inventory-transfer","actor_id":"player"}]})
	rt.tick(0.1)
	var caring:Dictionary=rt.actor("repair-resident")
	check("urgent life safely interrupts modules owner into same A drink",caring.intent is Dictionary and caring.intent.owner=="runtime" and caring.intent.kind=="drink",caring)
	var saved_progress:float=float(services.modules.state().projects[0].progress_seconds)
	for i:int in 10:rt.tick(0.1)
	check("self-care retains actual project progress and unconsumed materials",float(services.modules.state().projects[0].progress_seconds)==saved_progress and rt.stock(supplies.id).items.timber==14)
	var cold:=mount(rt.capture_checkpoint());check("paused construction and real A care cold restore",cold.ok,cold)
	if cold.ok:rt=cold.runtime;services=cold.services
	for i:int in 500:
		rt.tick(0.1)
		if services.modules.instance(site.id).status=="operational":break
	check("same NPC resumes site and completes actual shell once",services.modules.instance(site.id).status=="operational" and rt.stock(supplies.id).items.timber==2 and rt.stock(supplies.id).items.scrap==1)
	if services.modules.instance(site.id).status=="operational":
		var warehouse:Dictionary=services.modules.instance(site.id);var buffer:String=warehouse.stock_refs.storage
		# Owner-held direct transfer exercises the adopted per-instance total.
		var fixture:Dictionary=rt.capture_checkpoint();var player:=Draft.find(fixture.facts.actors,"player");player.x=work.x;player.y=work.y;player.z=work.z;player.intent=null;player.pack["r34:salvaged_drive_unit"]=2
		var capacity_mount:=mount(fixture);check("warehouse capacity fixture restores at real port",capacity_mount.ok,capacity_mount)
		if capacity_mount.ok:
			var cr:RefCounted=capacity_mount.runtime
			check("warehouse accepts adopted one real drive per instance",command(cr,"deposit",buffer,{"items":{"r34:salvaged_drive_unit":1}}).ok)
			check("full drive slot rejects second while retaining original pack",not command(cr,"deposit",buffer,{"items":{"r34:salvaged_drive_unit":1}}).ok and cr.stock(buffer).items.get("r34:salvaged_drive_unit")==1 and cr.actor("player").pack.get("r34:salvaged_drive_unit")==1)
			var reloaded:=mount(cr.capture_checkpoint());check("drive finite warehouse quantity cold restores without refilling",reloaded.ok and reloaded.runtime.stock(buffer).items.get("r34:salvaged_drive_unit")==1,reloaded)
	finish()
func finish()->void:
	var report:Dictionary={"ok":checks.all(func(c:Dictionary)->bool:return c.ok),"checks":checks,"scope":"actual E/B/A construction walk, same module labor, urgent life handoff, cold restore and finite drive capacity; explicit fixture pad/consent/supplies; not normal economy/OS/VA/package"}
	print(JSON.stringify(report))
	for host:Node in hosts:host.free()
	quit(0 if report.ok else 1)
