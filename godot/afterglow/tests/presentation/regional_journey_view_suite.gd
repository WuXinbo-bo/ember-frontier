extends SceneTree
## Observe supplied immutable B/E checkpoints, never manufacture actor/task data.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Cargo=preload("res://scripts/presentation/factory_cargo_view.gd")
var runtime:RefCounted
var view:Node3D
var checks:Array=[]
var errors:Array=[]
var observed:Array=[]
var mode:String
var output:String
var steps:int=0
var read_only:bool=true
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL ",name," ",detail)
func mount(capture:Dictionary)->bool:
	var native:=Native.new();var built:Dictionary=native._assemble(capture);native.free()
	check("unchanged full Native mounts actual "+mode+" checkpoint",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return false
	if runtime!=null:runtime.retire()
	runtime=built.runtime
	var regions:Dictionary={}
	for actor:Dictionary in runtime.facts().actors:regions[actor.regionId]=true
	for id:String in regions:
		var complete:bool=false;var batches:int=0;var ok:bool=true
		while not complete and batches<128:
			var plan:Dictionary=runtime.world.prepare_region_residency(id,true,runtime.world.get_revision(),32)
			if not plan.get("ok",false):ok=false;break
			complete=plan.complete;batches+=1
			if not runtime._commit(plan).get("ok",false):ok=false;break
		check("original bounded residency prepares actual actor region "+id,ok and complete,{"batches":batches,"budget":32})
		if not ok or not complete:return false
	if not is_instance_valid(view):view=Actors.new();root.add_child(view);view.set_process(false)
	view.configure(runtime)
	check("actual original character assemblies remain valid",view.assembly_report().ok,view.assembly_report())
	return true
func observe(id:String)->void:
	var before:Dictionary=runtime.capture_checkpoint();view.sync(0)
	read_only=read_only and Data.json_equal(before,runtime.capture_checkpoint())
	var a:Dictionary=runtime.actor(id);var intent:Variant=a.get("intent")
	var kind:String=str(intent.get("kind","")) if intent is Dictionary else ""
	var state:String=str(view._states.get(id,""))
	if kind=="zone_supply" and (state not in ["Idle","Walk"] or not str(view._held_ids.get(id,"")).is_empty() or view._work_items.has(id)):errors.append({"kind":"premature supply labor or tool","state":state})
	if kind=="harvest":
		var frame:Dictionary=view._work_frames.get(id,{})
		if frame.get("available",false) and frame.get("active",false) and state!="Use":errors.append({"kind":"actual harvest missing Use","state":state})
	if a.get("pending_delivery",{}).get("phase")=="deliver":
		var expected:Dictionary=Cargo.hand_items(a);var prop:Node3D=view._carried.get(id)
		if not expected.is_empty() and state in ["Carry","CarryWalk"]:
			if not is_instance_valid(prop) or not prop.visible or prop.get_meta("item_id","")!=Cargo.representative(expected) or not Data.json_equal(prop.get_meta("actual_items",{}),expected):errors.append({"kind":"actual cargo representation mismatch","items":expected,"state":state})
	var key:String=kind+":"+state
	if not observed.any(func(row:Dictionary)->bool:return row.key==key):observed.append({"key":key,"step":steps,"time":runtime.clock(),"actor":a,"held":view._held_ids.get(id,""),"work":view._work_frames.get(id,{})})
func tick(id:String)->void:
	runtime.tick(.1);steps+=1;observe(id)
func command(kind:String,target:String="",payload:Dictionary={})->Dictionary:
	return runtime.command({"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"command_id":"D:observed:"+mode+":"+str(steps)+":"+kind})
func output_delivery()->void:
	var task:Dictionary={}
	for row:Dictionary in runtime.world.extension("r34:logistics").get("tasks",[]):
		if row.get("zone_output_work_id")!=null and row.actor_id=="player" and row.phase=="deliver":task=row;break
	check("real C-completed crop has original logistics custody",not task.is_empty(),task)
	if task.is_empty():return
	var items:Dictionary=task.items.duplicate(true);var before:Dictionary=runtime.stock(task.destination_id).items.duplicate(true)
	check("pre-dispatch actual pack is retained without fake pending delivery",not runtime.actor("player").has("pending_delivery") and items.keys().all(func(k:String)->bool:return float(runtime.actor("player").pack.get(k,0))>=float(items[k])))
	var accepted:=command("zonework.deliver",task.zone_id,{"task_id":task.id})
	check("original public delivery command accepts actual custody",accepted.get("ok",false),accepted.get("reason"))
	if not accepted.get("ok",false):return
	observe("player")
	check("real task dispatch sets physical held small crop",runtime.actor("player").intent.kind=="haul" and Actors.is_carrying(runtime.actor("player")) and view._carried.get("player")!=null and view._carried.player.visible)
	for _i:int in 3:tick("player")
	check("real crop delivery visibly walks",observed.any(func(row:Dictionary)->bool:return row.key=="haul:CarryWalk"),observed.map(func(row:Dictionary)->String:return row.key))
	var paused:=command("held","",{"held":false});var at:Dictionary=runtime.actor("player");var count:Dictionary=runtime.actor("player").pack.duplicate(true)
	for _i:int in 4:tick("player")
	check("original manual pause keeps real visible cargo without movement",paused.get("ok",false) and runtime.actor("player").x==at.x and runtime.actor("player").z==at.z and Data.json_equal(runtime.actor("player").pack,count) and view._carried.player.visible)
	var saved:=Store.encode(runtime.capture_checkpoint());var decoded:=Store.decode(saved.text) if saved.get("ok",false) else saved
	check("actual paused cargo JSON cold decodes",decoded.get("ok",false),decoded.get("code"))
	if not decoded.get("ok",false):return
	FileAccess.open(output+".paused.native.json",FileAccess.WRITE).store_string(saved.text)
	if not mount(decoded.capture):return
	observe("player")
	check("same Node after cold rebuilds original actual crop cargo",Actors.is_carrying(runtime.actor("player")) and view._carried.get("player")!=null and view._carried.player.visible and not runtime.actor("player").intent.held)
	check("standard held resumes restored original delivery",command("held","",{"held":true}).get("ok",false))
	for _i:int in 800:
		tick("player")
		var current:Dictionary={}
		for row:Dictionary in runtime.world.extension("r34:logistics").tasks:
			if row.id==task.id:current=row;break
		if current.get("status")=="completed":break
	check("real target gets only original finite crop once",items.keys().all(func(k:String)->bool:return float(runtime.stock(task.destination_id).items.get(k,0))==float(before.get(k,0))+float(items[k]) and float(runtime.actor("player").pack.get(k,0))==0),{"pack":runtime.actor("player").pack,"destination":runtime.stock(task.destination_id).items})
	check("actual delivered empty hands hide old cargo",not Actors.is_carrying(runtime.actor("player")) and not view._carried.player.visible)
func natural_npc()->void:
	var id:String="repair-resident";var intent:Dictionary=runtime.actor(id).get("intent",{})
	check("unaltered E natural checkpoint contains active actual supply",intent.get("owner")=="actions" and intent.get("kind")=="zone_supply",intent)
	if intent.get("kind")!="zone_supply":return
	var tool_id:String=str(intent.supply.tool_ids[0]);var wear:float=float(runtime.tool(tool_id).durability);var tree_id:String=""
	check("real axe is still at original searched rack before pickup",runtime.tool(tool_id).holderId==intent.supply.source_id)
	observe(id)
	var acquired:bool=false;var effective:bool=false;var felled:bool=false
	for _i:int in 1500:
		tick(id)
		var a:Dictionary=runtime.actor(id);var current:Variant=a.get("intent")
		acquired=acquired or runtime.tool(tool_id).holderId=="pack:"+id
		if current is Dictionary and current.get("kind")=="harvest":
			tree_id=str(current.get("request",{}).get("target_id",""));var work:Dictionary=view._work_frames.get(id,{})
			if work.get("available",false) and work.get("active",false):effective=effective or (view._states.get(id)=="Use" and view._held_ids.get(id)==tool_id)
		if not tree_id.is_empty() and runtime.world.entity(tree_id).get("data",{}).get("harvest",{}).get("phase")=="stump":felled=true;break
	check("same original NPC really retrieves source-held axe",acquired)
	check("real effective original harvest uses exact owned axe",effective,observed.map(func(row:Dictionary)->String:return row.key))
	check("actual generated tree is felled with original axe wear",felled and float(runtime.tool(tool_id).durability)<wear,{"tree":tree_id,"wear_before":wear,"wear_after":runtime.tool(tool_id).durability})
	check("original population and voluntary consent preserved",runtime.facts().actors.size()==3 and ["repair-resident","village-resident"].all(func(actor_id:String)->bool:return runtime.actor(actor_id).relationship.consent and runtime.actor(actor_id).hp==100))
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];mode=args[2]
	var raw:String=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(raw)
	check("owner exact supplied input identity",raw.sha256_text()==args[3],raw.sha256_text())
	check("owner full canonical checkpoint decodes",decoded.get("ok",false),decoded.get("code"))
	if decoded.get("ok",false) and mount(decoded.capture):
		if mode=="output":output_delivery()
		elif mode=="npc":natural_npc()
	check("all actual consumer reads preserve complete authority",read_only)
	check("real transitions have no invented or missing props",errors.is_empty(),errors)
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"steps":steps,"observed":observed,"errors":errors,"scope":"Exact unchanged owner checkpoint, original full Native/Runtime and explicit bounded residency warm, actual D original rigs/props. B crop input is finite lab, public original delivery command; E input is actual natural voluntary recruitment/tool staging, autonomous supply/harvest. Domains separately qualified. Not package, renderer, OS, VA, FPS or full economy."},"\t",true,true))
	if is_instance_valid(view):view.free()
	if runtime!=null:runtime.retire()
	print("DDD_REGIONAL_JOURNEY ",mode," ",checks.size()," failed=",failed);quit(0 if failed==0 else 1)
