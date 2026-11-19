extends "res://tests/integration/run_village_supply15.gd"
## Normal chapter-one commands. The caller supplies the live opening runtime and real fuel.
const REGION20="RH-HOME"
const FIELD20="chapter20:potato-field"
const RAW20="r34:raw_water"
const BUCKET20="r34:water_bucket"
const SEED20="r34:potato_seed"
const POTATO20="r34:potato"
const MEAL20="r34:meal_simple"
const PACK20="pack:player"

func supply20(runtime:RefCounted)->bool:
	var plan:Dictionary=runtime.world.extension("generation:"+REGION20)
	var landmarks:Dictionary=plan.get("opening_landmarks",{})
	var well:String=str(landmarks.get("raw_water",""))
	workshop15=runtime._services.modules.instance("r34:generated:RH-HOME:woodwork")
	var present:bool=not well.is_empty() and not workshop15.get("config",{}).get("workbench_id","").is_empty()
	check("chapter opening has a real well and manual workbench",present,landmarks)
	if not present or not supplies20(runtime,landmarks):return false
	var fuel:bool=amount20(runtime,"log")>=3
	check("earlier real felling leaves at least three logs for supply",fuel,runtime.stock(PACK20).get("items",{}))
	if not fuel or not draw20(runtime,well) or not boil20(runtime,well):return false
	if not field20(runtime,plan) or not labor15(runtime,FIELD20,"till"):return false
	for cycle:int in 2:
		var seed_before:float=amount20(runtime,SEED20)
		if not labor15(runtime,FIELD20,"sow"):return false
		var sown:Dictionary=plant_state20(runtime)
		var seed_used:bool=sown.get("stage")=="seedling" and sown.get("seed_reserved")==0 and amount20(runtime,SEED20)==seed_before-(1 if cycle==0 else 0)
		check("first sow spends a seed; second sow uses the retained seed: cycle %d"%(cycle+1),seed_used,sown)
		if not seed_used or not grow20(runtime,well):return false
		var potatoes:float=amount20(runtime,POTATO20)
		if not labor15(runtime,FIELD20,"harvest_crop"):return false
		var harvested:Dictionary=plant_state20(runtime)
		var crop_ok:bool=harvested.get("stage")=="harvested" and harvested.get("seed_reserved")==1 and amount20(runtime,POTATO20)==potatoes+4
		check("four real potatoes and one retained seed: cycle %d"%(cycle+1),crop_ok,harvested)
		if not crop_ok or not cook20(runtime,well):return false
		note(runtime,"chapter20 completed crop and meal cycle %d"%(cycle+1),harvested)
	var meals:float=amount20(runtime,MEAL20)
	var eating:Dictionary=send(runtime,"eat","",{"source_id":PACK20,"item_id":MEAL20})
	var eaten:bool=eating.ok and progress(runtime,50).finished and amount20(runtime,MEAL20)==meals-1
	check("player eats one of the produced potato meals",eaten,eating)
	runtime.tick(.1)
	var flags:Dictionary=runtime.world.extension("r34:gameplay").get("flags",{})
	var recorded:bool=["village_water_collected","village_clean_water","village_crop_harvested","village_food_produced"].all(func(key:String)->bool:return flags.get(key,false))
	check("real supply work records all four chapter progress markers",recorded,flags)
	return eaten and recorded

func amount20(runtime:RefCounted,item:String)->float:
	return float(runtime.stock(PACK20).get("items",{}).get(item,0))

func supplies20(runtime:RefCounted,landmarks:Dictionary)->bool:
	var items:Dictionary={}
	for item:String in [BUCKET20,SEED20]:
		if amount20(runtime,item)<1:items[item]=1
	if not items.is_empty() and not take_source(runtime,str(landmarks.get("starter_supplies","")),items):return false
	var actual_tools:Array=runtime.world.extension("r3:production").get("tools",[])
	if actual_tools.any(func(tool:Dictionary)->bool:return tool.get("kind")=="shovel" and tool.get("holderId")==PACK20 and float(tool.get("durability",0))>0):return true
	var salvage:String=str(landmarks.get("salvage",""))
	var shovel:String=salvage+":tool:shovel"
	if not take_source(runtime,salvage,{},[shovel]):return false
	var held:bool=runtime.tool(shovel).get("holderId")==PACK20 and float(runtime.tool(shovel).get("durability",0))>0
	check("chapter recovery shovel enters the real player pack",held,runtime.tool(shovel))
	return held

func draw20(runtime:RefCounted,well:String)->bool:
	var raw:float=amount20(runtime,RAW20)
	var buckets:float=amount20(runtime,BUCKET20)
	var worked:bool=complete15(runtime,"zonework.draw_water",well)
	var collected:float=amount20(runtime,RAW20)-raw
	var ok:bool=worked and collected>=1 and collected<=2 and amount20(runtime,BUCKET20)==buckets
	check("well work delivers finite raw water and keeps the bucket",ok,collected)
	return ok

func boil20(runtime:RefCounted,well:String)->bool:
	for refill:int in 2:
		if amount20(runtime,RAW20)>=2:break
		if not draw20(runtime,well):return false
	if not care(runtime,40):return false
	var raw:float=amount20(runtime,RAW20)
	var clean:float=amount20(runtime,"water")
	var fuel:float=amount20(runtime,"log")
	var worked:bool=craft15(runtime,"r34:raw_boil_water_v2")
	var paid:bool=worked and amount20(runtime,RAW20)==raw-2 and amount20(runtime,"water")==clean+2 and amount20(runtime,"log")==fuel-1
	check("boiling uses two raw water and one real log for two safe drinks",paid,runtime.stock(PACK20).get("items",{}))
	return paid

func cook20(runtime:RefCounted,well:String)->bool:
	if not care(runtime,40):return false
	if amount20(runtime,"water")<1 and not boil20(runtime,well):return false
	var potatoes:float=amount20(runtime,POTATO20)
	var clean:float=amount20(runtime,"water")
	var fuel:float=amount20(runtime,"log")
	var meals:float=amount20(runtime,MEAL20)
	var worked:bool=craft15(runtime,"r34:cook_potato_v2")
	var paid:bool=worked and amount20(runtime,POTATO20)==potatoes-2 and amount20(runtime,"water")==clean-1 and amount20(runtime,"log")==fuel-1 and amount20(runtime,MEAL20)==meals+3
	check("potato meal uses two tubers, one safe water and one log for three meals",paid,runtime.stock(PACK20).get("items",{}))
	return paid

func field20(runtime:RefCounted,plan:Dictionary)->bool:
	for field:Dictionary in plan.get("landforms",[]):
		if field.get("use")!="field":continue
		var r:Array=field.xz
		for z:int in range(ceili(r[1]*2)+2,floori(r[3]*2)-2,2):
			for x:int in range(ceili(r[0]*2)+2,floori(r[2]*2)-2,2):
				var spec:Dictionary={"kind":"farm","region_id":REGION20,"bounds":{"x0":x,"x1":x+1,"z0":z,"z1":z+1},"policy":{"crop_id":"potato","worker_ids":["player"]}}
				var preview:Dictionary=runtime._services.ecology.preview_zone(spec)
				if not preview.ok or preview.get("cells",[]).is_empty():continue
				var cell:Dictionary=preview.cells[0]
				var feet:Dictionary={"x":(float(cell.x)+.5)*.5,"y":float(cell.y)*.5,"z":(float(cell.z)+.5)*.5,"regionId":REGION20,"buildingId":null,"storeyId":null}
				if not runtime._services.actions.route("player",Geometry.location(runtime.actor("player")),feet).ok:continue
				var created:Dictionary=send(runtime,"zone.create",FIELD20,{"spec":spec})
				check("player creates a reachable plot on the actual generated field",created.ok,created)
				if not created.ok:return false
				plant15=Rules15.plant_id(REGION20,cell)
				return true
	check("generated chapter field includes a reachable farming cell",false)
	return false

func plant_state20(runtime:RefCounted)->Dictionary:
	return runtime.world.extension_entries("r34:ecology","plants",[plant15]).get(plant15,{})

func grow20(runtime:RefCounted,well:String)->bool:
	var started:int=Time.get_ticks_msec()
	var watered:bool=false
	for step:int in 1800:
		var plant:Dictionary=plant_state20(runtime)
		if plant.get("stage")=="mature":
			check("soil reached maturity after one actual seedling watering",watered,plant)
			return watered
		if plant.get("stage")=="seedling" and int(plant.get("moisture",0))<1 and not watered:
			if amount20(runtime,RAW20)<1 and not draw20(runtime,well):return false
			var raw:float=amount20(runtime,RAW20)
			var worked:bool=labor15(runtime,FIELD20,"water")
			watered=worked and amount20(runtime,RAW20)==raw-1
			check("seedling takes exactly one unit of raw water",watered,plant_state20(runtime))
			if not watered:return false
		if step%100==0 and not care(runtime,35):return false
		if Time.get_ticks_msec()-started>180000:break
		runtime.tick(.1)
	check("chapter potatoes mature under the normal simulation clock",false,plant_state20(runtime))
	return false
