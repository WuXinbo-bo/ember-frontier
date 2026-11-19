extends "res://tests/gameplay/factory_zone_opening_processing.gd"
## Natural finite continuation: original pickaxe/terrain labor -> exact stone
## -> original paid module construction. No dismantling/free supplies/fixtures.
const Direct=preload("res://scripts/input/direct_interaction.gd")
var quarry_attempts:Array=[]
var build_choices:Array=[]
var built_ids:Array=[]

func quarry(tool:String)->bool:
	var stone_start:float=float(runtime.actor("player").pack.get("stone_m3",0))
	for spot:Vector2 in [Vector2(52,12),Vector2(49,12),Vector2(52,9),Vector2(49,9)]:
		var hint:Dictionary={"regionId":"RH-HOME","buildingId":null,"storeyId":null,"x":spot.x,"y":0,"z":spot.y}
		var feet:Dictionary=runtime.domain_service("buildings").current_space().standing_point(hint)
		if feet.is_empty():continue
		var route:Dictionary=runtime.domain_service("actions").route("player",G.location(runtime.actor("player")),feet)
		if not route.get("ok",false):continue
		if not await go(feet,"player walks onto original finite quarry supported stance"):return false
		for dz:int in range(-5,6):
			for dx:int in range(-5,6):
				if abs(dx)<2 and abs(dz)<2:continue
				var x:int=floori(spot.x*2)+dx;var z:int=floori(spot.y*2)+dz
				var height:Variant=runtime.world.surface_height((x+.5)*.5,(z+.5)*.5)
				if height==null:continue
				var cell:Dictionary={"x":x,"y":roundi(float(height)*2)-1,"z":z}
				if runtime.world.cell_at(x,cell.y,z)!=3:continue
				var payload:Dictionary=Direct.terrain_payload({"cell":cell,"normal":Vector3.UP},{"brush_cells":1,"height":0,"material":3},"dig",.5)
				payload.merge({"tool_id":tool,"held":true,"requires_hold":true},true)
				var request:Dictionary={"actor_id":"player","command_id":"E:quarry:preview","kind":"terrain","target_id":"","payload":payload}
				var legal:Dictionary=runtime.availability(request)
				quarry_attempts.append({"cell":cell,"availability":legal.get("code"),"reason":legal.get("reason")})
				if not legal.get("ok",false):continue
				if not perform("original visible stone voxel paid pickaxe labor "+str(quarry_attempts.size()),"terrain","",payload):return false
				if float(runtime.actor("player").pack.get("stone_m3",0))>=2:
					check("two cubic metres stone come only from actual paid original voxels",absf(float(runtime.actor("player").pack.stone_m3)-stone_start-2)<.000001)
					return true
	check("original reachable quarry supplies required finite stone",false,{"actor":runtime.actor("player"),"attempts":quarry_attempts})
	return false

func build_one(definition:String,id:String)->bool:
	var hammer:String="r34:generated:RH-HOME:woodwork:tool:hammer"
	var module_service:RefCounted=runtime.domain_service("modules")
	var choice:Dictionary={}
	for z:int in [36,44,24,52,18]:
		if not choice.is_empty():break
		for x:int in [36,44,52,28,20]:
			var height:Variant=runtime.world.surface_height(x,z)
			if height==null:continue
			var payload:Dictionary={"definition_id":definition,"position":{"regionId":"RH-HOME","x":float(x),"y":float(height),"z":float(z)},"quarter_turn":0,"source_id":"pack:player","tool_id":hammer}
			var preview:Dictionary=module_service.preview({"kind":"module.plan","actor_id":"player","target_id":id,"payload":payload})
			if not preview.get("ok",false):continue
			for port:Dictionary in preview.get("ports",[]):
				if port.purpose not in ["work","repair","service","input"]:continue
				var route:Dictionary=runtime.domain_service("actions").route("player",G.location(runtime.actor("player")),port.location)
				if route.get("ok",false):choice={"payload":payload,"port":port.location,"preview":preview};break
			if not choice.is_empty():break
	check("real unchanged landscape offers legal paid site "+id,not choice.is_empty())
	if choice.is_empty():return false
	build_choices.append(choice)
	if not await go(choice.port,"builder physically reaches real work port "+id):return false
	var before:Dictionary=runtime.actor("player").pack
	if not perform("original hammer labor completes paid building "+id,"module.plan",id,choice.payload):return false
	var m:Dictionary=module_service.instance(id)
	var paid:bool=m.get("status")=="operational" and not m.get("paid_cost",{}).is_empty()
	for item:String in m.get("paid_cost",{}):paid=paid and absf(float(before.get(item,0))-float(runtime.actor("player").pack.get(item,0))-float(m.paid_cost[item]))<.000001
	check("exact finite original cost and operational receipt "+id,paid,m)
	if paid:built_ids.append(id)
	return paid

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];options=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var native:=Native.new()
	var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	check("actual paid study and three-log processing final mounts unchanged",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime;initial=runtime.capture_checkpoint();elapsed_start=runtime.clock()
	note("original-natural-processed-boards-input")
	check("twelve original processed boards and unchanged real blocked crop job",runtime.actor("player").pack.get("timber")==12 and runtime.domain_service("zonework").state().jobs.has("workforce:execute:village-resident:2715"))
	var pick:String=rack+":tool:pickaxe"
	if not await take_stock(rack,{},[pick]):return finish()
	if not await take_stock(source_tools,{"timber":8,"scrap":6}):return finish()
	if not await take_stock(source_home,{"cloth":2}):return finish()
	if not await quarry(pick):return finish()
	note("original-actual-quarry-two-cubic-metres-paid")
	if not cold("actual12-quarry-before-build-cold"):return finish()
	if not await build_one("r34.module.water_low_v1.mechanism-v2","E:actual12:water-low"):return finish()
	if not await build_one("r34.module.canteen_low_v1.mechanism-v2","E:actual12:canteen-low"):return finish()
	note("finite-material-water-and-canteen-actually-built")
	cold("actual12-built-water-canteen-final-cold")
	check("construction uses original people HP consent and no source grants",runtime.facts().actors.size()==3 and initial.facts.actors.all(func(a:Dictionary)->bool:return runtime.actor(a.id).hp==a.hp) and ["village-resident","repair-resident"].all(func(id:String)->bool:return runtime.actor(id).relationship.consent) and quantities().get("r34:water_bucket")==1 and quantities().get("r34:potato_seed")==4)
	finish()

func finish()->void:
	if runtime!=null:
		FileAccess.open(output+"/construction-evidence.json",FileAccess.WRITE).store_string(JSON.stringify({"quarry_attempts":quarry_attempts,"build_choices":build_choices,"built_ids":built_ids},"\t",true,true))
		save("actual12-built-water-canteen-final")
	super.finish()
