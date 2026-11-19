extends SceneTree
## Real file/rename/codec fault matrix under the supplied isolated directory.
const Store=preload("res://scripts/storage/native_store.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const World=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
var checks:Array=[]
var output:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func write(path:String,text:String)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f:=FileAccess.open(path,FileAccess.WRITE);f.store_string(text);f.close()
func capture(seed:int)->Dictionary:
	var w:=World.new();w.load_snapshot(Rural.generate(seed))
	var at:Dictionary={"x":29.2,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var a:Dictionary=Initial.actor("player","fixture",at,at,{"food":2,"water":2})
	var r:=Runtime.new();r.configure({"world":w,"facts":{"actors":[a],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":{}})
	return r.capture_checkpoint()
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var value:Dictionary=capture(713);value.source.note="quoted \" slash \\ unicode 农村"
	var encoded:Dictionary=Store.encode(value)
	check("real full envelope encodes with inner and outer bytes",encoded.ok and encoded.envelope_bytes>encoded.payload_bytes)
	var measured:Dictionary=JSON.parse_string(encoded.text)
	check("inner measurement uses actual UTF-8 payload bytes",measured.payload.to_utf8_buffer().size()==encoded.payload_bytes)
	# Each encode has a new timestamp-containing checkpoint ID, including in
	# the inner world envelope. Its fractional decimal length can vary; these
	# separate calls cannot claim an exact one-byte boundary. Keep a 32-byte
	# margin, and verify the actual first payload's byte measurement above.
	check("inner explicitly sufficient byte budget accepted",Store.encode(value,encoded.payload_bytes+32).ok)
	check("inner explicitly insufficient byte budget rejected",Store.encode(value,encoded.payload_bytes-32).get("code")=="SAVE_TOO_LARGE")
	# Outer budget is independently enforced with a fixed small limit.
	check("outer limit enforced independently",Store.encode(value,Store.LIMIT,64).get("code")=="SAVE_TOO_LARGE")
	var altered:Dictionary=JSON.parse_string(encoded.text);var payload:Dictionary=JSON.parse_string(altered.payload)
	payload.simulation={"remainder":-0.1};altered.payload=JSON.stringify(payload);altered.sha256=altered.payload.sha256_text()
	check("signed but bad simulation state is rejected before mount",Store.decode(JSON.stringify(altered)).get("code")=="INVALID_SIMULATION_STATE")
	var store:=Store.new(output+"/slots")
	check("empty root is honestly no save",store.load_current().code=="NO_SAVE")
	write(store.root+"/aaaaaaaa/a.json",encoded.text)
	var bytes:String=FileAccess.get_file_as_string(store.root+"/aaaaaaaa/a.json")
	var missing:Dictionary=store.load_current()
	check("missing active discovers valid namespace without activating",missing.code=="RECOVERY_CHOICE_REQUIRED" and missing.candidates.size()==1 and not FileAccess.file_exists(store.root+"/active.json"),missing.get("code"))
	check("candidate exposes identity hash and full-assembly requirement",missing.candidates[0].world_id==value.world.worldId and missing.candidates[0].requires_assembly_validation and missing.candidates[0].sha256==bytes.sha256_text())
	var c:Dictionary=missing.candidates[0]
	var loaded:Dictionary=store.load_recovery_candidate(c.candidate_id,c.sha256)
	check("explicit load alone does not activate",loaded.ok and not FileAccess.file_exists(store.root+"/active.json"))
	check("path traversal candidate refused",store.load_recovery_candidate("../a",c.sha256).code=="INVALID_CANDIDATE")
	check("wrong digest is stale candidate not world replacement",store.load_recovery_candidate(c.candidate_id,"0".repeat(64)).code=="STALE_CANDIDATE")
	var activated:Dictionary=store.activate_saved(loaded.activation)
	check("validated explicit choice promotes atomic pointer",activated.ok and store.load_current().ok)
	var original_pointer:String=FileAccess.get_file_as_string(store.root+"/active.json")
	write(store.root+"/active.json","{truncated")
	check("truncated active enters explicit recovery",store.load_current().code=="RECOVERY_CHOICE_REQUIRED")
	check("discovery preserves bad active and original slot bytes",FileAccess.get_file_as_string(store.root+"/active.json")=="{truncated" and FileAccess.get_file_as_string(store.root+"/aaaaaaaa/a.json")==bytes)
	write(store.root+"/active.json",JSON.stringify({"namespace":"../outside","slot":"a"}))
	check("unsafe active metadata cannot escape root",store.load_current().code=="RECOVERY_CHOICE_REQUIRED")
	write(store.root+"/active.json",original_pointer)
	write(store.root+"/aaaaaaaa/b.json","{bad-slot")
	var fallback_meta:Dictionary=JSON.parse_string(original_pointer);fallback_meta.slot="b"
	write(store.root+"/active.json",JSON.stringify(fallback_meta))
	var fallback:Dictionary=store.load_current()
	check("same-world alternate slot retains automatic fallback",fallback.ok and fallback.recovered and fallback.capture.world.worldId==value.world.worldId)
	var alternate:Dictionary=Store.encode(capture(2026));write(store.root+"/bbbbbbbb/a.json",alternate.text)
	write(store.root+"/aaaaaaaa/a.json","{bad-both")
	var both:Dictionary=store.load_current()
	check("two damaged current slots require choice before another world",both.code=="RECOVERY_CHOICE_REQUIRED" and both.candidates.size()==1 and both.candidates[0].world_id!=value.world.worldId)
	check("cross-world discovery never silently repairs active",FileAccess.get_file_as_string(store.root+"/active.json")==JSON.stringify(fallback_meta))
	var filtered:Dictionary=store.list_recovery_candidates(value.world.worldId)
	check("world-filter cannot return another world's candidate",filtered.ok and filtered.candidates.is_empty())
	var selected:Dictionary=both.candidates[0]
	var to_promote:Dictionary=store.load_recovery_candidate(selected.candidate_id,selected.sha256)
	write(store.root+"/active.json",original_pointer)
	check("active CAS prevents racing explicit recovery",store.activate_saved(to_promote.activation).code=="STALE_ACTIVE" and FileAccess.get_file_as_string(store.root+"/active.json")==original_pointer)
	to_promote=store.load_recovery_candidate(selected.candidate_id,selected.sha256)
	write(store.root+"/bbbbbbbb/a.json",alternate.text+" ")
	check("slot CAS rechecks content after offline assembly",store.activate_saved(to_promote.activation).code=="INVALID_CANDIDATE" and FileAccess.get_file_as_string(store.root+"/active.json")==original_pointer)
	var orphan:=Store.new(output+"/orphan")
	write(orphan.root+"/cccccccc/a.json.tmp",encoded.text)
	check("orphan temporary file is never a recovery candidate",orphan.load_current().code=="NO_SAVE" and orphan.list_recovery_candidates().candidates.is_empty())
	write(orphan.root+"/cccccccc/a.json","{bad")
	check("only bad slots are corruption not a fresh world",orphan.load_current().code=="INVALID_CHECKPOINT")
	var limited:=Store.new(output+"/limited")
	for i:int in Store.RECOVERY_NAMESPACES+1:DirAccess.make_dir_recursive_absolute(limited.root+"/%08x"%i)
	check("bounded scan discloses truncation and never says no save",limited.list_recovery_candidates().scan.truncated and limited.load_current().code=="RECOVERY_SCAN_LIMIT")
	check("recovery never rewrites historical source slots",FileAccess.get_file_as_string(store.root+"/aaaaaaaa/a.json")=="{bad-both" and FileAccess.get_file_as_string(orphan.root+"/cccccccc/a.json.tmp")==encoded.text)
	finish()
func finish()->void:
	var report:Dictionary={"scope":"source/headless real FileAccess/codec/SHA/atomic rename fault fixtures; no user save or OS qualification","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var f:=FileAccess.open(output+"/results.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close();print(JSON.stringify(report));quit(1 if report.failed else 0)
