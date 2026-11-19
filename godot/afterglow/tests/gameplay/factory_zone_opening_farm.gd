extends "res://tests/gameplay/factory_zone_opening_work.gd"
## Continue actual autonomous finite forestry. Original player staging is
## already paid; NPC farming/water/log hauling use only E and B/C authorities.
var field_id:String=""
var raw_zone:String="E:actual12:raw-source"
var setup:Dictionary={}

func field()->Dictionary:
	return runtime.domain_service("ecology").state().plants.get(field_id,{})

func setup_farm()->bool:
	for cell:Vector2i in [Vector2i(76,92),Vector2i(78,92),Vector2i(80,92),Vector2i(76,96),Vector2i(70,90),Vector2i(84,92),Vector2i(64,80)]:
		var spec:Dictionary={"kind":"farm","region_id":"RH-HOME","bounds":{"x0":cell.x,"z0":cell.y,"x1":cell.x+1,"z1":cell.y+1},"policy":{"crop_id":"potato","priority":5,"worker_ids":["village-resident"],"source_stock_id":rack,"target_stock_id":rack}}
		if not create_zone(farm,spec):continue
		var rows:Array=runtime.domain_service("zonework").work_candidates("village-resident")
		for c:Dictionary in rows:
			if c.zone_id==farm and c.kind=="zonework" and c.operation=="till":field_id=str(c.job.target_id);setup.field=c;return true
		send_to("zone.cancel",farm)
	return false

func setup_water()->bool:
	for e:Dictionary in runtime.world.entities("RH-HOME"):
		if e.get("data",{}).get("raw_water_source",{}).is_empty():continue
		var x:int=floori(float(e.position.x)*2);var z:int=floori(float(e.position.z)*2)
		var spec:Dictionary={"kind":"forage","region_id":"RH-HOME","bounds":{"x0":x-4,"z0":z-4,"x1":x+5,"z1":z+5},"policy":{"priority":1,"worker_ids":["village-resident"],"source_stock_id":rack,"target_stock_id":rack}}
		setup.water_preview=runtime.zone_preview(spec)
		if not create_zone(raw_zone,spec):continue
		setup.source=e;return true
	return false

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];options=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var native:=Native.new()
	var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	check("actual autonomous forest success mounts without grants",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime;initial=runtime.capture_checkpoint();elapsed_start=runtime.clock()
	note("actual-forest-finite-input")
	var drops:Array=runtime.facts().stocks.filter(func(s:Dictionary)->bool:return s.id.ends_with(":drops") and float(s.items.get("log",0))>=3)
	check("only actually felled three logs exist at original tree",drops.size()==1,drops)
	if drops.size()!=1:return finish()
	var moved:Dictionary=send_to("logistics.create","",{"source_id":drops[0].id,"destination_id":rack,"items":{"log":3},"repeat":false})
	check("original logistics config reserves only original real felled logs",moved.get("ok",false),moved)
	if not moved.get("ok",false):return finish()
	for row:Dictionary in runtime.world.extension("r34:logistics").tasks:
		if row.source_id==drops[0].id and row.destination_id==rack:task_id=row.id
	var planted:bool=setup_farm();var sourced:bool=setup_water()
	check("actual soil admits single farm and real source admits water work",planted and sourced,setup)
	if not planted or not sourced:return finish()
	var seen_supply:bool=false;var seen_field:bool=false;var seen_draw:bool=false;var hauling:bool=false;var active_cold:bool=false
	for i:int in 2800:
		tick()
		for id:String in ["village-resident","repair-resident"]:
			var a:Dictionary=runtime.actor(id)
			if not a.get("intent") is Dictionary:continue
			if a.intent.get("kind")=="zone_supply":seen_supply=true
			if a.intent.get("owner")=="zonework":
				seen_field=true
				var work:Dictionary=runtime.domain_service("zonework").state().jobs.get(str(a.intent.get("work_id","")),{})
				if work.get("job",{}).get("kind")=="draw_raw_water":seen_draw=true
			if a.intent.get("kind")=="haul" and float(a.pack.get("log",0))>0:
				hauling=true
				if not active_cold:active_cold=cold("actual12-forest-log-carrying-cold")
		if field().get("stage") in ["seedling","growing"] and float(runtime.stock(rack).items.get("r34:raw_water",0))>=1 and float(runtime.stock(rack).items.get("log",0))>=3:break
	check("E really fetches original shovel seed and bucket then performs field and source work",seen_supply and seen_field and seen_draw,{"field":field(),"actors":runtime.facts().actors,"candidates":runtime.domain_service("zonework").work_candidates("village-resident")})
	check("original NPC custody walks original three logs to real container across cold",hauling and active_cold and runtime.stock(drops[0].id).items.get("log")==0 and runtime.stock(rack).items.get("log")==3,runtime.world.extension("r34:logistics"))
	check("original seed really sown once with finite raw water delivered by NPC",field().get("stage") in ["seedling","growing"] and runtime.stock(rack).items.get("r34:potato_seed")==0 and quantities().get("r34:potato_seed")==3 and quantities().get("r34:water_bucket")==1 and float(runtime.stock(rack).items.get("r34:raw_water",0))>=1,{"field":field(),"rack":runtime.stock(rack)})
	note("actual-autonomous-planted-source-and-logistics")
	cold("actual12-farm-water-log-final-cold")
	check("no injected people HP consent or safe drinking water",runtime.facts().actors.size()==3 and initial.facts.actors.all(func(a:Dictionary)->bool:return runtime.actor(a.id).hp==a.hp) and ["village-resident","repair-resident"].all(func(id:String)->bool:return runtime.actor(id).relationship.consent) and float(quantities().get("water",0))<=float(initial.facts.stocks.reduce(func(sum:float,s:Dictionary)->float:return sum+float(s.items.get("water",0)),0.0))+float(initial.facts.actors.reduce(func(sum:float,a:Dictionary)->float:return sum+float(a.pack.get("water",0)),0.0)))
	finish()

func finish()->void:
	if runtime!=null:
		FileAccess.open(output+"/farm-setup.json",FileAccess.WRITE).store_string(JSON.stringify({"field_id":field_id,"setup":setup,"field":field()},"\t",true,true))
		save("actual12-farm-water-log-final")
	super.finish()
