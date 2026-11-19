extends "res://tests/gameplay/generated_cooperation.gd"
## Consume actual completed A/B/E extension checkpoints through D's public view.
## No synthetic intent, animation DTO, formal app or normal-camera VA claim.
const Actors=preload("res://scripts/presentation/actor_view.gd")
var view:Node3D
var observations:Array=[]

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	output_dir=args[0];DirAccess.make_dir_recursive_absolute(output_dir)
	evidence_kind="actual-ordinary-extension-checkpoints-real-rigs-headless-consumption"
	host=Client.new()
	if args.size()!=2:check("actual completed extension evidence supplied",false);finish();return
	var index:Variant=JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not index is Dictionary or not index.get("phase_captures") is Array:
		check("actual extension phase index is valid",false);finish();return
	var id:String=index.ordinary_id
	check("nine original extension phases supplied",index.phase_captures.size()==9)
	view=Actors.new();root.add_child(view);view.set_process(false)
	for phase:Dictionary in index.phase_captures:
		var capture:Variant=JSON.parse_string(FileAccess.get_file_as_string(phase.path))
		if not capture is Dictionary or not mount(capture):view.free();finish();return
		# Restored walking motion is derived again by the real B executor.
		# Do not forge movement or extend work just for a presentation test.
		if phase.phase=="walking":runtime.tick(0.1);ticks+=1
		var before:Dictionary=runtime.capture_checkpoint()
		view.configure(runtime);view.sync(0.1)
		var report:Dictionary=view.assembly_report()
		var stats:Dictionary=view.statistics()
		check(phase.phase+" original rigs pass real assembly",report.ok,report)
		check(phase.phase+" view leaves world facts inventory and clock unchanged",Data.json_equal(before,runtime.capture_checkpoint()))
		if phase.phase=="removed":
			check("actually removed ordinary identity has no model or animation",not view.roots.has(id) and not stats.animation_states.has(id) and not report.actors.any(func(a:Dictionary)->bool:return a.actor_id==id))
		else:
			var person:Dictionary=runtime.actor(id)
			var rows:Array=report.actors.filter(func(a:Dictionary)->bool:return a.actor_id==id)
			check(phase.phase+" stable saved appearance binds actual original model",rows.size()==1 and rows[0].ok and rows[0].profile_id==index.appearances[id][0] and rows[0].resource=="res://data/gameplay/actors/"+str(index.appearances[id][0])+".glb",rows)
			check(phase.phase+" ordinary actor owns actual AnimationPlayer",stats.animation_players==stats.actors and view.roots.has(id) and view.roots[id].get_child_count()>0)
			var expected:String="Walk" if phase.phase=="walking" else "Use" if phase.phase=="working" else "RestLying" if phase.phase in ["paused-work","incapacitated"] else "Idle"
			check(phase.phase+" real authoritative state selects original "+expected,stats.animation_states.get(id)==expected,{"actual":stats.animation_states.get(id),"intent":person.get("intent"),"movement":runtime.actor_presentation().movement.get(id)})
			if phase.phase=="incapacitated":check("actual human RestLying rig is not tilted twice",is_zero_approx(view.roots[id].rotation.z))
		observations.append({"phase":phase.phase,"capture":phase.path,"assembly":report,"statistics":stats})
	write_json("presentation-evidence.json",{"scope":evidence_kind,"ordinary_id":id,"observations":observations})
	view.free();finish()
