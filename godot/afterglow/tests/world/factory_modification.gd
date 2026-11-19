extends "res://tests/world/factory_normal_path.gd"
## Actual normal finite sources and official command/fixed-step path. No
## actor relocation, fabricated tools/materials, app, cursor or renderer.
const Fields=preload("res://scripts/environment/field_surfaces.gd")
const EnvironmentView=preload("res://scripts/environment/environment_view.gd")
func generation_contract()->Dictionary:return {}
func run()->void:
	var opening:Dictionary=normal_tools(generation_contract())
	if not opening.ok:return finish()
	var built:Dictionary=opening.built;var runtime:RefCounted=opening.runtime;var world:RefCounted=opening.world
	var query:RefCounted=opening.query
	var axe:String=opening.axe;var shovel:String=opening.shovel;var pickaxe:String=opening.pickaxe
	var actual_walk:Dictionary={};var native:Node
	var at:Dictionary=_location(world,55.0,15.0);at=query.standing_point(at)
	actual_walk=walk(runtime,at) if not at.is_empty() else {"ok":false}
	check("normal walk reaches supported edit approach",actual_walk.get("ok",false),actual_walk)
	if not actual_walk.get("ok",false):return finish()
	var top:float=world.surface_height(55.75,15.75)
	var cell:Dictionary={"x":111,"y":roundi(top*2)-1,"z":31}
	var hit:Dictionary=Queries.pick(world,Vector3(55.75,top+4,15.75),Vector3(55.75,top-2,15.75))
	check("actual selected stone seam cell has stable world revision",hit.get("cell")==cell and hit.get("target_id")=="terrain:111:%d:31"%cell.y and hit.world_revision==world.get_revision(),hit)
	var key:String=Data.key(Data.cell_chunk(Vector3i(cell.x,cell.y,cell.z),16))
	var original:Dictionary=Mesher.build(world,key)
	var dig:Dictionary=brush(cell,"dig",pickaxe,2)
	var started:Dictionary=send(runtime,"terrain",hit.target_id,dig)
	check("normal two-cell real input starts dig across neighbor chunks",started.ok,started)
	if not started.ok:return finish()
	for i in 3:runtime.tick(0.1)
	var elapsed:float=runtime.actor("player").intent.elapsed;var clock:float=runtime.clock()
	runtime.set_paused(true);runtime.tick(1.0)
	check("global pause preserves actual terrain intent and clock",runtime.clock()==clock and runtime.actor("player").intent.elapsed==elapsed)
	runtime.set_paused(false)
	var released:Dictionary=send(runtime,"held","",{"held":false})
	for i in 4:runtime.tick(0.1)
	check("released terrain hold does not progress or alter cells",released.ok and runtime.actor("player").intent.elapsed==elapsed and world.cell_at(cell.x,cell.y,cell.z)!=0)
	send(runtime,"held","",{"held":true})
	var completed:Dictionary=progress(runtime,150)
	var all_dug:bool=true
	for c:Dictionary in dig.edit.cells:all_dug=all_dug and world.cell_at(c.x,c.y,c.z)==0
	check("real fixed-step dig settles every selected seam cell and finite stone",completed.finished and all_dug and is_equal_approx(float(runtime.actor("player").pack.get("stone_m3",0)),0.5),completed)
	var modified:Dictionary=Mesher.build(world,key)
	check("actual derived terrain arrays follow modified authority",original!=modified)
	var mesh:ArrayMesh=Mesher.mesh(modified)
	var shape:ConcavePolygonShape3D=mesh.create_trimesh_shape()
	check("real native collision derives the same updated triangle faces",not shape.get_faces().is_empty() and shape.get_faces().size()==mesh.get_faces().size())
	var below:Dictionary=cell.duplicate(true);below.y-=1
	var fill:Dictionary=brush(below,"fill",pickaxe,2)
	var filled:Dictionary=send(runtime,"terrain","",fill)
	check("face-adjacent two-cell fill uses real recovered material",filled.ok,filled)
	if not filled.ok:return finish()
	completed=progress(runtime,150)
	var all_filled:bool=true
	for c:Dictionary in fill.edit.cells:all_filled=all_filled and world.cell_at(c.x,c.y,c.z)==3
	check("real fill restores all four seam cells without duplicating material",completed.finished and all_filled and is_zero_approx(float(runtime.actor("player").pack.get("stone_m3",0))),completed)
	var single:Dictionary=brush(cell,"dig",pickaxe)
	var final_edit:Dictionary=send(runtime,"terrain","",single)
	if final_edit.ok:completed=progress(runtime,50)
	check("separate final edit leaves persistent changed fact",final_edit.ok and world.cell_at(cell.x,cell.y,cell.z)==0,final_edit)
	# Natural soil uses the normal shovel; never add a fake dual-quality tool
	# to make a stone quarry support an inappropriate leveling operation.
	at=_location(world,41.5,20.25);at=built.services.buildings.current_space().standing_point(at)
	actual_walk=walk(runtime,at) if not at.is_empty() else {"ok":false}
	check("normal walk reaches soil leveling approach",actual_walk.get("ok",false),actual_walk)
	if not actual_walk.get("ok",false):return finish()
	var soil_top:float=world.surface_height(42.25,20.25)
	var soil_cell:Dictionary={"x":84,"y":roundi(soil_top*2)-1,"z":40}
	var level:Dictionary=brush(soil_cell,"level",shovel,2,soil_top-0.5,2)
	var leveled:Dictionary=send(runtime,"terrain","",level)
	check("real half-metre soil leveling starts with normal shovel",leveled.ok,leveled)
	if not leveled.ok:return finish()
	for i in 3:runtime.tick(0.1)
	var cancelled:Dictionary=send(runtime,"cancel")
	check("normal cancel preserves uncommitted soil and material",cancelled.ok and runtime.actor("player").intent==null and world.surface_height(42.25,20.25)==soil_top,cancelled)
	leveled=send(runtime,"terrain","",level)
	if leveled.ok:completed=progress(runtime,150)
	var actual_level:bool=leveled.ok and completed.finished
	for z in range(40,42):
		for x in range(84,86):actual_level=actual_level and world.surface_height((x+0.5)*0.5,(z+0.5)*0.5)==soil_top-0.5
	check("actual four soil columns reach the same half-metre target",actual_level,completed)
	var trees:Array=world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a.position).distance_to(Geometry.point(runtime.actor("player")))<Geometry.point(b.position).distance_to(Geometry.point(runtime.actor("player"))))
	if trees.is_empty():check("normal finite forest has an actual tree",false);return finish()
	var tree:Dictionary=trees[0];var dropped:String=tree.data.outputId
	var harvest:Dictionary=send(runtime,"harvest",str(tree.id),{"direct":false,"tool_ids":[axe]})
	check("normal old axe approaches actual generated tree",harvest.ok,harvest)
	if harvest.ok:completed=progress(runtime,700)
	check("actual generated tree becomes stump with finite real log yield",harvest.ok and completed.finished and world.entity(str(tree.id)).data.harvest.phase=="stump" and runtime.stock(dropped).items.get("log",0)==3,completed)
	var sites:Array=world.extension("generation:RH-VILLAGE").get("regional_sites",[])
	check("normal current world has actual adopted regional site",sites.size()==1)
	if sites.size()!=1:return finish()
	var site:Dictionary=sites[0]
	actual_walk=walk(runtime,site.survey_point)
	check("normal actor walks from real forest through shared region to survey",actual_walk.get("ok",false),actual_walk)
	if not actual_walk.get("ok",false):return finish()
	var surveyed:Dictionary=send(runtime,"settlement.survey","",{"site_id":site.id})
	var accepted:Dictionary=send(runtime,"settlement.begin_route_work","",{"site_id":site.id,"accept_risk":true}) if surveyed.ok else surveyed
	check("normal site survey and informed risk uses E actual rule",surveyed.ok and accepted.ok,{"survey":surveyed,"risk":accepted})
	if not accepted.ok:return finish()
	var before:Dictionary=site.goal_corridor.approach_before;var after:Dictionary=site.goal_corridor.approach_after
	var toward:Vector3=(Geometry.point(after)-Geometry.point(before)).normalized()
	at=before.duplicate(true);at.x+=toward.x*1.25;at.z+=toward.z*1.25
	at=built.services.buildings.current_space().standing_point(at)
	actual_walk=walk(runtime,at) if not at.is_empty() else {"ok":false}
	check("normal actor approaches actual visible stone face",actual_walk.get("ok",false),actual_walk)
	if not actual_walk.get("ok",false):return finish()
	var start_stone:float=float(runtime.actor("player").pack.get("stone_m3",0));var removed:int=0;var blocked:Dictionary={}
	# Highest exposed cells first, real reach/LOS/tool and fixed-step costs on
	# each command. No direct voxel fixtures or special event rewards.
	var remaining:Array=site.obstacle_cells.duplicate(true)
	remaining.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.y>b.y if a.y!=b.y else Geometry.point(a).distance_to(Geometry.point(runtime.actor("player")))<Geometry.point(b).distance_to(Geometry.point(runtime.actor("player"))))
	for c:Dictionary in remaining:
		var p:Dictionary=brush({"x":c.x,"y":c.y,"z":c.z},"dig",pickaxe)
		var worked:Dictionary=send(runtime,"terrain","",p)
		if not worked.ok:blocked={"cell":c,"receipt":worked,"actor":runtime.actor("player")};break
		completed=progress(runtime,40)
		if not completed.finished or world.cell_at(c.x,c.y,c.z)!=0:blocked={"cell":c,"progress":completed};break
		removed+=1
	check("normal recovered pickaxe clears every actual regional stone cell",removed==24,blocked)
	check("regional clearing yields only exact physical stone volume",removed==24 and is_equal_approx(float(runtime.actor("player").pack.get("stone_m3",0))-start_stone,3.0))
	check("normal clearing restores actual direct road body movement",removed==24 and built.services.buildings.current_space().walk("player",before,after).ok)
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	native=Native.new();var restored:Dictionary=native._assemble(decoded.capture) if decoded.ok else decoded;native.free()
	check("whole Native cold reassembly retains actual changed cells tools and pack",restored.ok and raster_digest(restored.world.snapshot())==raster_digest(world.snapshot()) and Data.json_equal(restored.runtime.actor("player").pack,runtime.actor("player").pack) and restored.runtime.tool(pickaxe).holderId=="pack:player",restored.get("reason"))
	if restored.ok:check("cold revisit preserves actual tree stump and exact finite drops",restored.world.entity(str(tree.id)).data.harvest.phase=="stump" and restored.runtime.stock(dropped).items.get("log",0)==3)
	if restored.ok:check("cold revisit retains actual informed site work and removed stones",site.obstacle_cells.all(func(c:Dictionary)->bool:return restored.world.cell_at(c.x,c.y,c.z)==0) and restored.world.extension("r34:gameplay").regional_objectives[site.id].risk_accepted)
	if restored.ok:
		var replay:Dictionary=Factory.prepare_region_draft(restored.world,Factory.draft_region_request(Factory.region_generation_input(restored.world,Modules.generation_profiles()),Vector2i.ZERO),restored.world.get_revision())
		check("edited region revisit never regenerates terrain or restocks sources",replay.ok and replay.already_generated and replay.world_changes.is_empty() and replay.initial_stocks.is_empty() and Modules.new().prepare_generation(restored.world).initial_tools.is_empty())
	costs={"scope":"actual normal command route; no physical cursor or formal macOS acceptance","logical_seconds":runtime.clock(),"final_world_revision":world.get_revision(),"raster_sha256":raster_digest(world.snapshot())}
	var args:Array=OS.get_cmdline_user_args()
	if not args.is_empty() and encoded.ok:FileAccess.open(str(args[0]).get_base_dir()+"/actual-normal-modified.native.json",FileAccess.WRITE).store_string(encoded.text)
	finish()
