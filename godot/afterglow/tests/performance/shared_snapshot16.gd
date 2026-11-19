extends SceneTree
## Full-state reference comparison; no fixture supplies construction materials.
const Client=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Context=preload("res://scripts/actions/domain_context.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func run()->void:
	var args:=OS.get_cmdline_user_args();var output:String=args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var borrowed:Dictionary={"actors":[{"id":"player","hp":100,"pack":{"timber":4}}],"stocks":[],"actions":[],"quests":[]}
	var ctx:Dictionary={"draft_snapshot":func()->Dictionary:return borrowed,"facts_diff":Client.Runtime.facts_diff}
	var one:=Draft.new(ctx);var two:=Draft.new(ctx)
	one.actor("player").pack.timber=2
	check("writable staged deep-forks shared initial facts",borrowed.actors[0].pack.timber==4 and two.observe_facts().actors[0].pack.timber==4)
	one.initial.actors[0].hp=50
	check("public initial is writable without leaking to sibling or staged",borrowed.actors[0].hp==100 and two.observe_facts().actors[0].hp==100 and one.staged.actors[0].hp==100)
	var three:=Draft.new(ctx);three.staged=three.observe_facts();three.actor("player").hp=30
	check("explicit staged observation assignment still forks before writes",borrowed.actors[0].hp==100 and three.initial.actors[0].hp==100)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	check("actual shipping saved world decodes",decoded.ok)
	if not decoded.ok:return finish(output,[])
	var reference:Script=load(args[2]);var rows:Array=[];var captures:Dictionary={}
	for mode:String in ["reference","current","current","reference"]:
		var host:=Client.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
		check("same saved world actually assembles "+mode+str(rows.size()),built.ok,built.get("reason"))
		if not built.ok:continue
		var runtime:RefCounted=built.runtime
		if mode=="reference":
			var old:RefCounted=reference.new()
			var configured:Dictionary=old.configure(runtime._context)
			check("original runtime configures against identical domain implementations",configured.ok)
			if not configured.ok:continue
			runtime=old
		var original:Dictionary=Geometry.location(runtime.actor("player"))
		var beds:Array=built.world.entities().filter(func(e:Dictionary)->bool:return e.get("data",{}).get("village_shelter",false))
		var destination:Dictionary=beds[0].data.module_bed.approach if not beds.is_empty() else original
		var admitted:bool=true;var began:int=Time.get_ticks_usec()
		for step:int in 120:
			if step%40==0 and runtime.actor("player").get("intent")==null:
				var command:Dictionary=runtime.command({"kind":"walk","actor_id":"player","command_id":"snapshot16-walk-"+str(step),"destination":destination if step%80==0 else original})
				admitted=admitted and command.ok
			runtime.tick(.1)
		var elapsed:int=Time.get_ticks_usec()-began
		check("reference/current actual walking commands all admitted "+mode+str(rows.size()),admitted)
		var capture:Dictionary=runtime.capture_checkpoint()
		if captures.is_empty():captures=capture
		else:check("all canonical authority facts, world, clock and source equal reference "+mode+str(rows.size()),Data.json_equal(captures,capture))
		rows.append({"mode":mode,"steps":120,"usec":elapsed,"mean_step_usec":float(elapsed)/120,"simulation":runtime.simulation_costs(),"authority":runtime.authority_costs()})
		# API adapters cannot leak one step's constructor data into later steps.
		var adapter:Dictionary=Context.isolate(runtime._context.merged({"runtime":runtime},true))
		var before:=Draft.new(adapter);var before_facts:Dictionary=before.observe_facts().duplicate(true)
		runtime.tick(.1)
		var after:=Draft.new(adapter)
		check("constructor view survives later fixed-step mutation "+mode+str(rows.size()),Data.json_equal(before.observe_facts(),before_facts) and after.observe_facts().time>before_facts.time)
		runtime.retire()
	finish(output,rows)
func finish(output:String,rows:Array)->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":rows,"scope":"ABBA source CPU fixture, exact current domain implementations with pre16 Runtime as reference; full checkpoint equality and shared Draft ownership. Not GPU FPS or independent PCK comparison."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}))
	quit(1 if failed else 0)
