extends "res://tests/gameplay/generated_cooperation.gd"
## Shared ability reads must use the supplied staged person, not an old ID
## lookup. These are explicit pure needs/HP fixtures, not earned gameplay.
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Residents=preload("res://scripts/runtime/resident_life.gd")

func run()->void:
	output_dir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output_dir)
	evidence_kind="explicit-staged-needs-shared-capability-consumers"
	host=Client.new()
	var built:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	check("capability generated world prepares",built.ok,built.get("reason"))
	if not built.ok or not mount(built.capture):finish();return
	var before:Dictionary=runtime.capture_checkpoint()
	var residents:RefCounted=runtime._services.residents
	for id:String in ["player","village-resident"]:
		var staged:Dictionary=runtime.actor(id)
		staged.thirst=80.0;staged.hunger=80.0;staged.stamina=40.0
		staged.fatigue=60.0;staged.self_routine={"phase":0}
		# The existing canonical cap is 73, so 40 is above its half-cap.
		# Current authority still has its original, less fatigued person's cap.
		check(id+" decision reads staged stamina ceiling",residents._need(staged)=="",{"staged":staged,"authority":runtime.actor(id)})
		staged.stamina=30.0
		check(id+" staged low stamina still requests actual recovery",residents._need(staged)=="rest")
	check("ability decisions never mutate authority clock inventory or profiles",Data.json_equal(before,runtime.capture_checkpoint()))
	var detached:Dictionary=Initial.actor("ordinary:detached-effects","Detached ordinary person",Geometry.location(runtime.actor("player")),runtime.actor("player").home,{})
	detached.fatigue=60.0;detached.stamina=40.0
	var standalone:=Residents.new()
	check("unconfigured ordinary decision needs no registered ID or second authority",standalone._need(detached)=="")
	for fatigue:float in [0.0,22.0,60.0,100.0]:
		detached.fatigue=fatigue
		check("E and movement use the same effects ceiling at "+str(fatigue),standalone._stamina_max(detached)==Movement.stamina_max(detached) and standalone._stamina_max(detached)==Content.actor_effects(detached).stamina_max)
	var effects:Dictionary=Content.actor_effects(detached)
	effects.skills.crafting=999
	check("effects expose detached existing skills and neutral multipliers",detached.skills.crafting==0 and Content.actor_effects(detached).labor_multiplier==1.0 and Content.actor_effects(detached).recovery_multiplier==1.0)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	check("complete existing catalog resolves formal quantity references",Content.validate_catalog(catalog).ok)
	for bad_id:String in ["unknown","unknown_m3"]:
		var bad:Dictionary=catalog.duplicate(true)
		bad.production_recipes[0].inputs[bad_id]=1
		check("formal recipe rejects unknown item even with volume-like name "+bad_id,not Content.validate_catalog(bad).ok and Content.item_definition(bad_id).is_empty() and Content.quantity_step(bad_id)==0)
	var intent:Dictionary={"schema_version":1,"owner":"gameplay","kind":"radio","id":"E:effects:radio-schema","operation":"repair","source_id":"pack:"+str(detached.id),"target_id":"fixture:bench","tool_id":"fixture:hammer","cost":{"scrap":8,"tool_handle":1},"elapsed":0.0,"duration":20.0}
	check("E radio accepts original exact costs through public definitions",runtime._services.gameplay.validate_intent(intent,detached).ok)
	for bad:Variant in [7,8.5,"8",true]:
		var invalid:Dictionary=intent.duplicate(true);invalid.cost.scrap=bad
		check("radio retains exact cost and typed public quantity rejection "+str(bad),not runtime._services.gameplay.validate_intent(invalid,detached).ok)
	intent.cost={"scrap":8.0,"tool_handle":1.0}
	check("native JSON numeric representation retains legal original costs",runtime._services.gameplay.validate_intent(intent,detached).ok)
	finish()
