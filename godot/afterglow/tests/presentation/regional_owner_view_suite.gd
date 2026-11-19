extends "res://tests/world/ecology_labor.gd"
## Reuses C's unchanged finite labor fixture and the ACTUAL providers.
## No source/capture/tool/route edits; not a normal starting-economy claim.
const EcologyView=preload("res://scripts/presentation/ecology_visual.gd")
const PlanningView=preload("res://scripts/presentation/planning_visual.gd")
const ActorView=preload("res://scripts/presentation/actor_view.gd")
var ecological:Node3D
var planning:Node3D
var actors:Node3D
var observed_stages:Dictionary={}
var observed_operations:Dictionary={}
var display_errors:Array=[]
var samples:int=0
var _ticks:int=0
func check(label:String,ok:bool,detail:Variant=null)->void:
	super.check(label,ok,detail)
	if runtime.domain_service("ecology")==null or runtime.actor("player").is_empty():return
	if ecological==null:
		ecological=EcologyView.new();root.add_child(ecological);ecological.set_process(false);ecological.configure(runtime)
		planning=PlanningView.new();root.add_child(planning);planning.set_process(false);planning.configure(runtime)
		actors=ActorView.new();root.add_child(actors);actors.set_process(false);actors.configure(runtime)
	observe()
func step(count:int)->void:
	for _i:int in count:
		runtime.tick(.1);_ticks+=1
		if actors!=null and (runtime.actor("player").get("intent")!=null or _ticks%100==0):observe()
func observe()->void:
	samples+=1
	var revision:int=world.get_revision();var clock:float=runtime.clock();var a:Dictionary=runtime.actor("player")
	ecological.sync();planning.set_selected("C:field");planning.sync();actors.sync(0)
	for row:Dictionary in ecological.statistics().visuals:observed_stages[row.stage]=true
	var work:Dictionary=actors.statistics().work.get("player",{})
	if work.get("available",false) and work.get("active",false):
		observed_operations[work.get("operation","")]=true
		if actors._states.player!="Use":display_errors.append({"kind":"active work missing Use","operation":work.get("operation")})
		if work.get("operation")=="till" and actors._held_ids.get("player")!="C:fixture:shovel":display_errors.append({"kind":"real shovel missing"})
	if world.get_revision()!=revision or runtime.clock()!=clock or not Data.json_equal(a,runtime.actor("player")):display_errors.append({"kind":"display changed authority"})
func finish()->void:
	if ecological!=null:
		super.check("D consumes actual C tilled seedling growing mature harvested sequence",["tilled","seedling","growing","mature","harvested"].all(func(stage:String)->bool:return observed_stages.has(stage)),observed_stages)
		super.check("D consumes actual B till sow water harvest owner actions",["till","sow","water","harvest_crop"].all(func(operation:String)->bool:return observed_operations.has(operation)),observed_operations)
		super.check("real provider display keeps authority unchanged and actual tool action",display_errors.is_empty(),display_errors)
		super.check("planning selects exact real field cell",planning.statistics().counts.get("selected")==1,planning.statistics())
		var provider:Variant=runtime.domain_service("ecology")
		var basis:Dictionary=provider.presentation_basis("player")
		var old_query:String=ecological._query_basis
		var old_revision:int=world.get_revision()
		var current:Dictionary=world.snapshot()
		super.check("actual ecology exposes nonpersistent authority token",basis.get("ecology_generation") is Dictionary and basis.ecology_generation.has("generation"),basis)
		var reloaded:Dictionary=world.load_snapshot(current)
		ecological.sync()
		super.check("same object same revision cold load invalidates actual ecology query",reloaded.ok and world.get_revision()==old_revision and ecological._query_basis!=old_query and ecological.statistics().available,{"before":basis,"after":provider.presentation_basis("player")})
		ecological.free();planning.free();actors.free()
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"commands":commands,"samples":samples,"observed_stages":observed_stages,"observed_operations":observed_operations,"display_errors":display_errors,"scope":"C unchanged finite agronomy fixture through actual Runtime commands/A clock/B work/C ecology/D native nodes and original rigs. Not natural economy, PCK/renderer/OS/VA/FPS."},"\t",true,true))
	print("DDD_REGIONAL_OWNER_VIEW ",checks.size()," failed=",failed);runtime.retire();quit(0 if failed==0 else 1)
