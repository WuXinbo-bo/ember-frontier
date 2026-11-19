extends "res://tests/world/settlement_joint.gd"
## New-version actual A/B composition, body routes, peripheral facts and labor.
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Terrain=preload("res://scripts/terrain/terrain_service.gd")
const TerrainView=preload("res://scripts/terrain/terrain_view.gd")
const Queries=preload("res://scripts/terrain/terrain_queries.gd")
const Data=preload("res://scripts/world/world_data.gd")
func install_region(world:RefCounted,coord:Vector2i)->Dictionary:
	var result:Dictionary=OldGenerator.prepare_region(world,coord,Building.generation_profiles(),world.get_revision())
	if not result.ok or result.already_generated:return result
	var start:=Time.get_ticks_usec();var draft:Dictionary=world.prepare_changes(result.world_changes,world.get_revision())
	costs["prepare_"+str(coord)]=(Time.get_ticks_usec()-start)/1000.0
	if not draft.ok:return draft
	var committed:Dictionary=world.commit_prepared(draft.capability)
	return result if committed.ok else committed
func region_signature(world:RefCounted,region_id:String)->String:
	var rows:Array=[];var region:Dictionary=world.region(region_id)
	var keys:Array=world.chunk_keys();keys.sort()
	for key:String in keys:
		var c:Dictionary=world.chunk(key)
		var p:Dictionary={"x":(c.coord.x+0.5)*8,"y":0,"z":(c.coord.z+0.5)*8}
		if Data.contains(region.bounds,p):rows.append([key,PackedInt32Array(c.cells).to_byte_array()])
	var entities:Array=world.entities(region_id);entities.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.id<b.id)
	for e:Dictionary in entities:e.erase("revision")
	return var_to_bytes([rows,JSON.stringify(entities,"",true,true),JSON.stringify(world.extension("generation:"+region_id),"",true,true)]).hex_encode().sha256_text()
func run()->void:
	var profiles:Array=Building.generation_profiles();var primary:RefCounted;var primary_facts:Dictionary={}
	for seed_value:int in [713,2026]:
		var assembled:Dictionary=Assembly.prepare(Landscape.generate(seed_value,profiles))
		check("new rural3 actual A/B complete composition seed "+str(seed_value),assembled.ok,assembled.get("reason"))
		if not assembled.ok:return finish()
		var world:=State.new();world.load_snapshot(assembled.capture.world)
		var building:=Building.new();var runtime:=Runtime.new()
		# Deliberate isolated road-start fixture. OS birth/open-door and full NPC
		# interaction remain A's same-package acceptance, never claimed by this.
		var facts:Dictionary=assembled.capture.facts.duplicate(true)
		facts.actors=[actor_at(world.extension("generation:RH-HOME").anchors.arrival)]
		var configured:Dictionary=runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"terrain":Terrain.new(),"actions":Actions.new(),"production":Production.new()}})
		check("same runtime accepts actual assembled new heights seed "+str(seed_value),configured.ok)
		walk_paths(world,building,"rural3 seed "+str(seed_value)+" full family graph")
		var route:Dictionary=walk_home_to_village(runtime,world)
		check("actual direct-move runtime follows old-home to village route seed "+str(seed_value),route.ok,route)
		if seed_value==713:primary=world;primary_facts=runtime.facts()
	var east:=install_region(primary,Vector2i(1,0));var west:=install_region(primary,Vector2i(-1,0))
	check("actual positive and negative peripheral coordinates commit new version",east.ok and west.ok and primary.regions().size()==4,{"east":east.get("cost",east.get("reason")),"west":west.get("cost",west.get("reason"))})
	if not east.ok or not west.ok:return finish()
	var reverse:=State.new();reverse.load_snapshot(Landscape.generate(713,profiles))
	var a:=install_region(reverse,Vector2i(-1,0));var b:=install_region(reverse,Vector2i(1,0))
	check("opposite preparation order preserves exact peripheral cells IDs plans",a.ok and b.ok and region_signature(primary,"R2:1:0")==region_signature(reverse,"R2:1:0") and region_signature(primary,"R2:-1:0")==region_signature(reverse,"R2:-1:0"))
	var max_seam:=0.0
	for edge:float in [0,64]:
		for z in 128:
			max_seam=maxf(max_seam,absf(primary.surface_height(edge-0.25,(z+0.5)*0.5)-primary.surface_height(edge+0.25,(z+0.5)*0.5)))
	check("new organic grade keeps positive negative border within one cell",max_seam<=0.5,max_seam)
	var world:RefCounted=primary
	var tree:Dictionary=world.entities("R2:1:0").filter(func(e:Dictionary)->bool:return e.kind=="tree")[0]
	var p:Dictionary=tree.position;var actor:Dictionary=actor_at({"x":p.x+1.75,"y":world.surface_height(p.x+1.75,p.z),"z":p.z});actor.regionId=tree.regionId
	# On a real half-metre contour the 0.52m body can span a higher adjacent
	# tread. Resolve the isolated fixture with the production full-body query,
	# exactly as real movement does, rather than inserting an invalid actor at
	# the centre column's lower Y and blaming its later safety rejection.
	var labor_building:=Building.new()
	labor_building.geometry.configure(JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json")))
	var original_start:Dictionary=actor.duplicate(true)
	var standing:Dictionary=labor_building.space(world).standing_point(actor)
	check("peripheral labor fixture starts at real complete-body supported feet",not standing.is_empty(),{"center_column_fixture":original_start,"production_standing":standing})
	if standing.is_empty():return finish()
	actor.merge(standing,true)
	var prod:Dictionary=world.extension("r3:production")
	prod.tools.append_array([{"id":"test:r3axe","kind":"salvaged_axe","holderId":"pack:player","durability":100.0},{"id":"test:r3shovel","kind":"shovel","holderId":"pack:player","durability":100.0,"qualities":{"shovel":1}}])
	var draft:Dictionary=world.prepare_changes([{"op":"extension.set","id":"r3:production","before_exists":true,"before":world.extension("r3:production"),"after":prod}],world.get_revision())
	if draft.ok:world.commit_prepared(draft.capability)
	# Keep every actual A/B holder/container from complete composition. Replacing
	# them with only new tree drops would invalidate existing tools at first use.
	var runtime:=Runtime.new();var facts:Dictionary=primary_facts.duplicate(true);facts.actors=[actor]
	for stock:Dictionary in OldGenerator.empty_resource_stocks(world):
		if not facts.stocks.any(func(s:Dictionary)->bool:return s.id==stock.id):facts.stocks.append(stock)
	var configured:Dictionary=runtime.configure({"world":world,"facts":facts,"services":{"terrain":Terrain.new(),"buildings":labor_building,"production":Production.new(),"actions":Actions.new()}})
	check("peripheral revised tree uses sole real runtime labor facts",configured.ok)
	var harvest:Dictionary=runtime.command({"command_id":"r3:harvest","actor_id":"player","kind":"harvest","target_id":tree.id,"payload":{"tree_id":tree.id,"output_id":tree.data.outputId,"tool_ids":["test:r3axe"],"held":true}})
	if harvest.ok:
		for i in 280:runtime.tick(0.1)
	check("actual three-species tree harvest persists stump and only real log drops",harvest.ok and world.entity(tree.id).data.harvest.phase=="stump" and runtime.stock(tree.data.outputId).items.get("log",0)==3,harvest)
	var cx:int=floori((actor.x+0.5)*2);var cz:int=floori((actor.z+0.5)*2);var y:int=roundi(world.surface_height((cx+0.5)*0.5,(cz+0.5)*0.5)*2)-1
	var cell:Dictionary={"x":cx,"y":y,"z":cz};var hit:Dictionary=Queries.pick(world,Vector3((cx+0.5)*0.5,y*0.5+5,(cz+0.5)*0.5),Vector3((cx+0.5)*0.5,y*0.5-1,(cz+0.5)*0.5))
	check("new-height stable DDA cell identifies authoritative terrain",hit.get("target_id")=="terrain:%d:%d:%d"%[cx,y,cz],hit)
	var view:=TerrainView.new();root.add_child(view);view.configure({"world":world});view.set_process(false)
	var key:=Data.key(Data.cell_chunk(Vector3i(cx,y,cz),16));view._rebuild(key)
	await physics_frame;await process_frame
	var ray:=PhysicsRayQueryParameters3D.create(Vector3((cx+0.5)*0.5,15,(cz+0.5)*0.5),Vector3((cx+0.5)*0.5,-3,(cz+0.5)*0.5))
	var collision:Dictionary=view.get_world_3d().direct_space_state.intersect_ray(ray)
	check("actual native collider agrees with new authoritative voxel height",not collision.is_empty() and absf(collision.position.y-(y+1)*0.5)<0.001,str(collision.get("position")))
	view.free()
	var dig:Dictionary=runtime.command({"command_id":"r3:dig","actor_id":"player","kind":"terrain","payload":{"edit":{"operation":"dig","cells":[cell]},"tool_id":"test:r3shovel"}})
	if dig.ok:
		for i in 100:runtime.tick(0.1)
	check("actual new-height dig conserves soil volume",dig.ok and world.cell_at(cx,y,cz)==0 and runtime.actor("player").pack.get("soil_m3",0)==0.125,dig)
	var fill:Dictionary=runtime.command({"command_id":"r3:fill","actor_id":"player","kind":"terrain","payload":{"edit":{"operation":"fill","material":2,"cells":[cell]},"tool_id":"test:r3shovel"}})
	if fill.ok:
		for i in 100:runtime.tick(0.1)
	check("actual new-height fill consumes same soil and restores selected cell",fill.ok and world.cell_at(cx,y,cz)==2 and runtime.actor("player").pack.get("soil_m3",0)==0,fill)
	var saved:Dictionary=Codec.encode_checkpoint(world.snapshot(),{"runtime":runtime.facts()},"test:rural3:peripheral")
	var decoded:Dictionary=Codec.decode_checkpoint(saved.envelope) if saved.ok else saved
	var restored:=State.new();var loaded:Dictionary=restored.load_snapshot(decoded.state) if decoded.ok else decoded
	check("same codec restores peripheral edit stump and actual log stock",loaded.ok and restored.cell_at(cx,y,cz)==2 and restored.entity(tree.id).data.harvest.phase=="stump" and decoded.extensions.runtime.stocks.filter(func(s:Dictionary)->bool:return s.id==tree.data.outputId)[0].items.get("log",0)==3,loaded)
	var repeat:Dictionary=OldGenerator.prepare_region(restored,Vector2i(1,0),profiles)
	check("cold revisit returns original plan with no regeneration or replenishment",repeat.ok and repeat.already_generated and repeat.world_changes.is_empty() and repeat.initial_stocks.is_empty() and not restored.is_cell_resident(cx,y,cz))
	finish()
