extends SceneTree
## Finite fixture: actual travel, holds, consumed inputs and save/reload.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const WELL="r34:ecology:raw-source:RH-HOME"
const WORKSHOP="r34:generated:RH-HOME:woodwork"
const PACK="pack:player"
var host:Node
var runtime:RefCounted
var checked:int=0
var failed:int=0

func _initialize()->void:call_deferred("run")

func check(label:String,ok:bool,detail:Variant=null)->bool:
	checked+=1
	if not ok:failed+=1;print("FAIL ",label," ",detail)
	return ok

func close()->void:
	if runtime!=null:runtime.retire()
	if is_instance_valid(host):host.free()
	print("CHAPTER_SUPPLY_ACTIONS ",checked-failed,"/",checked)
	quit(0 if failed==0 else 1)

func send(kind:String,id:String,payload:Dictionary={})->Dictionary:
	return runtime.command({"kind":kind,"target_id":id,"actor_id":"player","command_id":"chapter-fixture:"+str(runtime.get_revision())+":"+kind,"payload":payload})

func wait_done()->bool:
	for i:int in 750:
		runtime.tick(.1)
		if runtime.actor("player").get("intent")==null:return true
	return false

func craft(recipe:String,target_tool:String="")->Dictionary:
	var payload:Dictionary={"recipe_id":recipe,"source_id":PACK,"output_id":PACK,"tool_ids":[],"direct":false}
	if not target_tool.is_empty():payload.repair_tool_id=target_tool
	return send("craft",WORKSHOP,payload)

func run()->void:
	var profiles:=Assembly.generation_profiles(20)
	if not check("chapter profiles",profiles.ok,profiles.get("code")):return close()
	var opening:=Assembly.prepare(Assembly.generate(713,profiles.profiles,20))
	if not check("actual chapter generation",opening.ok,opening.get("code")):return close()
	var capture:Dictionary=opening.capture
	var player:=Draft.find(capture.facts.actors,"player")
	player.pack={"r34:water_bucket":1,"log":2,"r34:potato":2,"timber":1}
	player.thirst=60.0;player.hunger=60.0
	var ax_id:String=""
	for axe:Dictionary in capture.world.extensions["r3:production"].tools:
		if axe.kind!="salvaged_axe":continue
		axe.durability=0.0;axe.holderId=PACK;ax_id=str(axe.id);break
	host=Native.new();var built:Dictionary=host._assemble(capture)
	if not check("assemble",built.ok,built.get("code")):return close()
	runtime=built.runtime
	var draw:=send("zonework.draw_water",WELL)
	if not check("real well admission gives no water before work",draw.ok and runtime.stock(PACK).items.get("r34:raw_water",0)==0,draw):return close()
	var paused:=send("held","",{"held":false})
	var encoded:=Store.encode(runtime.capture_checkpoint());var decoded:=Store.decode(encoded.text) if encoded.ok else encoded
	if not check("paused well survives save",paused.ok and decoded.ok,decoded.get("code")):return close()
	runtime.retire();runtime=null;built=host._assemble(decoded.capture)
	if not check("reassemble",built.ok,built.get("code")):return close()
	runtime=built.runtime
	var resumed:=send("held","",{"held":true})
	check("arrival and well work settle real raw water once",resumed.ok and wait_done() and runtime.stock(PACK).items.get("r34:raw_water",0)==2 and runtime.stock(PACK).items.get("r34:water_bucket",0)==1,runtime.actor("player").activity)
	check("raw is never drinkable",Content.consumable_definition("r34:raw_water","drink").is_empty())
	var boil:=craft("r34:raw_boil_water_v2")
	check("boil pays exact fuel and produces drinkable water",boil.ok and wait_done() and runtime.stock(PACK).items.get("r34:raw_water",0)==0 and runtime.stock(PACK).items.get("log",0)==1 and runtime.stock(PACK).items.get("water",0)==2,boil)
	var drink:=send("drink","",{"source_id":PACK,"item_id":"water"})
	check("ordinary drink consumes the real safe water",drink.ok and wait_done() and runtime.stock(PACK).items.get("water",0)==1,drink)
	var cook:=craft("r34:cook_potato_v2")
	check("cooking consumes potatoes, water and fuel",cook.ok and wait_done() and runtime.stock(PACK).items.get("r34:potato",0)==0 and runtime.stock(PACK).items.get("water",0)==0 and runtime.stock(PACK).items.get("log",0)==0 and runtime.stock(PACK).items.get("r34:meal_simple",0)==3,cook)
	var eat:=send("eat","",{"source_id":PACK,"item_id":"r34:meal_simple"})
	check("ordinary eat consumes the actual cooked meal",eat.ok and wait_done() and runtime.stock(PACK).items.get("r34:meal_simple",0)==2,eat)
	var repair:=craft("r34:repair_axe_v2",ax_id)
	check("the same zero durability axe is restored using one real board",repair.ok and wait_done() and runtime.stock(PACK).items.get("timber",0)==0 and float(runtime.tool(ax_id).get("durability",0))>0,repair)
	close()
