extends SceneTree
## 6.36 E consumer contract. Mounts a real finite checkpoint unchanged.
## Every scheduling variant is an ephemeral Draft + refusing B probe, NOT a
## natural zone journey, a production result or a population/need change.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Workforce=preload("res://scripts/runtime/settlement_workforce.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Data=preload("res://scripts/world/world_data.gd")
class ExecutorProbe extends RefCounted:
	var calls:Array=[]
	var rows:Array=[]
	var owner:String="actions"
	var published_jobs:Array=[]
	var reject_busy:bool=false
	var handoff_ok:bool=true
	var status:Dictionary={"active":true,"yieldable":false,"manual_paused":false}
	func workforce_status(actor_id:String,_facts:Dictionary={},_overrides:Dictionary={})->Dictionary:
		calls.append({"method":"status","actor_id":actor_id});return status.duplicate(true)
	func projection(_actor_id:String)->Dictionary:return {"available":true,"owner":owner,"jobs":published_jobs}
	func workforce_candidates(actor_id:String,facts:Dictionary={},overrides:Dictionary={})->Array:
		calls.append({"method":"candidates","actor_id":actor_id,"facts_token":facts.get("diagnostic_token"),"extension_token":overrides.get("diagnostic_token")})
		var result:Array=rows.filter(func(row:Dictionary)->bool:return actor_id=="*" or row.get("actor_id")==actor_id).duplicate(true)
		var actor:Dictionary=Draft.find(facts.get("actors",[]),actor_id)
		if reject_busy and actor.get("intent")!=null:
			for row:Dictionary in result:row.valid=false;row.reason="ACTOR_BUSY"
		return result
	func work_candidates(actor_id:String,facts:Dictionary={},overrides:Dictionary={})->Array:return workforce_candidates(actor_id,facts,overrides)
	func workforce_candidate(actor_id:String,id:String)->Dictionary:
		for row:Dictionary in workforce_candidates(actor_id):
			if row.id==id:return row
		return {}
	func safe_handoff(actor_id:String,candidate_id:String,facts:Dictionary,overrides:Dictionary)->Dictionary:
		var before:Dictionary=Draft.find(facts.actors,actor_id);var after:Dictionary=before.duplicate(true);after.intent=null
		calls.append({"method":"handoff","actor_id":actor_id,"candidate_id":candidate_id,"current_owner":before.get("intent",{}).get("owner","") if before.get("intent") is Dictionary else "","owner":owner})
		if not handoff_ok:return {"ok":false,"code":"PROBE_HANDOFF_DENIED","reason":"隔离安全交接拒绝"}
		return {"ok":true,"fact_changes":[{"collection":"actors","id":actor_id,"before":before.duplicate(true),"after":after}],"world_changes":[],"events":[]}
	func prepare_guard(request:Dictionary,_facts:Dictionary,_overrides:Dictionary)->Dictionary:
		calls.append({"method":"guard","request":request.duplicate(true)})
		return {"ok":false,"code":"PROBE_STOP","reason":"隔离guard消费者不移动或攻击"}
	func prepare_workforce(request:Dictionary,facts:Dictionary,overrides:Dictionary)->Dictionary:
		calls.append({"method":"prepare","request":request.duplicate(true),"current_intent":Draft.find(facts.actors,str(request.actor_id)).get("intent"),"facts_token":facts.get("diagnostic_token"),"extension_token":overrides.get("diagnostic_token"),"owner":owner})
		return {"ok":false,"code":"PROBE_STOP","reason":"消费者探针拒绝执行，不结算生产"}
	func count(method:String)->int:return calls.filter(func(row:Dictionary)->bool:return row.method==method).size()
class ResidentProbe extends RefCounted:
	var danger:bool=false
	var need:String=""
	var care_calls:Array=[]
	func factory_signals(a:Dictionary,_tx:RefCounted)->Dictionary:
		if not a.get("self_routine") is Dictionary:a.self_routine={"version":1}
		return {"danger":danger,"urgent_need":need,"guard_qualified":false}
	func teaching_target_reserved(_a:Dictionary,_tx:RefCounted)->bool:return false
	func prepare_factory_person(_tx:RefCounted,id:String,_dt:float,_now:float,_allow:bool,_layout:Dictionary)->Dictionary:
		care_calls.append(id);return {"ok":true}
	func prepare_factory_waiting(_tx:RefCounted,_id:String,_now:float)->bool:return false
var checks:Array=[]
var evidence:Array=[]
var output:String
var runtime:RefCounted
var actions:ExecutorProbe
var zones:ExecutorProbe
var residents:ResidentProbe
var workforce:RefCounted
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name)
func candidate(id:String,actor_id:String,priority:float=0)->Dictionary:
	return {"id":id,"actor_id":actor_id,"owner":"zonework" if id.begins_with("zonework:") else "actions","valid":true,"player_priority":priority,"wait_seconds":0,"route_cost":1}
func reset()->RefCounted:
	actions.calls.clear();zones.calls.clear();residents.care_calls.clear();actions.rows.clear();zones.rows.clear();residents.danger=false;residents.need=""
	zones.status={"active":true,"yieldable":false,"manual_paused":false}
	zones.reject_busy=false;zones.handoff_ok=true
	var tx:=Draft.new(workforce.context)
	for a:Dictionary in tx.staged.actors:
		# Only reset the scheduling deadline in this explicitly isolated Draft.
		# Original hp/needs/pack/location/consent stay exactly as captured.
		if a.id!="player":a.self_routine.next_decision=0
	tx.staged.diagnostic_token="current-facts";tx.extensions.diagnostic_token="current-overrides"
	return tx
func step(tx:RefCounted)->void:
	workforce._advance_survival(tx,residents,0.1,runtime.clock(),Workforce.initial())
	evidence.append({"actions":actions.calls.duplicate(true),"zonework":zones.calls.duplicate(true),"care":residents.care_calls.duplicate(true)})
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0]
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var native:=Native.new()
	var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	check("original finite cooperative checkpoint mounts",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime;var before:Dictionary=runtime.capture_checkpoint()
	actions=ExecutorProbe.new();zones=ExecutorProbe.new();zones.owner="zonework";residents=ResidentProbe.new();workforce=Workforce.new()
	workforce.configure({"runtime":runtime,"world":runtime.world,"spatial":built.services.actions.building,"services":{"actions":actions,"zonework":zones,"production":built.services.production,"residents":residents}})
	var tx:RefCounted=reset();zones.rows=[candidate("zonework:test:seed","village-resident")];step(tx)
	check("idle two original members query each provider once per actor",actions.count("candidates")==2 and zones.count("candidates")==2)
	check("automatic work releases current actions then requests only B zone executor",actions.count("handoff")==1 and actions.count("prepare")==0 and zones.count("prepare")==1 and zones.calls[-1].request.candidate_id=="zonework:test:seed")
	check("candidate queries borrow exact current facts and extension view",zones.calls.filter(func(row:Dictionary)->bool:return row.method=="candidates").all(func(row:Dictionary)->bool:return row.facts_token=="current-facts" and row.extension_token=="current-overrides"))
	check("E never supplies arbitrary zone cost duration or job materials",zones.calls[-1].request.keys().all(func(key:String)->bool:return key in ["actor_id","candidate_id","command_id"]))
	tx=reset();zones.rows=[candidate("zonework:test:stale","village-resident")];workforce._work_candidates("village-resident",tx.staged,tx.extensions);zones.rows=[candidate("zonework:test:fresh","village-resident")]
	var fresh:Array=workforce._work_candidates("village-resident",tx.staged,tx.extensions)
	check("no cross-query stale candidate cache",fresh.size()==1 and fresh[0].id=="zonework:test:fresh" and zones.count("candidates")==2)
	var copied:Dictionary=fresh[0];copied.id="mutated-return"
	check("zone provider DTO remains detached",zones.rows[0].id=="zonework:test:fresh")
	tx=reset();var supply:Dictionary=candidate("zone-supply:test:tool","village-resident",3)
	supply.merge({"owner":"actions","executor":"actions","kind":"supply","critical_supply":true,"source_id":"explicit-source","destination_id":"pack:village-resident","tool_ids":["explicit-tool"]},true);zones.rows=[supply]
	var supplied:Array=workforce._work_candidates("village-resident",tx.staged,tx.extensions)
	check("ZoneWork prerequisite offers retain original actions ownership",supplied.size()==1 and supplied[0].id==supply.id and supplied[0].owner=="actions")
	var looked_up:Dictionary=workforce._candidate("village-resident",str(supply.id))
	check("explicit supply lookup rechecks current ZoneWork offer",looked_up.get("id")==supply.id and looked_up.get("executor")=="actions")
	step(tx)
	check("N6 supply goes to sole actions executor instead of ZoneWork labor",actions.count("prepare")==1 and zones.count("prepare")==0 and actions.calls[-1].request.candidate_id==supply.id)
	check("supply consumer passes identity only rather than trusting a source cost or tool grant",actions.count("prepare")==1 and actions.calls[-1].request.keys().all(func(key:String)->bool:return key in ["actor_id","candidate_id","command_id"]))
	tx=reset();zones.rows=[supply.duplicate(true)];zones.rows[0].owner="zonework"
	check("spoofed supply owner is not admitted as an actions prerequisite",workforce._work_candidates("village-resident",tx.staged,tx.extensions).is_empty() and workforce._candidate("village-resident",str(supply.id)).is_empty())
	tx=reset();zones.rows=[supply.duplicate(true)];actions.rows=[supply.duplicate(true)]
	check("same supply offer exposed by both providers is ranked only once",workforce._work_candidates("village-resident",tx.staged,tx.extensions).size()==1)
	zones.rows.clear();actions.rows.clear()
	check("withdrawn current supply cannot be recovered from an E candidate cache",workforce._candidate("village-resident",str(supply.id)).is_empty())
	tx=reset();zones.rows=[candidate("zonework:test:visible","village-resident")]
	var listed:Array=workforce._work_candidates("*",tx.staged,tx.extensions)
	check("public all-member query uses exact real actor IDs rather than a global wildcard",zones.count("candidates")==3 and zones.calls.all(func(row:Dictionary)->bool:return row.actor_id in ["player","village-resident","repair-resident"]) and listed.size()==1)
	var published:Dictionary=workforce.projection("*");var person:Dictionary=Draft.find(published.people.map(func(row:Dictionary)->Dictionary:return row.merged({"id":row.actor_id})),"village-resident")
	check("UI receives actual per-member candidate and current cargo owner views",person.get("candidates",[]).size()==1 and person.candidates[0].id=="zonework:test:visible" and person.get("current_owner")=="" and person.get("pending_delivery")=={} and person.get("suspended_work")=={})
	person.candidates.clear()
	check("public member DTO edits cannot change provider candidate or actual source",zones.rows.size()==1 and zones.rows[0].id=="zonework:test:visible" and Data.json_equal(before,runtime.capture_checkpoint()))
	zones.published_jobs=[{"id":"explicit-projection-fixture","status":"suspended","elapsed":3.2,"paused_reason":"need"}]
	var jobs:Dictionary=workforce._zone_projection("village-resident")
	check("B suspended work DTO is transparently exposed without a second progress owner",jobs.owner=="zonework" and jobs.jobs==zones.published_jobs)
	jobs.jobs[0].elapsed=99
	check("suspended job DTO is detached from B provider",zones.published_jobs[0].elapsed==3.2)
	tx=reset();tx.actor("village-resident").intent={"owner":"zonework","id":"explicit-isolated-active","kind":"zonework"};step(tx)
	check("active zone labor remains stable and is never reranked",zones.calls.filter(func(row:Dictionary)->bool:return row.method=="candidates" and row.actor_id=="village-resident").is_empty() and zones.count("handoff")==0 and tx.actor("village-resident").intent.id=="explicit-isolated-active")
	for need:String in ["drink","eat","rest","bed"]:
		tx=reset();residents.need=need;tx.actor("repair-resident").intent={"owner":"zonework","id":"explicit-isolated-active","kind":"zonework"};step(tx)
		check("N2 "+need+" does not recompute any work candidate",actions.count("candidates")==0 and zones.count("candidates")==0)
		check("N2 "+need+" pauses through current zone owner before self care",zones.count("handoff")==1 and actions.count("handoff")==0 and residents.care_calls==["repair-resident"] and tx.actor("repair-resident").intent==null)
	tx=reset();residents.danger=true;residents.need="drink";tx.actor("repair-resident").intent={"owner":"zonework","id":"explicit-isolated-active","kind":"zonework"};step(tx)
	check("N1 threat wins over need with zero work enumeration",zones.count("candidates")==0 and zones.count("handoff")==1 and tx.actor("repair-resident").self_routine.factory_decision.priority=="N1")
	tx=reset();zones.rows=[candidate("zonework:test:blocked","village-resident",100)];zones.rows[0].valid=false;actions.rows=[candidate("logistics:test:ready","village-resident")];step(tx)
	check("waiting invalid zone supply does not tie up a worker from eligible logistics",actions.count("prepare")==1 and zones.count("prepare")==0 and actions.calls[-1].request.candidate_id=="logistics:test:ready")
	tx=reset();zones.status.yieldable=true;tx.actor("repair-resident").intent={"owner":"zonework","id":"explicit-isolated-blocked","kind":"zonework"};actions.rows=[candidate("logistics:test:compatible","repair-resident")];step(tx)
	check("only B-proved blocked labor can yield to compatible available work",zones.count("status")==1 and zones.count("handoff")==2 and actions.count("prepare")==1 and actions.calls[-1].request.candidate_id=="logistics:test:compatible" and actions.calls[-1].current_intent==null)
	check("failed replacement admission retains original blocked work rather than committing a pause",tx.actor("repair-resident").intent.id=="explicit-isolated-blocked")
	tx=reset();zones.status.yieldable=true;zones.status.manual_paused=true;tx.actor("repair-resident").intent={"owner":"zonework","id":"explicit-isolated-manual-pause","kind":"zonework"};actions.rows=[candidate("logistics:test:compatible","repair-resident")];step(tx)
	check("manual pause never triggers automatic replacement or resume",zones.count("handoff")==0 and actions.count("prepare")==0 and zones.calls.filter(func(row:Dictionary)->bool:return row.method=="candidates" and row.actor_id=="repair-resident").is_empty() and tx.actor("repair-resident").intent.id=="explicit-isolated-manual-pause")
	tx=reset();zones.status.yieldable=true;zones.reject_busy=true;tx.actor("repair-resident").intent={"owner":"zonework","id":"explicit-isolated-busy-rule","kind":"zonework"};zones.rows=[candidate("zonework:test:alternative","repair-resident")];step(tx)
	check("B ACTOR_BUSY candidates are queried only after a real prepared handoff observation",zones.count("prepare")==1 and zones.calls[-1].request.candidate_id=="zonework:test:alternative" and zones.calls[-1].current_intent==null)
	check("refused alternative does not commit the observational handoff or lose blocked intent",tx.actor("repair-resident").intent.id=="explicit-isolated-busy-rule")
	tx=reset();zones.status.yieldable=true;zones.reject_busy=true;zones.handoff_ok=false;tx.actor("repair-resident").intent={"owner":"zonework","id":"explicit-isolated-denied-handoff","kind":"zonework"};zones.rows=[candidate("zonework:test:alternative","repair-resident")];step(tx)
	check("denied observation handoff never invents an idle actor or requests replacement",zones.count("prepare")==0 and tx.actor("repair-resident").intent.id=="explicit-isolated-denied-handoff")
	tx=reset();var patrol:Dictionary=candidate("regional-guard:explicit-zone","repair-resident");patrol.merge({"kind":"guard","operation":"patrol","site_id":"explicit-zone","position":{"regionId":"RH-HOME","x":10.0,"y":0.5,"z":25.0}},true);actions.rows=[patrol];step(tx)
	check("ordinary patrol stays N6 and uses B original prepare_guard with exact provider point",actions.count("guard")==1 and actions.count("prepare")==0 and actions.calls[-1].request.site_id==patrol.site_id and actions.calls[-1].request.position==patrol.position and tx.actor("repair-resident").self_routine.factory_decision.priority=="N6")
	tx=reset();tx.actor("village-resident").relationship.consent=false;step(tx)
	check("withdrawn member never enumerates a new zone job",zones.calls.filter(func(row:Dictionary)->bool:return row.method=="candidates" and row.actor_id=="village-resident").is_empty())
	tx=reset();tx.actor("village-resident").intent={"owner":"zonework","id":"isolated-active","kind":"zonework"}
	var handoff:Dictionary=workforce._safe_handoff("village-resident","logistics:test:ready",tx.staged,tx.extensions)
	check("zone-to-logistics handoff uses current owner regardless of target prefix",handoff.ok and zones.count("handoff")==1 and actions.count("handoff")==0)
	var absent:=Workforce.new();absent.configure({"runtime":runtime,"world":runtime.world,"spatial":built.services.actions.building,"services":{"actions":actions,"production":built.services.production,"residents":residents}})
	check("missing zone executor fails explicitly without falling back to another executor",not absent._prepare_work({"actor_id":"village-resident","candidate_id":"zonework:missing"},tx.staged,tx.extensions).ok)
	var calls_before:int=actions.count("handoff")
	check("missing current zone owner cannot fall through to actions handoff",not absent._safe_handoff("village-resident","",tx.staged,tx.extensions).ok and actions.count("handoff")==calls_before)
	check("all actual people facts materials tools clock and world remain unchanged",Data.json_equal(before,runtime.capture_checkpoint()))
	finish()
func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"observations":evidence,"scope":"6.36 E consumer only. Real finite checkpoint mounted unchanged; all intent/deadline/withdrawal/availability/signal variants ephemeral and explicit; B probes refuse execution. No production/natural journey/OS/VA/FPS qualification."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
