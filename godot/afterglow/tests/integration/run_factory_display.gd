extends SceneTree
## Synthetic lifecycle edge cases + real normal-source module damage,
## shared-command/persistence boundaries. Not normal-play/OS/VA acceptance.
const Display=preload("res://scripts/runtime/factory_display.gd")
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Factory=preload("res://scripts/world/factory_generator.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
class PublicAlerts extends RefCounted:
	var output:Dictionary={"available":true,"alerts":[{"key":"public:one","location":{"x":1}}],"private_unused":{"rows":[]}}
	func projection(_actor_id:String)->Dictionary:return output
class FastPublicAlerts extends PublicAlerts:
	var calls:int=0
	var complete_calls:int=0
	func alert_projection(_actor_id:String)->Dictionary:
		calls+=1;return output
	func factory_projection(_actor_id:String)->Dictionary:
		complete_calls+=1;return output
	func logistics_projection(_actor_id:String)->Dictionary:
		complete_calls+=1;return output
class KnownSites extends RefCounted:
	var sites:Array=[]
	func regional_projection(_actor_id:String)->Dictionary:return {"available":true,"sites":sites}
var checks:Array=[]
var output:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func sample(severity:String="warning",episode:String="")->Dictionary:
	return {"key":"fixture:module:missing_input","object_id":"fixture:module","reason_code":"missing_input","severity":severity,"location":{"x":1.0,"y":0.5,"z":2.0,"regionId":"RH-HOME"},"title":"真实原因的测试DTO","detail":"不生成任何生产事实","episode_id":episode}
func request(row:Dictionary,kind:String,id:String)->Dictionary:
	return {"kind":kind,"actor_id":"player","command_id":id,"target_id":row.id,"payload":{"key":row.key,"notification_token":row.notification_token,"seconds":60}}
func pure_checks()->void:
	var owner:=PublicAlerts.new()
	var rows:Array=Runtime._factory_alert_rows(owner,"projection","player")
	rows[0].location.x=9;rows.clear()
	check("alert-only read detaches provider nested rows",owner.output.alerts.size()==1 and owner.output.alerts[0].location.x==1)
	owner.output.alerts.append("malformed")
	check("alert-only read rejects malformed provider like generic facade",Runtime._factory_alert_rows(owner,"projection","player").is_empty())
	check("alert-only read never invents absent provider capabilities",Runtime._factory_alert_rows(null,"projection","player").is_empty() and Runtime._factory_alert_rows(owner,"missing","player").is_empty())
	var fast:=FastPublicAlerts.new();var reader:=Runtime.new()
	reader._facts={"actors":[{"id":"player"}]};reader._services={"production":fast}
	check("production alert selector uses one compact read for both owned domains",reader.factory_alert_sources().size()==1 and fast.calls==1 and fast.complete_calls==0)
	check("unknown actor never enters an alert provider",reader.factory_alert_sources("unknown").is_empty() and fast.calls==1)
	var sites:=KnownSites.new();reader._services={"workforce":sites};reader._work_revision=1;reader._work_targets=[]
	var point:Dictionary={"x":1.0,"y":0.5,"z":2.0,"regionId":"RH-VILLAGE","buildingId":null,"storeyId":null}
	sites.sites=[{"id":"site:known","surveyed":false,"defense_position":point}]
	check("cached work selector never exposes an unsurveyed regional guard",reader.work_targets().is_empty())
	sites.sites[0].surveyed=true
	var guard_rows:Array=reader.work_targets()
	check("surveyed regional guard enters existing cached selector without stock edits",guard_rows.size()==1 and guard_rows[0].job=="guard" and guard_rows[0].actual_target_id=="site:known")
	guard_rows[0].work_payload.position.x=9
	check("regional guard display is detached from owner locations",sites.sites[0].defense_position.x==1)
	var raw:Dictionary=sample();var empty:Dictionary=Display.initial()
	var pending:Dictionary=Display.reconcile(empty,[raw],1.0)
	check("normal warning waits for stable cause",pending.active.size()==1 and pending.active[0].pending and empty.active.is_empty())
	var short:Dictionary=Display.reconcile(pending,[],1.5)
	check("transient ordinary cause creates no history or toast",short.active.is_empty() and short.history.is_empty())
	var stable:Dictionary=Display.reconcile(pending,[raw],2.0)
	check("stable cause reuses episode without per-revision duplication",not stable.active[0].pending and stable.active[0].episode==pending.active[0].episode and stable.next_episode==2)
	stable.active[0].acknowledged=true;stable.active[0].ignored_until=80.0
	var quantity_change:Dictionary=raw.duplicate(true);quantity_change.detail="数量变化不重建episode"
	var retained:Dictionary=Display.reconcile(stable,[quantity_change],3.0)
	check("quantity or detail change preserves acknowledgement and ignore",retained.active[0].acknowledged and retained.active[0].ignored_until==80.0 and retained.active[0].episode==1)
	var urgent:Dictionary=raw.duplicate(true);urgent.severity="critical"
	var upgraded:Dictionary=Display.reconcile(retained,[urgent],3.1)
	check("severity escalation cancels ignore and creates one notification",not upgraded.active[0].pending and not upgraded.active[0].acknowledged and upgraded.active[0].ignored_until==0 and upgraded.active[0].notification==2 and upgraded.active[0].episode==1)
	var resolved:Dictionary=Display.reconcile(upgraded,[],4.0)
	check("only missing source resolves risk and preserves history",resolved.active.is_empty() and resolved.history.size()==1 and resolved.history[0].resolved and resolved.history[0].resolved_at==4.0)
	var again:Dictionary=Display.reconcile(resolved,[urgent],5.0)
	check("recurrence is new episode with old history intact",again.active[0].episode==2 and again.history.size()==1 and not again.active[0].acknowledged)
	var replacement:Dictionary=Display.reconcile(again,[sample("critical","next-real-event")],6.0)
	check("source event replacement immediately renews episode",replacement.active[0].episode==3 and replacement.history.size()==2)
	check("well formed lifecycle state validates",Display.validate(replacement).ok)
	var corrupt:Dictionary=replacement.duplicate(true);corrupt.active[0].ignored_until=NAN
	check("NaN and impossible duplicate identities cannot restore",not Display.validate(corrupt).ok)
	corrupt=replacement.duplicate(true);corrupt.history.append(corrupt.active[0].duplicate(true))
	check("duplicate active and historical IDs are rejected",not Display.validate(corrupt).ok)
	var tiles:Dictionary=Display.reconcile(empty,[],0.0,{"regionId":"RH-HOME","x":-0.1,"z":4.1})
	var duplicate:Dictionary=Display.reconcile(tiles,[],0.1,{"regionId":"RH-HOME","x":-1.0,"z":5.0})
	check("negative map coordinates use actual player tile once",tiles.explored_tiles[0].x==-1 and tiles.explored_tiles[0].z==1 and duplicate.explored_tiles.size()==1)
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	pure_checks()
	# This two-known-module fixture uses the pinned content1--8 family, not the current village opening.
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,Modules.generation_profiles_for_content(8),8))
	check("actual normal factory world assembles",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):return finish()
	var host:=Native.new();var built:Dictionary=host._assemble(prepared.capture);host.free()
	check("actual runtime mounts the display schema owner",built.get("ok",false) and built.get("services",{}).has("display"),built.get("reason"))
	if not built.get("ok",false):return finish()
	var runtime:RefCounted=built.runtime;var world:RefCounted=built.world
	var initial:Dictionary=runtime.capture_checkpoint();var view:Dictionary=runtime.factory_snapshot()
	var bodies:Array=runtime.actor_states()
	check("lightweight runtime scenario and bodies equal the canonical facts",runtime.scenario()==initial.facts.scenario and Data.json_equal(bodies,initial.facts.actors))
	bodies[0].pack.clear();bodies[0].x=999;bodies.clear()
	check("residency actor view cannot mutate nested authority or clock",Data.json_equal(initial,runtime.capture_checkpoint()))
	check("real compact providers preserve complete public alerts and authority",Data.json_equal(runtime.factory_alert_sources(),runtime.factory_snapshot("player",false).alerts) and Data.json_equal(initial,runtime.capture_checkpoint()))
	check("map query has no write or undiscovered-module disclosure",Data.json_equal(initial,runtime.capture_checkpoint()) and view.map.markers.filter(func(v:Dictionary)->bool:return v.kind=="module").size()==2 and view.map.markers.all(func(v:Dictionary)->bool:return v.kind!="hostile"))
	for i:int in 16:runtime.tick(0.1)
	check("real runtime stores explored tile without revealing whole regions",world.has_extension(Display.KEY) and runtime.factory_snapshot().map.explored_tiles.size()==1)
	var module:Dictionary=runtime.factory_snapshot().modules.instances[0]
	var damage:Dictionary=built.services.modules.prepare_damage(module.id,1.0,"r34:display-test:damage")
	var committed:Dictionary=runtime._commit(damage) if damage.get("ok",false) else damage
	check("real module damage uses original transaction and rule",committed.get("ok",false),committed)
	var rows:Array=runtime.factory_snapshot().alerts.filter(func(v:Dictionary)->bool:return v.object_id==module.id and v.reason_code=="damaged")
	check("actual urgent owner alert appears without normal debounce",rows.size()==1 and rows[0].severity=="danger",rows)
	if rows.is_empty():return finish()
	var row:Dictionary=rows[0];var facts:Dictionary=runtime.facts();var gameplay:Variant=world.extension("r34:gameplay");var production:Variant=world.extension("r34:production");var modules:Variant=world.extension("r34:modules")
	var stale:Dictionary=request(row,"alerts.acknowledge","display:stale");stale.payload.key="other:object:reason"
	var before:Dictionary=runtime.capture_checkpoint()
	check("stale or substituted alert cannot acknowledge another",runtime.command(stale).get("code")=="STALE_ALERT" and Data.json_equal(before,runtime.capture_checkpoint()))
	var ack:Dictionary=request(row,"alerts.acknowledge","display:ack")
	check("acknowledgement uses sole command path",runtime.command(ack).get("ok",false))
	var revision:int=runtime.get_revision()
	check("replayed read command is idempotent",runtime.command(ack).get("ok",false) and runtime.get_revision()==revision)
	row=runtime.factory_snapshot().alerts.filter(func(v:Dictionary)->bool:return v.object_id==module.id and v.reason_code=="damaged")[0]
	check("acknowledged damage remains present and unresolved",row.status=="acknowledged" and not row.resolved)
	check("temporary ignore is episode-limited actual read state",runtime.command(request(row,"alerts.ignore","display:ignore")).get("ok",false) and runtime.factory_snapshot().alerts.any(func(v:Dictionary)->bool:return v.id==row.id and v.status=="ignored"))
	check("read actions cannot repair, give items, advance clocks or alter jobs",Data.json_equal(facts,runtime.facts()) and Data.json_equal(gameplay,world.extension("r34:gameplay")) and Data.json_equal(production,world.extension("r34:production")) and Data.json_equal(modules,world.extension("r34:modules")))
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(encoded.text) if encoded.get("ok",false) else encoded
	host=Native.new();var restored:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded;host.free()
	check("cold native restore preserves same episode ignore and map memory",restored.get("ok",false) and restored.runtime.factory_snapshot().alerts.any(func(v:Dictionary)->bool:return v.id==row.id and v.status=="ignored") and restored.runtime.factory_snapshot().map.explored_tiles.size()==1,restored.get("reason"))
	var wrong:Dictionary=runtime.capture_checkpoint();wrong.world.extensions[Display.KEY].next_episode=0
	host=Native.new();var refused:Dictionary=host._assemble(wrong);host.free()
	check("malformed persisted display state rejects cold assembly",not refused.get("ok",false),refused.get("code"))
	var unsupported:Dictionary=request(row,"alerts.resolve","display:cannot-resolve")
	check("UI cannot resolve a real risk by command",runtime.command(unsupported).get("code")=="UNSUPPORTED")
	finish()
func finish()->void:
	var report:Dictionary={"scope":"pure lifecycle counterexamples and actual normal-source runtime/schema/commands/native restore; no GUI/OS/normal economy or package qualification","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));quit(1 if report.failed else 0)
