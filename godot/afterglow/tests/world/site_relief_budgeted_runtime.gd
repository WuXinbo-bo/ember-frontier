extends "res://tests/world/site_relief_runtime.gd"
## Same real worker/labor/cold-restore input; exercise C's promoted-view policy
## at the newly exposed Y=0 seam, without opening a second formal client.
var derived_phases:Array=[]

func collider_agrees(view:Node,world:RefCounted,cx:int,cz:int,label:String)->void:
	var keys:Array=Data.affected(Vector3i(cx,0,cz),int(world.config().chunkCells))
	if label=="before work":
		# The parent derived the complete finite edit neighbourhood. Retire only
		# the untouched initial queue, then use the exact promoted C edit policy.
		view.cancel_pending()
		view.set_budgeted_edits(true)
		view.set_streaming_updates(true)
	else:
		var pending:Dictionary=view.readiness(keys)
		var stale:=false
		for key:String in keys:stale=stale or view._chunks.has(key)
		check("budgeted commit immediately retires stale upper lower bodies "+label,not stale and not pending.ready and not pending.geometry_ready,pending)
	var iterations:=0
	while not view.readiness(keys).geometry_ready and iterations<100:
		view.prioritize(keys)
		view.process_budget(4000)
		iterations+=1
		if not view.readiness(keys).geometry_ready:await process_frame
	var ready:Dictionary=view.readiness(keys)
	if label!="before work":
		check("new collision registration still requires physical frame "+label,ready.geometry_ready and not ready.ready and not ready.awaiting_physics.is_empty(),ready)
	await physics_frame;await process_frame
	ready=view.readiness(keys)
	check("budgeted edit readiness opens only after physical barrier "+label,ready.ready,ready)
	var x:float=(cx+0.5)*0.5;var z:float=(cz+0.5)*0.5
	var ray:=PhysicsRayQueryParameters3D.create(Vector3(x,15,z),Vector3(x,-3,z))
	var hit:Dictionary=view.get_world_3d().direct_space_state.intersect_ray(ray)
	check("budgeted native mesh collider agrees "+label,not hit.is_empty() and absf(hit.position.y-float(world.surface_height(x,z)))<0.001,{"authority":world.surface_height(x,z),"collision":str(hit.get("position")),"collider_chunk":hit.collider.get_meta("terrain_chunk") if not hit.is_empty() else null})
	derived_phases.append({"label":label,"budget_slices":iterations,"readiness":ready,"stages":view.statistics().stages})

func finish()->void:
	costs.budgeted_phases=derived_phases
	costs.scope="C actual promoted-view budgeted edit policy with the same Runtime.changed/real labor/native collision and cold-restore fixture. Immediate stale-body retirement and physical readiness gate at the vertical seam. No OS/app/Metal, all-actor A runtime gate, natural survival or hard-budget qualification."
	super.finish()
