extends "res://tests/gameplay/factory_zone_opening_journey.gd"
## Read-only route/residency diagnosis of the actual paid opening failure.
## No warm, move, tick, fixture or authority mutation after original assembly.
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];options=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var native:=Native.new()
	var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	check("actual paid opening failure mounts without injected authority",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime;initial=runtime.capture_checkpoint();elapsed_start=runtime.clock()
	var before:Dictionary=runtime.capture_checkpoint()
	var states:Dictionary={}
	for region:Dictionary in runtime.world.regions():states[region.id]={"storage":runtime.world.region_residency_state(region.id),"detailed":runtime.region_is_detailed(region.id)}
	var home:Dictionary=runtime.world.extension(Gameplay.KEY).layout.home
	var rows:Array=[]
	var exit:Dictionary={"regionId":"RH-VILLAGE","buildingId":null,"storeyId":null,"x":34.0,"y":0.5,"z":-0.5}
	for destination:Dictionary in [home,exit,G.location(runtime.stock(source_tools))]:
		var began:int=Time.get_ticks_usec()
		var route:Dictionary=runtime.domain_service("actions").route("player",G.location(runtime.actor("player")),destination)
		rows.append({"destination":destination,"route":route,"usec":Time.get_ticks_usec()-began})
	check("read-only route diagnosis preserves entire original checkpoint",Data.json_equal(before,runtime.capture_checkpoint()))
	FileAccess.open(output+"/residency-diagnosis.json",FileAccess.WRITE).store_string(JSON.stringify({"regions":states,"pins":Residency.required_regions(runtime),"routes":rows,"clock":runtime.clock(),"actor":runtime.actor("player"),"scope":"Original paid failure, only authoritative read queries after Native assembly. No warming, simulation STEP or gameplay commands. A missing headless stream prerequisite is not assigned as a navigation defect."},"\t",true,true))
	finish()
