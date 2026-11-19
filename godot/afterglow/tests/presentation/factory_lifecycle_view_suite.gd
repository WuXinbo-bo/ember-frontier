extends "res://tests/modules/run_factory_lifecycle.gd"
## Adds actual D consumers to B's existing finite lifecycle journey.
const PublicView=preload("res://scripts/presentation/factory_view.gd")
const ActorView=preload("res://scripts/presentation/actor_view.gd")
var current_runtime:RefCounted
var public_view:Node3D
var actor_view:Node3D
var visual_checks:Array=[]
const MODULE_ID="r34:test-built-woodshop"

func observe(rt:RefCounted)->void:
	if rt==null:return
	current_runtime=rt
	if public_view==null:
		public_view=PublicView.new();root.add_child(public_view);public_view.set_process(false)
		actor_view=ActorView.new();root.add_child(actor_view);actor_view.set_process(false)
	public_view.configure(rt);actor_view.configure(rt)

func advance(rt:RefCounted,services:Dictionary,steps:int,domain:String)->void:
	super.advance(rt,services,steps,domain)
	observe(rt)

func command(rt:RefCounted,id:String,kind:String,target:String="",payload:Dictionary={},actor_id:String="player")->Dictionary:
	var result:Dictionary=super.command(rt,id,kind,target,payload,actor_id)
	observe(rt)
	return result

func commit(rt:RefCounted,prepared:Dictionary)->Dictionary:
	var result:Dictionary=super.commit(rt,prepared)
	observe(rt)
	return result

func visual(label:String,ok:bool,detail:Variant=null)->void:
	visual_checks.append({"name":label,"ok":ok,"detail":detail})
	checks.append({"name":"D "+label,"ok":ok,"detail":detail})
	if not ok:print("FAIL D ",label," ",JSON.stringify(detail))

func check(name:String,ok:bool,detail:Variant=null)->void:
	super.check(name,ok,detail)
	if current_runtime==null or not is_instance_valid(public_view):return
	var before:Dictionary=current_runtime.capture_checkpoint()
	public_view.sync();actor_view.sync(0)
	var condition:Node3D=public_view._conditions.get(MODULE_ID)
	if name=="real on-site hammer labor advances unique project":
		visual("real module construction animates actor and local work at owner progress",condition!=null and condition.statistics().construction_active and actor_view._states.player=="Use" and actor_view.statistics().work.player.available,public_view.statistics())
	elif name=="released hold stops effective labor and preserves costs":
		visual("module held=false stops actual actor Use and local chips",condition!=null and not condition.statistics().construction_active and actor_view._states.player!="Use")
	elif name=="one start moves material to WIP and promises output":
		var machine:Node3D=public_view._machines.get(MODULE_ID)
		visual("actual machine owner starts moving subassembly without operator",machine!=null and machine.statistics().active and machine.statistics().progress_seconds>0,public_view.statistics())
	elif name=="pause preserves WIP progress and energy":
		visual("actual machine pause stops subassembly work",public_view._machines.has(MODULE_ID) and not public_view._machines[MODULE_ID].statistics().active,public_view.statistics())
	elif name=="two real single batches yield once each":
		var stock:Node3D=public_view._buffers.get(MODULE_ID,{}).get("output:timber")
		visual("real batch outputs appear only as actual finite board stock",stock!=null and stock.statistics().actual==8.0 and stock.statistics().visible_parts>0,public_view.statistics())
	elif name=="same damage cause cannot apply twice":
		visual("real partial damage binds existing alpha detail on owner surface",condition!=null and condition.statistics().damage_visible and condition.statistics().damage_ratio>0,public_view.statistics())
	elif name=="ruin freezes one recovery ledger and real local caches":
		var machine:Node3D=public_view._machines.get(MODULE_ID)
		visual("ruin stops machinery and removes duplicate intact damage detail",condition!=null and not condition.statistics().damage_visible and (machine==null or not machine.statistics().active),public_view.statistics())
	visual("public snapshot and actor pose never settle goods at "+name,Data.json_equal(before,current_runtime.capture_checkpoint()))

func finish()->void:
	var failures:Array=checks.filter(func(c:Dictionary)->bool:return not c.ok).map(func(c:Dictionary)->String:return str(c.name))
	var report:Dictionary={"scope":"actual B finite fixture lifecycle commands/advances/cold restore plus D public/actor nodes; no normal-economy, renderer, OS, VA or performance approval","checks":checks,"failures":failures,"visual_checks":visual_checks}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	if is_instance_valid(public_view):public_view.free()
	if is_instance_valid(actor_view):actor_view.free()
	current_runtime=null
	print("DDD_REAL_LIFECYCLE ",JSON.stringify({"checks":checks.size(),"failures":failures}));quit(1 if not failures.is_empty() else 0)
