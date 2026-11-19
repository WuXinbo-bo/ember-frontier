extends SceneTree
## Definition/purity checks on actual new12; exact C finite four-cycle save for
## a real walk/craft consumer. No added materials, movement or tool identities.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Rules=preload("res://scripts/ecology/ecology_rules.gd")
var checks:Array=[]
var hosts:Array=[]
var runtimes:Array=[]
var output:String
var serial:int=0
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->bool:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name+" "+str(detail))
	return ok
func entry(book:Dictionary,id:String)->Dictionary:
	for row:Dictionary in book.entries:
		if row.id==id:return row
	return {}
func mount(capture:Dictionary)->Dictionary:
	var host:=Native.new();hosts.append(host);var built:Dictionary=host._assemble(capture)
	if built.get("ok",false):runtimes.append(built.runtime)
	return built
func send(rt:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	serial+=1
	return rt.command({"command_id":"A:regional-book:"+str(serial),"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination})
func idle(rt:RefCounted,limit:int)->bool:
	for _i:int in limit:
		if rt.actor("player").get("intent")==null:return true
		rt.tick(.1)
	return rt.actor("player").get("intent")==null
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var profiles:Dictionary=Assembly.generation_profiles();var opening:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	if not check("actual new12 prepares",opening.get("ok",false),opening.get("reason")):return finish()
	var built:Dictionary=mount(opening.capture)
	if not check("shipping Native mounts current providers",built.get("ok",false),built.get("reason")):return finish()
	var rt:RefCounted=built.runtime;var before:Dictionary=rt.capture_checkpoint();var book:Dictionary=rt.handbook_snapshot()
	check("all six existing handbook sections remain",book.sections.size()==6)
	check("old trees card no longer denies implemented planting",not entry(book,"source:trees").description.contains("未接栽植") and entry(book,"source:trees").description.contains("补种"))
	for id:String in Rules.CROPS:
		var card:Dictionary=entry(book,"source:crop:"+id)
		check("crop definition is exact original owner "+id,Data.json_equal(card.get("definition",{}).get("crop_rules"),Rules.CROPS[id]))
		check("crop yield is a source relation "+id,entry(book,"item:"+str(Rules.CROPS[id].item)).sources.any(func(r:Dictionary)->bool:return r.id==card.id))
		check("crop water is a use relation, never a water grant "+id,entry(book,"item:r34:raw_water").uses.any(func(r:Dictionary)->bool:return r.id==card.id) and not entry(book,"item:r34:raw_water").sources.any(func(r:Dictionary)->bool:return r.id==card.id))
	for id:String in Rules.TREES:check("tree stage definition is exact original owner "+id,Data.json_equal(entry(book,"source:tree:"+id).get("definition",{}).get("tree_rules"),Rules.TREES[id]))
	check("raw source requires actual reusable bucket",entry(book,"item:r34:water_bucket").uses.any(func(r:Dictionary)->bool:return r.id=="source:raw_water"))
	check("raw source text preserves unsafe filtered water distinction",entry(book,"source:raw_water").description.contains("都不能直接饮用"))
	var target:String="process:manual:r34:compost_v2";var process:Dictionary=rt.handbook_snapshot("player",target).selection
	check("new recipe is actual production definition",not process.is_empty() and process.definition.inputs==rt.domain_service("production").recipes["r34:compost_v2"].inputs)
	check("legacy buildings do not become v2 hosts through empty station tags",not process.current.can_make and process.current.known_instances.is_empty())
	var hosts_match:bool=true
	for relation:Dictionary in process.sources:
		if not str(relation.id).begins_with("module:"):continue
		if not entry(book,relation.id).definition.get("mechanism",{}).get("recipes",[]).has(process.source_id):hosts_match=false
	check("all v2 host links require exact recipe capability",hosts_match)
	var ids:Dictionary={};var valid:bool=true
	for row:Dictionary in book.entries:ids[row.id]=true
	for row:Dictionary in book.entries:
		for related:String in row.related_ids:
			if not ids.has(related):valid=false
	check("every regional relation resolves in original handbook",valid)
	check("unknown readers still denied",not rt.handbook_snapshot("unknown","source:raw_water").available)
	check("new source and unavailable recipe queries leave actual state unchanged",Data.json_equal(before,rt.capture_checkpoint()))
	var bytes:String=FileAccess.get_file_as_string(args[1]);var decoded:Dictionary=Store.decode(bytes)
	if not check("original finite four-cycle native save decodes without editing",decoded.get("ok",false),decoded.get("reason")):return finish()
	var finite:Dictionary=mount(decoded.capture)
	if not check("original finite save full Native mounts",finite.get("ok",false),finite.get("reason")):return finish()
	var live:RefCounted=finite.runtime;var raw_before:String=bytes.sha256_text();var remote:Dictionary=live.handbook_snapshot("player",target).selection
	if not check("actual paid v2 water station is publicly identified",remote.current.known_instances.size()==1,remote.current):return finish()
	check("remote station does not authorize a direct batch",not remote.current.can_make)
	var module:Dictionary=remote.current.known_instances[0];var walk:Dictionary={}
	for port:Dictionary in module.ports:
		if port.purpose not in ["work","service","repair"]:continue
		for foot:Dictionary in port.use_points:
			walk=send(live,"walk","",{},foot)
			if walk.get("ok",false):break
		if walk.get("ok",false):break
	if not check("actual player walks to paid module original service foot",walk.get("ok",false) and idle(live,800),walk):return finish()
	var onsite_before:Dictionary=live.capture_checkpoint();var onsite:Dictionary=live.handbook_snapshot("player",target).selection
	if not check("onsite owner admission enables real v2 recipe",onsite.current.can_make and onsite.current.onsite,onsite.current):return finish()
	check("handbook ready query does not reserve or consume material",Data.json_equal(onsite_before,live.capture_checkpoint()))
	check("executable request targets actual module, direct owner admission",onsite.current.request.target_id==module.id and onsite.current.request.payload.direct==true)
	var pack:Dictionary=live.actor("player").pack.duplicate(true)
	var crafted:Dictionary=send(live,onsite.current.request.kind,onsite.current.request.target_id,onsite.current.request.payload)
	if not check("returned public request starts real original craft",crafted.get("ok",false) and idle(live,300),crafted):return finish()
	check("eighteen-second labor consumes original residues and raw exactly once",live.actor("player").pack["r34:crop_residue"]==pack["r34:crop_residue"]-2 and live.actor("player").pack["r34:raw_water"]==pack["r34:raw_water"]-1 and live.actor("player").pack.get("r34:compost",0)==pack.get("r34:compost",0)+1)
	check("actual read-only input stays byte-identical",FileAccess.get_file_as_string(args[1]).sha256_text()==raw_before)
	finish()
func finish()->void:
	var ok:bool=checks.all(func(row:Dictionary)->bool:return row.ok)
	var f:=FileAccess.open(output.path_join("results.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"ok":ok,"checks":checks,"scope":"actual new12 handbook queries plus preserved C finite four-cycle lab input and actual walk/craft; no natural complete economy, PCK, OS, visuals or FPS acceptance"},"\t"));f.close()
	for runtime in runtimes:runtime.retire()
	for host in hosts:
		if is_instance_valid(host):host.free()
	print("REGIONAL_BOOK "+str(checks.filter(func(row:Dictionary)->bool:return row.ok).size())+"/"+str(checks.size()))
	quit(0 if ok else 1)
