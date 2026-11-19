extends "res://tests/gameplay/factory_logistics.gd"
## Reuses E's real finite-source journey; adds D checks at actual transitions.
## Does not modify E test, assignments, tasks or actor inventories.
const Actors=preload("res://scripts/presentation/actor_view.gd")
var view:Node3D
var observed_haul:=false
var empty_collect:=true
var visual_checks:Array=[]

func mount(capture:Dictionary)->bool:
	var ok:bool=super.mount(capture)
	if ok:
		if is_instance_valid(view):view.free()
		view=Actors.new();root.add_child(view);view.set_process(false);view.configure(runtime)
	return ok

func visual(label:String,ok:bool,detail:Variant=null)->void:
	visual_checks.append({"name":label,"ok":ok,"detail":detail})
	super.check("D "+label,ok,detail)

func until_carried()->bool:
	for i:int in 70:
		runtime.tick(0.1);view.sync(0)
		var actor:Dictionary=runtime.actor("repair-resident")
		var intent:Variant=actor.get("intent")
		if intent is Dictionary and intent.get("owner")=="actions" and intent.get("kind")=="haul" and not str(intent.get("logistics_task_id","")).is_empty():observed_haul=true
		if actor.get("pending_delivery",{}).get("phase")=="collect" and float(actor.pack.get("timber",0))==0:
			empty_collect=empty_collect and not Actors.is_carrying(actor) and (not view._carried.has(actor.id) or not view._carried[actor.id].visible)
		# The fixture starts at its source: pickup can finish in the same STEP
		# that assigns collect, leaving no persistent haul intent that frame.
		# Observe the subsequent real delivery path instead of inventing one.
		if actor.get("pending_delivery",{}).get("phase")=="deliver" and observed_haul:
			visual("real actions haul task is observed before pickup",observed_haul)
			visual("collect promises never show undelivered cargo",empty_collect)
			visual("physical pickup shows actual board type and quantity",view._states[actor.id] in ["Carry","CarryWalk"] and view._carried[actor.id].visible and view._carried[actor.id].get_meta("item_id")=="timber" and view._carried[actor.id].get_meta("actual_items").timber==float(actor.pack.timber),actor)
			return true
	return false

func check(label:String,ok:bool,detail:Variant=null)->void:
	super.check(label,ok,detail)
	if not is_instance_valid(view) or runtime==null:return
	var before:Dictionary=runtime.capture_checkpoint()
	view.sync(0)
	var actor:Dictionary=runtime.actor("repair-resident")
	if label=="N2 atomically pauses B cargo task and starts A care":
		visual("N2 drink stows physical load while cargo_held preserves actual timber",view._states[actor.id]=="Use" and not view._carried[actor.id].visible and float(actor.pack.get("timber",0))==1.0 and task().status=="cargo_held",view.statistics())
	elif label=="two real trips conserve all finite timber without phantom production":
		visual("successful real deliver hides empty pack without respawning commodity",not Actors.is_carrying(actor) and not view._carried[actor.id].visible and runtime.stock("fixture:finite-receiver").items.timber==2)
	elif label=="withdrawn worker cannot silently finish a logistics delivery":
		visual("consent withdrawal retains visible real held boards without a work assignment",Actors.is_carrying(actor) and view._carried[actor.id].visible and view._states[actor.id] in ["Carry","CarryWalk"] and float(actor.pack.get("timber",0))==1.0,actor)
	visual("read-only presentation preserves complete authority at "+label,Data.json_equal(before,runtime.capture_checkpoint()))

func finish()->void:
	var report:Dictionary={"scope":"actual C/A/B/E finite-source logistics journey plus D original GLB/cargo consumers; explicit consent/prior return/local endpoints remain fixtures; not normal OS journey, actual frames, VA or performance","checks":checks,"failures":checks.filter(func(c:Dictionary)->bool:return not c.ok).map(func(c:Dictionary)->String:return str(c.name)),"visual_checks":visual_checks}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print("DDD_REAL_LOGISTICS ",JSON.stringify({"checks":checks.size(),"failures":report.failures}))
	if is_instance_valid(view):view.free()
	runtime=null
	if is_instance_valid(host):host.free()
	quit(1 if not report.failures.is_empty() else 0)
