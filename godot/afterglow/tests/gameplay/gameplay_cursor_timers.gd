extends "res://tests/gameplay/generated_cooperation.gd"
## Recorded real material route/workbench. Repaired-radio and defense-warning
## prerequisites are explicit fixtures, not claimed completed combat/repair.

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	output_dir=args[0];DirAccess.make_dir_recursive_absolute(output_dir)
	evidence_kind="recorded-real-workbench-with-explicit-repaired-radio-and-timed-wave-prerequisites"
	command_prefix="E-cursor-timers:"
	host=Client.new()
	if args.size()!=2:check("recorded material route checkpoint supplied",false);finish();return
	var capture:Variant=JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not capture is Dictionary or not mount(capture):finish();return
	var benches:Array=runtime.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("definitionId")=="workbench")
	check("recorded material route retains actual constructed workbench",benches.size()==1)
	if benches.size()!=1:finish();return
	var bench:String=benches[0].id
	var points:Array=runtime._services.buildings.use_points(bench)
	if points.is_empty() or not walk(points[0],"actual B walk reaches retained constructed radio workstation"):finish();return
	var walked:Dictionary=runtime.capture_checkpoint()
	radio_progress(walked,bench)
	timed_wave(walked)
	finish()

func radio_progress(walked:Dictionary,bench:String)->void:
	var fixture:Dictionary=walked.duplicate(true)
	var g:Dictionary=fixture.world.extensions[Gameplay.KEY]
	g.defense.status="cleared";g.radio={"status":"repaired","station_id":bench,"signal":0.0}
	if not mount(fixture):return
	runtime.tick(0.1)
	var cursor:int=runtime.world.extension(Gameplay.KEY).last_event_revision
	var pack:Dictionary=runtime.actor("player").pack.duplicate(true)
	var tools:Array=runtime.world.extension("r3:production").tools.duplicate(true)
	var craft:float=runtime.actor("player").skills.crafting
	var start:Dictionary=send("radio",bench,{"operation":"transmit"})
	check("actual radio command validates real station and repaired prerequisite",start.ok,start)
	if not start.ok:return
	for i:int in 35:runtime.tick(0.1);ticks+=1
	var signal_at_save:float=runtime.world.extension(Gameplay.KEY).radio.signal
	check("radio advances actual elapsed/signal despite unchanged event cursor",signal_at_save>3.4 and signal_at_save<3.6 and int(runtime.world.extension(Gameplay.KEY).last_event_revision)==cursor and is_equal_approx(float(runtime.actor("player").intent.elapsed),signal_at_save))
	runtime.set_paused(true);var paused:Dictionary=runtime.capture_checkpoint();runtime.tick(10)
	check("pause freezes transmission and shared logical time",Data.json_equal(paused,runtime.capture_checkpoint()))
	runtime.set_paused(false)
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
	var decoded:Dictionary=Store.decode(encoded.get("text",""))
	check("in-progress actual radio intent native codec",encoded.ok and decoded.ok)
	if not encoded.ok or not decoded.ok or not mount(decoded.capture):return
	check("restore preserves consumed cursor and continuous radio progress",int(runtime.world.extension(Gameplay.KEY).last_event_revision)==cursor and absf(float(runtime.world.extension(Gameplay.KEY).radio.signal)-signal_at_save)<1e-12 and absf(float(runtime.actor("player").intent.elapsed)-signal_at_save)<1e-12)
	for i:int in 400:
		if runtime.actor("player").intent==null:break
		runtime.tick(0.1);ticks+=1
	var state:Dictionary=runtime.world.extension(Gameplay.KEY)
	check("original radio work reaches thirty seconds and connects",runtime.actor("player").intent==null and state.radio.status=="connected" and state.flags.get("radio_connected",false) and is_equal_approx(float(state.radio.signal),30.0),state.radio)
	check("transmission completion awards one original skill increment and creates no items/tools",is_equal_approx(float(runtime.actor("player").skills.crafting)-craft,1.0) and Data.json_equal(pack,runtime.actor("player").pack) and Data.json_equal(tools,runtime.world.extension("r3:production").tools))
	for i:int in 8:runtime.tick(0.1)
	check("completed radio cannot repeat and ignored completion event does not advance cursor",int(runtime.world.extension(Gameplay.KEY).last_event_revision)==cursor and is_equal_approx(float(runtime.actor("player").skills.crafting)-craft,1.0) and not send("radio",bench,{"operation":"transmit"}).ok)
	write_json("radio-cursor.json",{"explicit_prerequisites":["defense cleared","radio repaired at real built station"],"cursor":cursor,"signal_at_save":signal_at_save,"final":runtime.world.extension(Gameplay.KEY).radio,"tick_count":ticks})

func timed_wave(walked:Dictionary)->void:
	if not mount(walked):return
	var position:Dictionary={}
	var center:Dictionary=runtime.world.extension(Gameplay.KEY).layout.home
	var candidates:Array=[runtime.world.extension(Gameplay.KEY).layout.defense_position]
	for offset:Vector3 in [Vector3(6,0,6),Vector3(-6,0,6),Vector3(8,0,-6),Vector3(-8,0,-6)]:
		var p:Dictionary=center.duplicate(true);p.x+=offset.x;p.z+=offset.z
		var height:Variant=runtime.world.surface_height(float(p.x),float(p.z))
		if height!=null:p.y=float(height);candidates.append(p)
	for candidate:Dictionary in candidates:
		var probe:=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.gameplay.context)
		var wave:Dictionary={"id":"first-night","position":candidate.duplicate(true),"actors":[]}
		if runtime._services.gameplay._spawn(probe,wave,true).ok:position=candidate;break
	check("timed-wave fixture has three independently valid actual body stations",not position.is_empty())
	if position.is_empty():return
	var fixture:Dictionary=runtime.capture_checkpoint()
	var now:float=runtime.clock()
	var g:Dictionary=fixture.world.extensions[Gameplay.KEY]
	g.layout.defense_position=position
	g.defense={"status":"warning","warning_at":now,"arrival_at":now+0.5,"actors":[]}
	if not mount(fixture):return
	var before:int=runtime.facts().actors.size()
	for i:int in 3:runtime.tick(0.1);ticks+=1
	check("timed warning does not spawn early",runtime.world.extension(Gameplay.KEY).defense.status=="warning" and runtime.facts().actors.size()==before)
	for i:int in 3:runtime.tick(0.1);ticks+=1
	var state:Dictionary=runtime.world.extension(Gameplay.KEY)
	check("no new cursor event still runs actual due finite-wave spawning",state.defense.status=="active" and state.defense.actors.size()==3 and runtime.facts().actors.size()==before+3,state.defense)
	check("timed spawn is not prematurely cleared or converted to radio rewards",not state.flags.get("radio_connected",false) and state.defense.status!="cleared")
	write_json("timed-wave-cursor.json",{"explicit_prerequisite":"warning with arrival in0.5 logical seconds","position":position,"arrival":now+0.5,"actual_time":runtime.clock(),"defense":state.defense})
