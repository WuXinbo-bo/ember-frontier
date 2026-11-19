extends SceneTree
const Rural=preload("res://scripts/world/rural_generator.gd")
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const Settlement=preload("res://scripts/world/settlement_generator.gd")
const Before2=preload("res://tests/world/fixtures/rural2_generator_before_landscape.gd")
const Before3=preload("res://tests/world/fixtures/landscape_generator_before_housing.gd")
const BeforeApron=preload("res://tests/world/fixtures/local_apron_before_sampling_cost.gd")
const Contract=preload("res://scripts/world/generation_contract.gd")
const State=preload("res://scripts/world/world_state.gd")
const Codec=preload("res://scripts/world/world_codec.gd")
const Data=preload("res://scripts/world/world_data.gd")
const ORIGINAL="res://tests/world/fixtures/generation_profiles_before_housing.json"
const CURRENT="res://data/buildings/generation_profiles.json"
var checks:Array=[]
var costs:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func run()->void:
	var base:Array=JSON.parse_string(FileAccess.get_file_as_string(ORIGINAL)).profiles
	var catalog:Array=JSON.parse_string(FileAccess.get_file_as_string(CURRENT)).profiles
	check("actual delivered catalogue retains all original six complete profile values",base.all(func(row:Dictionary)->bool:return catalog.any(func(current:Dictionary)->bool:return Data.json_equal(row,current))))
	var unrelated:Dictionary=base[0].duplicate(true);unrelated.id="future-unselected-family";catalog.append(unrelated)
	var old2:Dictionary=Before2.generate(713,base)
	check("explicit rural2 ignores added catalogue families and keeps complete original world",Data.json_equal(old2,Rural.generate_settlement(713,catalog,"rural-2")))
	# Some historical tools supplied extra unused valid rows. An exact original
	# full stamp is also supported, without replacing it with the six-row stamp.
	var extra_world:=State.new();extra_world.load_snapshot(Before2.generate(713,catalog))
	var extra_input:Dictionary=Rural.region_generation_input(extra_world,catalog)
	var extra_draft:Dictionary=Rural.draft_settlement_region(713,Vector2i(-1,0),extra_input.profiles,extra_input.version,extra_input.generation_contract) if extra_input.ok else extra_input
	var extra_reference:Dictionary=Before2.draft_region(713,Vector2i(-1,0),catalog)
	check("legacy exact full catalogue contract also keeps its original stamp and plan",extra_draft.ok and Data.json_equal(extra_draft.plan,extra_reference.plan) and Rural.prepare_region_draft(extra_world,extra_draft,extra_world.get_revision()).ok)
	var old3:Dictionary=Before3.generate(713,base)
	var pinned_before_model:Dictionary=old3.duplicate(true)
	var old_input:Dictionary=Contract.fresh(base).contract
	old_input.erase("landscape_model")
	for key:String in Contract.PIN_FIELDS:
		if not old_input.has(key):continue
		pinned_before_model.extensions["generation:rural2"][key]=old_input[key]
		for region_id:String in ["RH-HOME","RH-VILLAGE"]:pinned_before_model.extensions["generation:"+region_id][key]=old_input[key]
	var pinned_world:=State.new();pinned_world.load_snapshot(pinned_before_model)
	var prior:Dictionary=Rural.region_generation_input(pinned_world,catalog)
	var prior_draft:Dictionary=Rural.draft_settlement_region(713,Vector2i(-1,0),prior.profiles,prior.version,prior.generation_contract) if prior.ok else prior
	var prior_reference:Dictionary=Before3.draft_region(713,Vector2i(-1,0),base)
	check("already-pinned rural3 without model key retains original terrain model",prior.ok and not prior.generation_contract.has("landscape_model") and prior_draft.ok and prior_draft.plan.height.grade_model=="organic-local-v1")
	check("already-pinned rural3 peripheral cells and resource entities remain byte exact",prior_draft.ok and Data.json_equal(prior_draft.chunks,prior_reference.chunks) and Data.json_equal(prior_draft.entities,prior_reference.entities))
	check("old pinned-model draft still passes main-thread saved-policy acceptance",prior_draft.ok and Rural.prepare_region_draft(pinned_world,prior_draft,pinned_world.get_revision()).ok)
	for snapshot:Dictionary in [old2,old3]:
		var world:=State.new();var loaded:Dictionary=world.load_snapshot(snapshot)
		var version:String=snapshot.generatorVersion
		check(version+" historical source loads without rewriting its configuration",loaded.ok and not world.extension("generation:rural2").has("profile_ids"))
		var before:Dictionary=world.snapshot()
		var input:Dictionary=Rural.region_generation_input(world,catalog)
		check(version+" captures only exact original six profiles as detached JSON values",input.ok and input.profiles.size()==6 and input.generation_contract.legacy and Data.json_value(input))
		var started:=Time.get_ticks_usec()
		var draft:Dictionary=Rural.draft_settlement_region(input.seed,Vector2i(1,0),input.profiles,input.version,input.generation_contract)
		costs[version+"_draft_ms"]=(Time.get_ticks_usec()-started)/1000.0
		var reference:Dictionary=Before2.draft_region(713,Vector2i(1,0),base) if version=="rural-2" else Before3.draft_region(713,Vector2i(1,0),base)
		check(version+" worker peripheral keeps exact pre-addition terrain plan chunks and entities",draft.ok and reference.ok and Data.json_equal(draft.plan,reference.plan) and Data.json_equal(draft.chunks,reference.chunks) and Data.json_equal(draft.entities,reference.entities))
		var prepared:Dictionary=Rural.prepare_region_draft(world,draft,input.expected_world_revision)
		check(version+" real main-thread prepare accepts compatible worker draft without changing live facts",prepared.ok and Data.json_equal(before,world.snapshot()),prepared.get("code"))
		var tx:Dictionary=world.prepare_changes(prepared.world_changes,world.get_revision()) if prepared.ok else prepared
		if tx.ok:world.commit_prepared(tx.capability)
		check(version+" same authoritative transaction installs actual peripheral chunks",tx.ok and world.region("R2:1:0").id=="R2:1:0" and world.chunk_keys().size()==768,tx.get("code"))
		var expanded:Dictionary=world.snapshot()
		var repeat:Dictionary=Rural.prepare_region(world,Vector2i(1,0),[])
		check(version+" explored peripheral returns saved plan with no stock or terrain reroll",repeat.ok and repeat.already_generated and repeat.world_changes.is_empty() and repeat.initial_stocks.is_empty() and Data.json_equal(expanded,world.snapshot()))
		var changed:Array=catalog.duplicate(true);changed[0].version+=1
		check(version+" actual original-family revision mismatch remains rejected",Rural.prepare_region(world,Vector2i(2,0),changed).get("code")=="GENERATION_PROFILE_VERSION_MISMATCH")
		var removed:Array=catalog.filter(func(row:Dictionary)->bool:return row.id!="homestead_l")
		check(version+" missing pinned original family remains rejected",not Rural.region_generation_input(world,removed).ok)
		if version=="rural-3":
			var wrong:Dictionary=Landscape.draft_region(713,Vector2i(2,0),base)
			check("old rural3 cannot accept a fresh pinned-policy worker by equal geometry SHA alone",Rural.prepare_region_draft(world,wrong,world.get_revision()).get("code")=="GENERATION_POLICY_MISMATCH")
	var fresh:Dictionary=Rural.generate_settlement(2026,base)
	var current:=State.new();var accepted:Dictionary=current.load_snapshot(fresh)
	check("fresh world persists candidate IDs input SHA and explicit selection policy",accepted.ok and current.extension("generation:rural2").profile_ids.size()==6 and current.extension("generation:rural2").residential_selection.version==1)
	check("fresh finite-apron model is persisted in configuration and actual plan",accepted.ok and current.extension("generation:rural2").landscape_model=="village-contours-v4" and current.extension("generation:RH-HOME").height.grade_model=="village-contours-v4")
	var v2_contract:Dictionary=Contract.fresh(base).contract;v2_contract.landscape_model="local-apron-v2"
	var v2_plan:Dictionary=Landscape.plan_region(275196493,Vector2i(0,-1),base,v2_contract)
	var v2_original:Dictionary=BeforeApron.draft_plan(v2_plan.plan.duplicate(true)) if v2_plan.ok else v2_plan
	var v2_current:Dictionary=Settlement.draft_plan(v2_plan.plan.duplicate(true)) if v2_plan.ok else v2_plan
	check("saved local-apron-v2 keeps exact original raster plan and entities at failing new seed",v2_original.ok and v2_current.ok and Data.json_equal(v2_original.plan,v2_current.plan) and Data.json_equal(v2_original.chunks,v2_current.chunks) and Data.json_equal(v2_original.entities,v2_current.entities))
	# The live eighth package uses v3. Its saved model must survive the new
	# default without silently giving an unexplored neighbour v4 road widths.
	var v3_contract:Dictionary=Contract.fresh(catalog).contract;v3_contract.landscape_model="local-apron-v3"
	var v3_source:Dictionary=Landscape.generate(973339546,catalog,v3_contract)
	var v3_saved:Dictionary=Codec.encode_checkpoint(v3_source,{},"test:eighth-model-compat")
	var v3_decoded:Dictionary=Codec.decode_checkpoint(v3_saved.envelope) if v3_saved.ok else v3_saved
	var v3_world:=State.new();var v3_loaded:Dictionary=v3_world.load_snapshot(v3_decoded.state) if v3_decoded.ok else v3_decoded
	var v3_input:Dictionary=Rural.region_generation_input(v3_world,catalog) if v3_loaded.ok else v3_loaded
	check("saved eighth local-apron-v3 cold restore pins original model after v4 default",v3_input.ok and v3_input.generation_contract.landscape_model=="local-apron-v3" and v3_world.extension("generation:RH-VILLAGE").height.grade_model=="local-apron-v3")
	var v3_next:Dictionary=Rural.draft_settlement_region(973339546,Vector2i(-1,0),v3_input.profiles,v3_input.version,v3_input.generation_contract) if v3_input.ok else v3_input
	var v3_reference:Dictionary=Landscape.draft_region(973339546,Vector2i(-1,0),catalog,v3_contract)
	check("restored v3 unexplored neighbour retains complete original cells entities and plan",v3_next.ok and Data.json_equal(v3_next.chunks,v3_reference.chunks) and Data.json_equal(v3_next.entities,v3_reference.entities) and Data.json_equal(v3_next.plan,v3_reference.plan))
	var v4_wrong:Dictionary=Landscape.draft_region(973339546,Vector2i(-1,0),catalog)
	check("restored v3 refuses fresh v4 worker even at the same seed and coordinate",v3_loaded.ok and v4_wrong.ok and Rural.prepare_region_draft(v3_world,v4_wrong,v3_world.get_revision()).get("code")=="GENERATION_POLICY_MISMATCH")
	var v3_prepare:Dictionary=Rural.prepare_region_draft(v3_world,v3_next,v3_world.get_revision()) if v3_next.ok else v3_next
	var v3_tx:Dictionary=v3_world.prepare_changes(v3_prepare.world_changes,v3_world.get_revision()) if v3_prepare.ok else v3_prepare
	if v3_tx.ok:v3_world.commit_prepared(v3_tx.capability)
	check("restored v3 accepts its actual original-model neighbour via authoritative transaction",v3_tx.ok and v3_world.extension("generation:R2:-1:0").height.grade_model=="local-apron-v3")
	var captured:Dictionary=Rural.region_generation_input(current,catalog)
	check("later unrelated addition cannot enter a fresh world's pinned candidates",captured.ok and captured.profiles.size()==6 and not captured.generation_contract.profile_ids.has(unrelated.id))
	var a:Dictionary=Landscape.plan_region(2026,Vector2i(1,-1),base,captured.generation_contract)
	var b:Dictionary=Landscape.plan_region(2026,Vector2i(1,-1),catalog,captured.generation_contract)
	check("saved policy reproduces full peripheral plan after catalogue addition",a.ok and b.ok and Data.json_equal(a.plan,b.plan))
	var changed_anchor:Array=base.duplicate(true);changed_anchor[0].npc_anchors[0].position[0]+=0.5
	check("fresh contract also rejects changed NPC anchors without a geometry version bump",Rural.region_generation_input(current,changed_anchor).get("code")=="GENERATION_PROFILE_VERSION_MISMATCH")
	var duplicate:Array=catalog.duplicate(true);duplicate.append(base[0].duplicate(true))
	check("duplicate selected profile cannot silently choose one catalogue entry",not Rural.region_generation_input(current,duplicate).ok)
	var stale:Dictionary=Rural.prepare_region(current,Vector2i(-1,0),catalog,current.get_revision()+1)
	check("stale world precondition still rejected before generation",stale.get("code")=="STALE_REVISION")
	var encoded:Dictionary=Codec.encode_checkpoint(current.snapshot(),{},"test:profile-pinning")
	var decoded:Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
	var restored:=State.new();var restored_ok:Dictionary=restored.load_snapshot(decoded.state) if decoded.ok else decoded
	var restored_input:Dictionary=Rural.region_generation_input(restored,catalog) if restored_ok.ok else restored_ok
	check("actual world codec retains exact candidate IDs and input contract on cold restore",restored_ok.ok and restored_input.ok and Data.json_equal(captured.generation_contract,restored_input.get("generation_contract")),{"encode":encoded.get("code"),"decode":decoded.get("code"),"restore":restored_ok.get("code"),"input":restored_input})
	if not restored_input.ok:return finish()
	var negative:Dictionary=Landscape.plan_region(2026,Vector2i(-1,-1),restored_input.profiles,restored_input.generation_contract)
	var again:Dictionary=Landscape.plan_region(2026,Vector2i(1,-1),restored_input.profiles,restored_input.generation_contract)
	check("negative and reverse order planning retain same shared global grading controls",negative.ok and again.ok and Data.json_equal(a.plan,again.plan) and Data.json_equal(negative.plan.grade_controls,a.plan.grade_controls))
	finish()
func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"costs":costs,"scope":"C real old/fresh authoritative generation, worker handoff, transactions and native world codec; not app/Metal/OS/VA"}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(1 if failed else 0)
