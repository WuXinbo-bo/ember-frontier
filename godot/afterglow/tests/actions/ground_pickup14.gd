extends SceneTree
## Explicit contact/stock fixtures verify authority boundaries, not acquisition.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var sequence:=0
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+str(detail))
func command(rt:RefCounted,id:String,auto:bool=false)->Dictionary:
	sequence+=1
	return rt.command({"kind":"pickup","actor_id":"player","target_id":id,"command_id":"pickup-test:"+str(sequence),"payload":{"automatic":auto}})
func mount(capture:Dictionary)->Dictionary:
	var node:=Native.new();var result:Dictionary=node._assemble(capture);node.free();return result
func run()->void:
	var profiles:Dictionary=Assembly.generation_profiles(14)
	var source:Dictionary=Assembly.generate(713,profiles.profiles,14)
	var prepared:Dictionary=Assembly.prepare(source)
	check("actual14 prepares for explicit authority fixture",prepared.get("ok",false))
	if not prepared.get("ok",false):return finish()
	var capture:Dictionary=prepared.capture
	var tree:Dictionary={}
	for entity:Dictionary in capture.world.entities.values():
		if entity.kind=="tree" and entity.regionId=="RH-HOME" and entity.data.harvest.seconds==6:tree=entity;break
	check("new14 has physical six-second small starting tree",not tree.is_empty())
	if tree.is_empty():return finish()
	var id:String=tree.data.outputId
	var drop:Dictionary=capture.world.entities[id]
	var player:Dictionary=Draft.find(capture.facts.actors,"player")
	player.merge(drop.position,true);player.regionId=drop.regionId;player.buildingId=null;player.storeyId=null
	var stock:Dictionary=Draft.find(capture.facts.stocks,id);stock.items={"scrap":4,"cloth":2,"log":3}
	var ready:Dictionary=mount(capture)
	check("actual native fixture assembles",ready.get("ok",false),ready.get("code"))
	if not ready.get("ok",false):return finish()
	var rt:RefCounted=ready.runtime
	var first:Dictionary=command(rt,id,true)
	check("autopickup takes bounded nearby logs and small items",first.ok and rt.actor("player").pack.get("scrap",0)==3 and rt.actor("player").pack.get("cloth",0)==2 and rt.actor("player").pack.get("log",0)==3,first.get("reason"))
	check("entries above the per-pass limit stay on the ground",rt.stock(id).items.get("log",0)==0 and rt.stock(id).items.get("scrap",0)==1)
	var second:Dictionary=command(rt,id)
	check("manual pickup transfers remaining finite logs and scrap",second.ok and rt.stock(id).items.get("log",0)==0 and rt.actor("player").pack.get("log",0)==3 and rt.actor("player").pack.get("scrap",0)==4,second.get("reason"))
	var before:Dictionary=rt.capture_checkpoint()
	var duplicate:Dictionary=command(rt,id)
	check("empty retry rejects without inventory mutation",not duplicate.ok and Data.json_equal(before,rt.capture_checkpoint()))
	var normal_id:String=""
	for item:Dictionary in rt.stock_states():
		if item.id!=id and not rt.world.entity(item.id).get("data",{}).get("dropped",false):normal_id=item.id;break
	var ordinary:Dictionary=command(rt,normal_id)
	check("normal chest cannot be converted into ground pickup",not ordinary.ok and ordinary.get("code")=="NOT_GROUND_DROP")
	var saved:Dictionary=Store.decode(Store.encode(rt.capture_checkpoint()).text)
	var cold:Dictionary=mount(saved.capture)
	check("pickup settlement survives canonical cold restore",cold.ok and cold.runtime.actor("player").pack.get("log")==3 and cold.runtime.stock(id).items.get("log",0)==0)
	if cold.ok:cold.runtime.retire()
	rt.retire()
	# Unauthorized owner and range use fresh detached fixtures, never edits to
	# live authority or another reviewer's active world.
	stock.owner="someone-else"
	var owned:Dictionary=mount(capture)
	if owned.ok:
		var denied:Dictionary=command(owned.runtime,id,true)
		check("automatic pickup refuses another owner's property",not denied.ok and owned.runtime.stock(id).items.get("log")==3)
		denied=command(owned.runtime,id)
		check("manual pickup also honors actual ownership",not denied.ok and owned.runtime.stock(id).items.get("log")==3)
		owned.runtime.retire()
	stock.owner=null
	player.x+=4.0
	var far:Dictionary=mount(capture)
	if far.ok:
		var denied:Dictionary=command(far.runtime,id,true)
		check("autopickup refuses physically distant small materials",not denied.ok and far.runtime.stock(id).items.get("scrap")==4)
		far.runtime.retire()
	finish()
func finish()->void:
	var args:Array=OS.get_cmdline_user_args();var output:String=args[0] if not args.is_empty() else "user://pickup14"
	DirAccess.make_dir_recursive_absolute(output)
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"suite":"ground-pickup14","scope":"Actual generation/native authority/cold save with explicitly injected contact and ground stock fixtures; not a natural acquisition or wall-layout qualification.","checks":checks,"failed":failed},"\t",true,true))
	print(JSON.stringify({"suite":"ground-pickup14","checks":checks.size(),"failed":failed}))
	quit(1 if failed else 0)
