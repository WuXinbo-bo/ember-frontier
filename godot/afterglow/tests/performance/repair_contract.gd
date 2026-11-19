extends "res://tests/world/environment_mount.gd"
## Real assembly: demand-specific reads and atomic staged region/view equivalence.
const Scheduler=preload("res://scripts/runtime/region_scheduler.gd")
const BuildingView=preload("res://scripts/buildings/building_view.gd")
const DomainDraft=preload("res://scripts/actions/domain_draft.gd")
func dispose_building(view:Node3D)->void:
 var retained:Array=[]
 BuildingView.retain_object_materials(view,retained)
 view.free()
func building_signature(view:Node3D)->Dictionary:
 var rows:Dictionary={}
 for collection:Dictionary in [view.static_nodes,view.objects]:
  for id:String in collection:rows[id]=node_data(collection[id])
 for id:String in view.doors:rows[id]=node_data(view.doors[id].node)
 return rows
func run()->void:
 var args:=OS.get_cmdline_user_args();var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[0]))
 if not decoded.get("ok",false):check("fixture decodes",false);finish(args[1]);return
 var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
 check("actual Native assembly",built.get("ok",false),built.get("code"))
 if not built.ok:finish(args[1]);return
 world=built.world;var rt:RefCounted=built.runtime
 var Policy=preload("res://scripts/presentation/interior_view_policy.gd")
 var original_policy:=GDScript.new();original_policy.source_code=FileAccess.get_file_as_string("res://scripts/presentation/interior_view_policy.gd").replace(".chunk_metadata(id)",".chunk(id)")
 check("original full-cell topology reader compiles",original_policy.reload()==OK)
 var before_policy:RefCounted=original_policy.new();var next_policy:RefCounted=Policy.new()
 check("metadata reader preserves the exact room topology key",before_policy._structure_key(built.services.buildings.current_space())==next_policy._structure_key(built.services.buildings.current_space()))
 var basis:Dictionary=rt.capture_checkpoint()
 var hud:Dictionary=rt.factory_hud_snapshot();var full:Dictionary=rt.factory_ui_snapshot()
 check("HUD preserves real alerts and read summaries",hud.alerts==full.alerts and hud.alert_summary==full.alert_summary)
 check("HUD includes every real member",hud.workforce.members==full.workforce.members)
 check("HUD unrequested detail is explicit",hud.details_state=="not_requested" and hud.workforce.candidates_state=="not_requested")
 check("invalid actors receive no available factory",not rt.factory_hud_snapshot("missing").available and not rt.factory_hud_snapshot("*").available)
 hud.workforce.members.clear();hud.alerts.clear()
 check("HUD DTO is detached and reads preserve authority",not rt.factory_hud_snapshot().workforce.members.is_empty() and basis==rt.capture_checkpoint())
 var display:Dictionary=rt.snapshot();var walking:Dictionary=rt.hud_snapshot();var pack:Dictionary={}
 for row:Dictionary in display.stocks:
  if row.id=="pack:player":pack=row
 check("walking HUD preserves exact pack tools actors and movement",walking.stocks==[pack] and walking.tools.filter(func(t:Dictionary):return t.holderId=="pack:player")==display.tools.filter(func(t:Dictionary):return t.holderId=="pack:player") and walking.actors==display.actors and walking.movement==display.movement)
 var reservation_equal:=true
 for row:Dictionary in display.stocks:
  for item:String in row.items:
   if row.reserved.items[item]!=built.services.production.reserved(row.id,item):reservation_equal=false
 for tool:Dictionary in display.tools:
  if tool.reserved!=built.services.production.tool_unavailable(tool.id):reservation_equal=false
 check("batched display holds equal original per-item and per-tool queries",reservation_equal)
 check("walking HUD skips only unrequested management detail",walking.work_targets.is_empty() and walking.regions.is_empty() and walking.catalog.tool_definitions==display.catalog.tool_definitions)
 var broad_equal:=true;var all_entities:Array=world.entities()
 for i:int in 50:
  var origin:=Vector3(float(i%10)*8-20,30,float(i/10)*8-70)
  var direction:=Vector3(.4,-1,.6).normalized();var end:Vector3=origin+direction*70
  var box:AABB=AABB(origin.min(end),origin.max(end)-origin.min(end)).grow(.001)
  var nearby:AABB=AABB(origin-Vector3.ONE*2.8,Vector3.ONE*5.6)
  var volumes:Array=[BuildingView.Geometry.json_box(box),BuildingView.Geometry.json_box(nearby)]
  var filtered:Array=world.entities_in_any_bounds(volumes);var expected:Array=[]
  for e:Dictionary in all_entities:
   if Data.intersects(e.bounds,volumes[0]) or Data.intersects(e.bounds,volumes[1]):expected.append(e)
  if filtered!=expected:broad_equal=false
  for e:Dictionary in all_entities:
   var hit:Variant=BuildingView.Geometry.aabb(e.bounds).intersects_ray(origin,direction)
   if hit!=null and origin.distance_to(hit)<70 and not filtered.any(func(row:Dictionary):return row.id==e.id):broad_equal=false
 check("ordered local broad phase preserves every actual ray candidate",broad_equal)
 var env:=EnvironmentView.new();root.add_child(env);env.configure({"world":world})
 var view:=BuildingView.new();root.add_child(view);view.configure({"service":built.services.buildings,"runtime":rt});view.set_process(false)
 var prior_nodes:Dictionary={}
 for id:String in view.static_nodes:prior_nodes[id]=view.static_nodes[id].get_instance_id()
 rt.changed.connect(func(change:Dictionary):
  var entities:Dictionary={};var chunks:Dictionary={}
  for op:Dictionary in change.get("world",[]):
   if op.op in ["entity.put","entity.remove"]:entities[op.id]=true
   if op.op in ["chunk.put","chunk.storage","chunk.residency"]:chunks[op.id]=true
  env.on_world_changed({"operations":change.get("world",[]),"entities":entities.keys(),"chunks":chunks.keys()}))
 var jobs:=Scheduler.new();jobs.attach(rt,built.services.buildings,1,built.services.modules)
 var requested:Dictionary=jobs.request(Vector2i(1,0));var result:Dictionary={};var interrupted:=false;var deadline:int=Time.get_ticks_msec()+60000
 while result.is_empty() and Time.get_ticks_msec()<deadline:
  await process_frame
  if jobs._active.has("prepared") and not interrupted:
   check("speculative phases publish no partial region",world.region("R34:1:0").is_empty())
   rt.set_paused(false);rt.tick(.1);rt.set_paused(true);interrupted=true
  result=jobs.poll(0)
 check("staged generation survives live simulation revision",requested.ok and interrupted and result.get("ok",false) and not world.region("R34:1:0").is_empty(),result.get("code"))
 var stable:=true
 for id:String in prior_nodes:
  if not view.static_nodes.has(id) or view.static_nodes[id].get_instance_id()!=prior_nodes[id]:stable=false
 check("additive region retains all original building mesh nodes",stable)
 var fresh:=BuildingView.new();root.add_child(fresh);fresh.configure({"service":built.services.buildings});fresh.set_process(false)
 check("incremental buildings exactly equal fresh geometry materials and transforms",building_signature(view)==building_signature(fresh))
 var envfresh:=EnvironmentView.new();root.add_child(envfresh);envfresh.configure({"world":world,"materials":env.materials})
 compare(env,envfresh,"additive region versus fresh environment")
 envfresh.free();dispose_building(fresh)
 var distant:String="R34:1:0"
 var cold:Dictionary=world.prepare_region_residency(distant,false,world.get_revision())
 check("actual distant residency plan",cold.get("ok",false) and not cold.get("world_changes",[]).is_empty())
 if cold.get("ok",false) and not cold.get("world_changes",[]).is_empty():
  rt.set_paused(false)
  var moved:bool=false
  for direction:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
   var p:Dictionary=rt.actor("player");var budget:Dictionary=rt.movement_budget("player",1.0/60,"walk")
   var to:Dictionary={"x":p.x+direction.x*budget.max_distance,"y":p.y,"z":p.z+direction.y*budget.max_distance,"regionId":p.regionId,"buildingId":p.get("buildingId"),"storeyId":p.get("storeyId")}
   var motion:Dictionary=rt.command({"command_id":"PERF:move:"+str(direction),"kind":"direct_move","actor_id":"player","destination":to,"payload":{"movement_dt":1.0/60,"movement_mode":"walk"}})
   if motion.get("ok",false):moved=true;break
  check("actual movement establishes motion history",moved and not rt._movement_recent.is_empty())
  var motion_before:Dictionary=rt._movement_recent.duplicate(true)
  var router:=preload("res://scripts/input/input_router.gd").new();router.controls_path=args[1]+".controls";root.add_child(router);router.configure(rt)
  for code:int in [KEY_W,KEY_SHIFT]:
   var input:=InputEventKey.new();input.physical_keycode=code;input.pressed=true;input.shift_pressed=code==KEY_SHIFT;router._unhandled_input(input)
  var proof:Dictionary={"blocked":false}
  var weak_runtime:WeakRef=weakref(rt)
  rt.changed.connect(func(change:Dictionary):
   if change.get("world",[]).any(func(op:Dictionary)->bool:return op.get("op") in ["chunk.storage","chunk.residency"]):
    proof.blocked=weak_runtime.get_ref().command({"command_id":"PERF:reentrant","kind":"cancel","actor_id":"player"}).get("code")=="STORAGE_BARRIER")
  var single:Array=[cold.world_changes[0]]
  var cooled:Dictionary=rt.commit_storage_projection({"world_changes":single})
  check("actual one-chunk cooling commits",cooled.get("ok",false))
  check("storage rejects reentrant commands",proof.blocked)
  check("storage preserves held direction/run and actual motion history",router._pressed.has("up") and router._pressed.has("run") and rt._movement_recent==motion_before and not rt.is_paused())
  var input_proof:Dictionary={"count":0}
  router.movement_requested.connect(func(_direction:Vector2,_dt:float):input_proof.count+=1)
  router._profiled_physics_process(1.0/60)
  check("held movement continues after storage without another key-down",input_proof.count==1)
  router.set_modal(true)
  check("real modal still releases held inputs and pauses",router._pressed.is_empty() and rt.is_paused());router.free();rt.set_paused(false)
  var retained:bool=true
  for id:String in prior_nodes:
   if not view.static_nodes.has(id) or view.static_nodes[id].get_instance_id()!=prior_nodes[id]:retained=false
  check("distant residency preserves original building node identities",retained)
  fresh=BuildingView.new();root.add_child(fresh);fresh.configure({"service":built.services.buildings});fresh.set_process(false)
  check("partial cold building view equals full rebuild",building_signature(view)==building_signature(fresh));dispose_building(fresh)
  envfresh=EnvironmentView.new();root.add_child(envfresh);envfresh.configure({"world":world,"materials":env.materials})
  compare(env,envfresh,"partial cooling support versus fresh environment");envfresh.free()
  var warm:Dictionary=world.prepare_region_residency(distant,true,world.get_revision())
  check("actual rewarm commits",warm.get("ok",false) and rt.commit_storage_projection({"world_changes":warm.world_changes}).get("ok",false))
  fresh=BuildingView.new();root.add_child(fresh);fresh.configure({"service":built.services.buildings});fresh.set_process(false)
  check("rewarmed building view equals full rebuild",building_signature(view)==building_signature(fresh));dispose_building(fresh)
  envfresh=EnvironmentView.new();root.add_child(envfresh);envfresh.configure({"world":world,"materials":env.materials})
  compare(env,envfresh,"rewarmed support versus fresh environment");envfresh.free()
 # Explicit C fixture, separate from normal actor admission: a real tree's
 # actual support column becomes cold, then warm. No facts are invented.
 var tree:Dictionary=world.entity(str(env._roots.keys()[0]))
 var cell:=Vector3i(floori(tree.position.x*2),floori((tree.position.y-.001)*2),floori(tree.position.z*2))
 var tree_chunk:String=Data.key(Data.cell_chunk(cell,16))
 var tree_cold:Dictionary=world.prepare_region_residency(str(tree.regionId),false,world.get_revision())
 var tree_ops:Array=tree_cold.get("world_changes",[]).filter(func(op:Dictionary):return op.id==tree_chunk)
 check("isolated tree fixture uses an actual support chunk",tree_ops.size()==1)
 if tree_ops.size()==1:
  var tx:Dictionary=world.prepare_changes(tree_ops,world.get_revision());var changed:Dictionary=world.commit_prepared(tx.capability) if tx.ok else tx
  check("isolated tree support cool transaction",changed.get("ok",false))
  if changed.ok:
   env.on_world_changed(changed.changes)
   check("cold support immediately retires actual tree",not env._roots.has(tree.id))
   envfresh=EnvironmentView.new();root.add_child(envfresh);envfresh.configure({"world":world,"materials":env.materials})
   compare(env,envfresh,"actual tree column cool versus fresh environment");envfresh.free()
   var tree_warm:Dictionary=world.prepare_region_residency(str(tree.regionId),true,world.get_revision())
   tx=world.prepare_changes(tree_warm.world_changes,world.get_revision());changed=world.commit_prepared(tx.capability) if tx.ok else tx
   check("isolated tree support rewarm transaction",changed.get("ok",false))
   if changed.ok:env.on_world_changed(changed.changes)
   check("rewarm restores actual tree",env._roots.has(tree.id))
   envfresh=EnvironmentView.new();root.add_child(envfresh);envfresh.configure({"world":world,"materials":env.materials})
   compare(env,envfresh,"actual tree column warm versus fresh environment");envfresh.free()
 jobs.shutdown();env.free();dispose_building(view);rt.retire();await process_frame
 finish(args[1])
