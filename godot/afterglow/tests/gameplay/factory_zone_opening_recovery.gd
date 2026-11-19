extends "res://tests/gameplay/factory_zone_opening_farm.gd"
## Continue actual built facilities and original blocked job. B/C provide
## standing/target correction; E issues NO replacement NPC action or field edit.
var before_job:Dictionary={}
var sow_cold:bool=false

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];options=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var native:=Native.new()
	var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	check("actual paid facilities and original blocked farm mount unchanged",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime;initial=runtime.capture_checkpoint();elapsed_start=runtime.clock();field_id="r34:ecology:RH-HOME:76:0:92"
	var id:String="workforce:execute:village-resident:2715"
	before_job=runtime.domain_service("zonework").state().jobs.get(id,{})
	check("only same blocked job target cell elapsed and finite sources retained",before_job.get("status")=="blocked" and before_job.get("elapsed")==8 and before_job.get("target",{}).get("y")==0 and before_job.get("location",{}).get("y")==.5 and field().is_empty(),before_job)
	if before_job.is_empty():return finish()
	note("same-real-paid-blocked-job-before-provider-recovery")
	var completed:bool=false;var draw_seen:bool=false;var supplied:bool=false
	for i:int in 1800:
		tick()
		var state:Dictionary=runtime.domain_service("zonework").state()
		if state.receipts.any(func(r:Dictionary)->bool:return r.id==id and r.status=="completed" and absf(float(r.elapsed)-8)<.000001):completed=true
		var a:Dictionary=runtime.actor("village-resident")
		if a.get("intent") is Dictionary:
			if a.intent.get("kind")=="zone_supply":supplied=true
			if a.intent.get("owner")=="zonework":
				var work:Dictionary=state.jobs.get(str(a.intent.get("work_id","")),{})
				if work.get("job",{}).get("kind")=="draw_raw_water":draw_seen=true
				if work.get("job",{}).get("kind")=="sow" and float(work.get("effective_seconds",0))>0 and not sow_cold:sow_cold=cold("actual12-recovered-sow-active-cold")
		if completed and field().get("stage") in ["seedling","growing"] and float(runtime.stock(rack).items.get("r34:raw_water",0))>=2:break
	check("original blocked job completes once without relocation new job or replay labor",completed and runtime.domain_service("zonework").state().receipts.filter(func(r:Dictionary)->bool:return r.id==id).size()==1,{"original":before_job,"state":runtime.domain_service("zonework").state(),"field":field()})
	check("E autonomously fetches real sole seed and sows with active full cold",supplied and sow_cold and field().get("stage") in ["seedling","growing"] and runtime.stock(rack).items.get("r34:potato_seed")==0 and quantities().get("r34:potato_seed")==3,{"field":field(),"actor":runtime.actor("village-resident")})
	check("same real NPC takes original source raw water then walks and deposits two units",draw_seen and float(runtime.stock(rack).items.get("r34:raw_water",0))>=2 and quantities().get("r34:water_bucket")==1,{"stock":runtime.stock(rack),"ecology":runtime.domain_service("ecology").state(),"actors":runtime.facts().actors,"logistics":runtime.world.extension("r34:logistics")})
	check("no replacement people HP or consent and paid facilities remain operational",runtime.facts().actors.size()==3 and initial.facts.actors.all(func(a:Dictionary)->bool:return runtime.actor(a.id).hp==a.hp) and ["village-resident","repair-resident"].all(func(person:String)->bool:return runtime.actor(person).relationship.consent) and ["E:actual12:water-low","E:actual12:canteen-low"].all(func(m:String)->bool:return runtime.domain_service("modules").instance(m).status=="operational"))
	note("original-job-recovery-real-seed-and-source-delivery")
	cold("actual12-recovered-field-water-final-cold")
	finish()

func finish()->void:
	if runtime!=null:save("actual12-recovered-field-water-final")
	super.finish()
