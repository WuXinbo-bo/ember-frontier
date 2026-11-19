extends "res://tests/world/factory_joint.gd"
## Shared normal-source route. Calling this never relocates actors, injects
## supplies, edits permissions, or completes a later event by fixture.
const Direct=preload("res://scripts/input/direct_interaction.gd")
var sequence:int=0

func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	return runtime.command({"command_id":"r34:c:normal:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination})

func progress(runtime:RefCounted,limit:int=1200)->Dictionary:
	var start:float=runtime.clock();var i:int=0
	while runtime.actor("player").get("intent")!=null and i<limit:
		runtime.tick(0.1);i+=1
	return {"finished":runtime.actor("player").get("intent")==null,"sim_seconds":runtime.clock()-start,"iterations":i,"actor":runtime.actor("player")}

func walk(runtime:RefCounted,at:Dictionary)->Dictionary:
	var request:Dictionary=send(runtime,"walk","",{},at)
	if not request.ok:return request
	var completed:Dictionary=progress(runtime)
	completed.ok=completed.finished and Geometry.point(runtime.actor("player")).distance_to(Geometry.point(at))<0.2
	return completed

func brush(cell:Dictionary,operation:String,tool:String,width:int=1,height:float=0.0,material:int=3)->Dictionary:
	var p:Dictionary=Direct.terrain_payload({"cell":cell,"normal":Vector3.UP},{"brush_cells":width,"height":height,"material":material},operation,0.5)
	p.merge({"tool_id":tool,"held":true,"requires_hold":operation!="fill"},true)
	return p

func normal_tools(generation_contract:Dictionary={},normal_seed:int=713)->Dictionary:
	var made:Dictionary=Assembly.prepare(Factory.generate(normal_seed,Modules.generation_profiles(),generation_contract))
	check("actual new-world normal opening composes",made.ok,made.get("reason"))
	if not made.ok:return {"ok":false}
	var native:=Native.new();var built:Dictionary=native._assemble(made.capture);native.free()
	check("actual normal runtime configures",built.ok,built.get("reason"))
	if not built.ok:return {"ok":false}
	var runtime:RefCounted=built.runtime;var world:RefCounted=built.world
	var query:RefCounted=built.services.buildings.current_space()
	var tool_stock:String="r34:generated:RH-HOME:woodwork:stock:tools"
	var actual_walk:Dictionary=walk(runtime,runtime.stock(tool_stock).location)
	check("normal actor walks from actual spawn to real hand workshop source",actual_walk.get("ok",false),actual_walk)
	if not actual_walk.get("ok",false):return {"ok":false}
	var axe:String="r34:generated:RH-HOME:woodwork:tool:salvaged_axe"
	var searched:Dictionary=send(runtime,"search",tool_stock)
	if searched.ok:progress(runtime)
	check("normal hand workshop container is actually searched",searched.ok and runtime.stock(tool_stock).searched,searched)
	var taken:Dictionary=send(runtime,"take",tool_stock,{"tool_ids":[axe]})
	check("normal finite workshop transfers actual old axe once",taken.ok and runtime.tool(axe).holderId=="pack:player",taken)
	if not taken.ok:return {"ok":false}
	var anchor:Dictionary=world.extension("generation:RH-HOME").content_anchors[0]
	var yard_stock:String=str(anchor.id)+":container"
	var yard:Dictionary=anchor.position.duplicate(true);yard.z-=1.2
	yard=query.standing_point(yard)
	actual_walk=walk(runtime,yard) if not yard.is_empty() else {"ok":false,"reason":"no stockyard use feet"}
	check("normal actor physically reaches finite recovery stockyard",actual_walk.get("ok",false),actual_walk)
	if not actual_walk.get("ok",false):return {"ok":false}
	var shovel:String=yard_stock+":tool:shovel";var pickaxe:String=yard_stock+":tool:pickaxe"
	searched=send(runtime,"search",yard_stock)
	if searched.ok:progress(runtime)
	check("normal recovery container is actually searched",searched.ok and runtime.stock(yard_stock).searched,searched)
	taken=send(runtime,"take",yard_stock,{"tool_ids":[shovel,pickaxe]})
	check("normal stockyard source transfers real shovel and pickaxe",taken.ok and runtime.tool(shovel).holderId=="pack:player" and runtime.tool(pickaxe).holderId=="pack:player",taken)
	if not taken.ok:return {"ok":false}
	return {"ok":true,"built":built,"runtime":runtime,"world":world,"query":query,"axe":axe,"shovel":shovel,"pickaxe":pickaxe,"tool_stock":tool_stock,"yard_stock":yard_stock}
