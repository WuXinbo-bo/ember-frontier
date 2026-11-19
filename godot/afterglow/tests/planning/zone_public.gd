extends SceneTree
## Actual zone commands/role queries/JSON restore. Job-admission negatives use
## explicit detached consenting-character fixtures, not a normal recruitment run.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var hosts:Array=[]
var runtimes:Array=[]
var output:String
var serial:int=0
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->bool:
	checks.append({"name":name,"ok":ok,"detail":detail.duplicate(true) if detail is Dictionary or detail is Array else detail})
	if not ok:print("FAIL "+name+" "+str(detail))
	return ok
func mount(capture:Dictionary)->Dictionary:
	var native:=Native.new();hosts.append(native)
	var result:Dictionary=native._assemble(capture)
	if result.get("ok",false):runtimes.append(result.runtime)
	return result
func command(rt:RefCounted,kind:String,target:String,payload:Dictionary={})->Dictionary:
	serial+=1
	return rt.command({"kind":kind,"actor_id":"player","target_id":target,"payload":payload,"command_id":"A:zone-public:"+str(serial)})
func target(rt:RefCounted)->Dictionary:
	for row:Dictionary in rt.work_targets():
		if row.id=="work:guard:A:patrol":return row
	return {}
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var profiles:Dictionary=Assembly.generation_profiles()
	var opening:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.get("profiles",[])))
	if not check("real new12 opening composes",opening.get("ok",false),opening.get("reason")):return finish()
	var built:Dictionary=mount(opening.capture)
	if not check("actual Native domains mount",built.get("ok",false),built.get("reason")):return finish()
	var rt:RefCounted=built.runtime;var a:Dictionary=rt.actor("player")
	var before:Dictionary=rt.capture_checkpoint()
	check("no invented patrol work target before designation",target(rt).is_empty())
	check("unknown housing reader is denied",not rt.housing_projection("unknown").available)
	var housing:Dictionary=rt.housing_projection()
	check("housing forwards actual B domain without a private UI table",Data.json_equal(housing,rt.domain_service("modules").housing_projection()))
	housing.homes.clear();housing.available=false
	check("returned housing DTO cannot mutate next query",rt.housing_projection().available)
	check("role and housing reads leave actual authority unchanged",Data.json_equal(before,rt.capture_checkpoint()))
	var spec:Dictionary={}
	for dz:int in [-8,0,8,16,24]:
		for dx:int in [-8,0,8,16,24]:
			var x:int=floori(float(a.x)*2)+dx;var z:int=floori(float(a.z)*2)+dz
			var probe:Dictionary={"kind":"patrol","region_id":a.regionId,"bounds":{"x0":x,"z0":z,"x1":x+3,"z1":z+3}}
			var preview:Dictionary=rt.zone_preview(probe)
			if preview.get("ok",false) and preview.cells.size()>=4:spec=probe;break
		if not spec.is_empty():break
	if not check("known actual terrain provides legal patrol cells",not spec.is_empty()):return finish()
	var made:Dictionary=command(rt,"zone.create","A:patrol",{"spec":spec})
	if not check("actual Runtime creates patrol designation",made.get("ok",false),made):return finish()
	var actual:Dictionary=target(rt)
	if not check("enabled designation exposes original B patrol role choice",not actual.is_empty(),rt.work_targets()):return finish()
	check("role anchor retains real zone identity and revision",actual.actual_target_id=="A:patrol" and actual.job=="guard" and actual.work_payload.zone_id=="A:patrol" and actual.work_payload.zone_revision==1)
	check("role query never changes actual player job",rt.actor("player").job==a.job)
	var fixture:Dictionary=rt.facts();var other:Dictionary={}
	for person:Dictionary in fixture.actors:
		if person.id!="player" and person.get("faction")!="infected":other=person;break
	if not check("original opening contains a real NPC identity for detached admission tests",not other.is_empty()):return finish()
	other.relationship.member=true;other.relationship.consent=true;other.relationship.home_arrived=true;other.regionId=a.regionId
	var request:Dictionary={"kind":"job","actor_id":"player","target_id":other.id,"command_id":"A:detached-job","payload":{"job":"guard","work_target_id":actual.id}}
	var read_basis:Dictionary=rt.capture_checkpoint()
	check("detached eligible role admission prepares without committing",rt.prepare_life(request,rt.actor("player"),fixture).get("ok",false))
	check("detached role admission leaves real NPC unmodified",Data.json_equal(read_basis,rt.capture_checkpoint()))
	other.regionId="not-current-region"
	check("role admission rejects NPC not physically in zone region",rt.prepare_life(request,rt.actor("player"),fixture).get("code")=="REGIONAL_JOB_UNAVAILABLE")
	other.regionId=a.regionId
	var policy:Dictionary=command(rt,"zone.policy","A:patrol",{"patch":{"policy":{"worker_ids":["player"]}}})
	check("actual policy can restrict patrol workers",policy.get("ok",false),policy)
	check("role submission rechecks live worker authorization",rt.prepare_life(request,rt.actor("player"),fixture).get("code")=="REGIONAL_JOB_PERMISSION")
	var encoded:Dictionary=Store.encode(rt.capture_checkpoint())
	var decoded:Dictionary=Store.decode(encoded.get("text",""))
	var restored:Dictionary=mount(decoded.get("capture",{})) if decoded.get("ok",false) else decoded
	check("actual Native JSON cold recovery retains current patrol target",restored.get("ok",false) and not target(restored.runtime).is_empty(),restored.get("reason"))
	check("cancel is an actual designation transaction",command(rt,"zone.cancel","A:patrol").get("ok",false))
	check("cached static work target list cannot resurrect cancelled patrol",target(rt).is_empty())
	check("stale role selection rejects after actual cancellation",not rt.prepare_life(request,rt.actor("player"),fixture).get("ok",false))
	if restored.get("ok",false):
		restored.runtime.retire()
		check("retired runtime never exposes a usable housing projection",not restored.runtime.housing_projection().available)
	finish()
func finish()->void:
	var failed:Array=checks.filter(func(c:Dictionary)->bool:return not c.ok)
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"ok":failed.is_empty(),"checks":checks,"failed":failed.size(),"scope":"Real planning/public API and Native JSON restore; detached consent fixtures only for job admission; no normal recruitment/patrol travel or OS/VA/FPS."},"\t"))
	for rt:RefCounted in runtimes:rt.retire()
	for native:Node in hosts:native.free()
	quit(0 if failed.is_empty() else 1)
