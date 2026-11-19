extends SceneTree
## Actual generated 10/12 composition, finite opening pickup and cold restore.
## No actor/stock edits, renderer or user saves. Failed travel stays evidence.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Source=preload("res://scripts/world/factory_zone_production.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var hosts:Array=[]
var commands:Array=[]
var output:String
var serial:int=0
var ticks:int=0
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->bool:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name+" "+str(detail))
	return ok
func mount(capture:Dictionary)->Dictionary:
	var host:=Native.new();hosts.append(host);return host._assemble(capture)
func command(rt:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	serial+=1
	var request:Dictionary={"kind":kind,"actor_id":"player","target_id":target,"payload":payload,"destination":destination,"command_id":"A:opening12:"+str(serial)}
	var receipt:Dictionary=rt.command(request);commands.append({"request":request,"receipt":receipt,"time":rt.clock()});return receipt
func progress(rt:RefCounted,limit:int=2400)->bool:
	for i:int in limit:
		if rt.actor("player").get("intent")==null:return true
		rt.tick(.1);ticks+=1
	return rt.actor("player").get("intent")==null
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var profiles:Dictionary=Assembly.generation_profiles(12)
	if not check("new12 profiles resolve through original module service",profiles.get("ok",false),profiles.get("code")):return finish()
	var previous:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles,10))
	if not check("old10 first registration still composes",previous.get("ok",false),previous):return finish()
	var fresh:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles,12))
	if not check("explicit new12 composes through shipping Assembly",fresh.get("ok",false),fresh):return finish()
	check("new12 keeps exact stable10 terrain bytes",Data.json_equal(previous.capture.world.chunks,fresh.capture.world.chunks))
	var built:Dictionary=mount(fresh.capture)
	if not check("new12 mounts real runtime and all domains",built.get("ok",false),built.get("reason")):return finish()
	var rt:RefCounted=built.runtime
	var descriptors:Dictionary=Source.opening_additions(rt.world)
	if not check("exactly one finite S03 source descriptor",descriptors.get("ok",false) and descriptors.get("additions",[]).size()==1,descriptors):return finish()
	var bag:Dictionary=descriptors.additions[0]
	var stock:Dictionary=rt.stock(bag.source_id)
	check("independent actual searchable container holds exact finite items",stock.get("searched")==false and Data.json_equal(stock.get("items"),Source.START_ITEMS) and rt.world.entity(bag.entity_id).get("kind")=="container" and stock.get("module_id")==null)
	var old_stocks_ok:bool=true
	for old:Dictionary in previous.capture.facts.stocks:
		if not Data.json_equal(old,rt.stock(old.id)):old_stocks_ok=false
	check("all previous source stocks retain exact identities and counts",old_stocks_ok)
	check("no extra food safe water tools or people granted",Data.json_equal(previous.capture.facts.actors,rt.facts().actors) and Data.json_equal(previous.capture.world.extensions["r3:production"],rt.world.extension("r3:production")))
	var registration:Dictionary=built.services.modules.prepare_generation(rt.world,[],rt.facts())
	check("repeat original registration creates no stock tool or world change",registration.get("ok",false) and registration.get("initial_stocks",[]).is_empty() and registration.get("initial_tools",[]).is_empty() and registration.get("world_changes",[]).is_empty(),registration.get("code"))
	var walk:Dictionary=command(rt,"walk","",{},bag.use_point)
	if not check("player can request actual walk to supported bag use point",walk.get("ok",false),walk):return finish()
	if not check("actual movement reaches bag rather than teleporting",progress(rt),rt.actor("player")):return finish()
	var search:Dictionary=command(rt,"search",bag.source_id)
	if not check("onsite finite bag search starts through original actions",search.get("ok",false),search):return finish()
	if not check("real elapsed search exposes seed bag contents",progress(rt,100) and rt.stock(bag.source_id).get("searched",false)):return finish()
	var taken:Dictionary=command(rt,"take",bag.source_id,{"items":Source.START_ITEMS.duplicate(true)})
	if not check("original transfer takes finite seeds and reusable bucket",taken.get("ok",false),taken):return finish()
	check("one pickup empties actual bag without duplicating contents",Source.START_ITEMS.keys().all(func(id:String)->bool:return rt.actor("player").pack.get(id)==Source.START_ITEMS[id] and rt.stock(bag.source_id).items.get(id,0)==0))
	var encoded:Dictionary=Store.encode(rt.capture_checkpoint())
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.get("ok",false) else encoded
	var cold:Dictionary=mount(decoded.capture) if decoded.get("ok",false) else decoded
	if not check("actual native codec restores searched emptied source",cold.get("ok",false),cold.get("reason")):return finish()
	check("cold restore retains all pack items and exhausted bag",Data.json_equal(rt.actor("player").pack,cold.runtime.actor("player").pack) and Data.json_equal(rt.stock(bag.source_id),cold.runtime.stock(bag.source_id)))
	var again:Dictionary=cold.services.modules.prepare_generation(cold.world,[],cold.runtime.facts())
	check("consumption and cold revisit cannot refill source",again.get("ok",false) and again.get("initial_stocks",[]).is_empty() and again.get("world_changes",[]).is_empty(),again.get("code"))
	var saved:Dictionary=Store.encode(cold.runtime.capture_checkpoint())
	if saved.get("ok",false):
		var file:=FileAccess.open(output.path_join("actual-new12-seedbag.native.json"),FileAccess.WRITE);file.store_string(saved.text);file.close()
	finish()
func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var file:=FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"commands":commands,"failed":failed,"ticks":ticks,"scope":"Actual generated opening/physical source pickup/native cold; no injected inventory or people; not complete farming economy, PCK, OS, VA or FPS"},"\t"));file.close()
	for host:Node in hosts:host.free()
	print("ZONE_OPENING "+str(checks.size()-failed)+"/"+str(checks.size()));quit(0 if failed==0 else 1)
