extends "res://tests/integration/run_village_opening16.gd"
## Same shipping opening/actions, followed by a bounded real walking observation.
## No position, terrain, inventory, clock or authority injection.
const MovementProbe16=preload("res://scripts/presentation/movement_frame_probe.gd")

func distribution(values:Array)->Dictionary:
	if values.is_empty():return {"count":0}
	var ordered:Array=values.duplicate();ordered.sort()
	var total:float=0
	for value:float in ordered:total+=value
	return {"count":ordered.size(),"mean_ms":total/ordered.size(),"p95_ms":ordered[mini(ordered.size()-1,floori(ordered.size()*.95))],"p99_ms":ordered[mini(ordered.size()-1,floori(ordered.size()*.99))],"max_ms":ordered[-1],"fps":1000.0*ordered.size()/total}

func walk_and_rest(beds:Array)->void:
	var original:Dictionary=Geometry.location(host.runtime.actor("player"))
	await super.walk_and_rest(beds)
	if checks.any(func(row:Dictionary)->bool:return not row.ok):return
	var endpoints:Array=[original,Geometry.location(host.runtime.actor("player"))]
	check("walking observation has two physically reached distinct endpoints",Geometry.point(endpoints[0]).distance_to(Geometry.point(endpoints[1]))>2.0)
	if Geometry.point(endpoints[0]).distance_to(Geometry.point(endpoints[1]))<=2.0:return
	var observer:=MovementProbe16.new();var intervals:Array[float]=[];var completed:int=0;var accepted:int=0
	var started:int=Time.get_ticks_usec();var previous:int=started;var next:int=0
	var command_ok:bool=true;var arrival_ok:bool=true
	host.runtime.set_paused(false)
	while Time.get_ticks_usec()-started<60000000:
		if host.runtime.actor("player").get("intent")==null:
			if accepted>0:
				if Geometry.point(host.runtime.actor("player")).distance_to(Geometry.point(endpoints[1-next]))>.2:arrival_ok=false;break
				completed+=1
			var result:Dictionary=host.runtime.command({"kind":"walk","actor_id":"player","command_id":"movement16-roundtrip-"+str(accepted),"destination":endpoints[next]})
			if not result.ok:command_ok=false;break
			accepted+=1;next=1-next
		await process_frame
		var now:int=Time.get_ticks_usec();var elapsed:float=(now-previous)/1000.0
		intervals.append(elapsed);observer.observe(host.runtime.actor("player"),now,elapsed,true);previous=now
	host.runtime.set_paused(true)
	check("all repeated walk commands pass real authority admission",command_ok,{"accepted":accepted})
	check("completed walks actually reach alternating endpoints",arrival_ok and completed>=6,{"completed":completed,"distance_m":observer.distance_m})
	check("walking observation contains no discontinuity or teleport",observer.discontinuities==0,observer.discontinuities)
	check("walking observation completes its bounded sixty second window",Time.get_ticks_usec()-started>=60000000)
	movement.long_observation={"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"whole":distribution(intervals),"moving":distribution(observer.frames),"distance_m":observer.distance_m,"completed":completed,"accepted":accepted,"discontinuities":observer.discontinuities,"simulation":host.runtime.simulation_budget(),"frame_intervals_ms":intervals,"scope":"Sixty wall seconds of original Native clock and real roundtrip walking commands with exact production renderer; diagnostic sample, with the user previous game still running; not an exclusive-machine or long-soak qualification."}
