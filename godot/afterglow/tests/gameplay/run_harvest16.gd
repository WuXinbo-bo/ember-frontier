extends SceneTree
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Profile=preload("res://scripts/runtime/playtest_profile.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
var checks:Array=[]
var output:String
var runtime:RefCounted
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var profiles:Dictionary=Assembly.generation_profiles(16)
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles,16))
	check("real normal16 prepares",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):return finish()
	var opening:Dictionary=Profile.prepare_opening(prepared.capture,"normal")
	var host:=Native.new();var built:Dictionary=host._assemble(opening);host.free()
	check("real normal16 assembles",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime
	var axe:String=opening.source.opening_configuration.tools.salvaged_axe
	var before:float=float(runtime.tool(axe).durability)
	var trees:Array=runtime.world.entities("RH-HOME").filter(func(t:Dictionary)->bool:return t.kind=="tree" and t.data.harvest.seconds==3)
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return G.point(a.position).distance_squared_to(G.point(runtime.actor("player")))<G.point(b.position).distance_squared_to(G.point(runtime.actor("player"))))
	var selected:Dictionary={};var receipt:Dictionary={}
	for tree:Dictionary in trees:
		receipt=runtime.command({"kind":"harvest","actor_id":"player","command_id":"harvest16:real","target_id":tree.id,"payload":{"direct":false,"tool_ids":[axe]}})
		if receipt.ok:selected=tree;break
	check("original action planner routes from normal spawn to a genuine small tree",not selected.is_empty(),receipt)
	if selected.is_empty():return finish()
	var max_move:float=0.0
	for i:int in 600:
		var old:=G.point(G.location(runtime.actor("player")));runtime.tick(.1)
		max_move=maxf(max_move,old.distance_to(G.point(G.location(runtime.actor("player")))))
		if runtime.actor("player").get("intent")==null:break
	var orders:Array=runtime.world.extension("r3:production").orders.filter(func(o:Dictionary)->bool:return o.targetId==selected.id)
	check("same harvest order completes exactly3 actual labor seconds",orders.size()==1 and orders[0].status=="completed" and is_equal_approx(float(orders[0].duration),3) and is_equal_approx(float(orders[0].elapsed),3),orders)
	check("original small-tree total wear stays3 despite half duration",is_equal_approx(float(runtime.tool(axe).durability),before-3))
	check("normal material yield remains exactly3 real logs at original drop",runtime.stock(selected.data.outputId).items.get("log",0)==3)
	check("normal player follows physical small movement steps",max_move>0 and max_move<1,max_move)
	check("harvested tree persists as original stump",runtime.world.entity(selected.id).data.harvest.phase=="stump")
	var again:Dictionary=runtime.command({"kind":"harvest","actor_id":"player","command_id":"harvest16:again","target_id":selected.id,"payload":{"direct":false,"tool_ids":[axe]}})
	check("repeat request cannot duplicate original tree output",not again.ok and runtime.stock(selected.data.outputId).items.get("log",0)==3,again.get("code"))
	var wire:Dictionary=Store.encode(runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(wire.get("text",""))
	check("completed half-time tree keeps original native checksum envelope",wire.ok and decoded.ok)
	if decoded.ok:
		var cold:=Native.new();var restored:Dictionary=cold._assemble(decoded.capture);cold.free()
		check("cold tree retains once-only output and exact original axe wear",restored.get("ok",false) and restored.runtime.stock(selected.data.outputId).items.get("log",0)==3 and is_equal_approx(float(restored.runtime.tool(axe).durability),before-3),restored.get("reason"))
		if restored.get("ok",false):restored.runtime.retire()
	FileAccess.open(output+"/actual-felled-small-tree.native.json",FileAccess.WRITE).store_string(wire.text)
	finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"suite":"real-harvest16","checks":checks,"failed":failed,"scope":"Untouched normal16 finite opening, original axe/route/harvest order and yield/wear/cold-save. No injection; headless, not FPS."},"\t",true,true))
	if runtime!=null:runtime.retire()
	print(JSON.stringify({"suite":"real-harvest16","checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
