extends SceneTree
const Dressing=preload("res://scripts/world/dressing_layout.gd")
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const Contract=preload("res://scripts/world/generation_contract.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const State=preload("res://scripts/world/world_state.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func run()->void:
	var catalog:Array=Dressing.profiles();var expected:String=Dressing.contract_sha256(catalog)
	var added:Array=catalog.duplicate(true);var extra:Dictionary=catalog[0].duplicate(true);extra.id="future-unused-prop";added.append(extra)
	var input:Dictionary=Dressing.resolve(expected,added)
	check("adding unused prop preserves exact old definitions and hash",input.ok and input.profiles==catalog and input.contract_sha256==expected)
	var changed:Array=added.duplicate(true);changed[0].footprint.max.x+=0.5
	check("same used definition physical change still rejected",not Dressing.resolve(expected,changed).ok)
	changed=added.duplicate(true);changed.remove_at(0)
	check("removing old definition rejected",not Dressing.resolve(expected,changed).ok)
	changed=added.duplicate(true);changed.append(catalog[0])
	check("ambiguous duplicate used ID rejected",not Dressing.resolve(expected,changed).ok)
	check("unknown historical input cannot silently use current catalogue",not Dressing.resolve("0".repeat(64),added).ok)
	var original_eight:Array=catalog.filter(func(p:Dictionary)->bool:return p.id!="abandoned_car")
	var eight_hash:=Dressing.contract_sha256(original_eight)
	check("pre-car eight has explicit reviewed exact history",Dressing.resolve(eight_hash,added).get("profiles",[])==original_eight)
	var profiles:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/generation_profiles.json")).profiles
	var contract:Dictionary=Contract.fresh(profiles).contract;contract.dressing_contract_sha256=eight_hash
	var source:Dictionary=Landscape.generate(713,profiles,contract)
	var world:=State.new();var loaded:Dictionary=world.load_snapshot(source)
	check("actual saved old dressing policy loads without changing world model",loaded.ok and world.extension("generation:rural2").dressing_contract_sha256==eight_hash)
	if loaded.ok:
		var before:Dictionary=world.snapshot()
		var captured:Dictionary=Rural.region_generation_input(world,profiles,added)
		check("owner captures detached selected profile values for worker",captured.ok and captured.generation_contract.dressing_profile_input==original_eight and Data.json_value(captured))
		if captured.ok:
			var draft:Dictionary=Rural.draft_region_request(captured,Vector2i(1,0))
			check("worker keeps old prop subset on actual adjacent coordinates",draft.ok and draft.plan.dressing_contract_sha256==eight_hash and draft.plan.dressing.all(func(p:Dictionary)->bool:return p.profile_id!="abandoned_car"),draft.get("code"))
			var prepared:Dictionary=Rural.prepare_region_draft(world,draft,world.get_revision()) if draft.ok else draft
			check("real prepare accepts compatible old content without touching source",prepared.ok and Data.json_equal(before,world.snapshot()),prepared.get("code"))
			var next:Dictionary=world.prepare_changes([{"op":"extension.set","id":"test:unrelated","before_exists":false,"before":null,"after":{"tick":1}}],world.get_revision())
			if next.ok:world.commit_prepared(next.capability)
			check("unrelated revision uses current CAS without regenerating worker output",Rural.prepare_region_draft(world,draft,world.get_revision()).ok and not Rural.prepare_region_draft(world,draft,int(captured.expected_world_revision)).ok)
			var foreign:Dictionary=source.duplicate(true);foreign.worldId="other:same-seed"
			var another:=State.new();another.load_snapshot(foreign)
			check("same seed foreign world cannot adopt owner request",Rural.prepare_region_draft(another,draft,another.get_revision()).get("code")=="FOREIGN_GENERATION_REQUEST")
		check("changed used definition rejected before worker generation",not Rural.region_generation_input(world,profiles,changed).ok)
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"scope":"C exact historical content inputs and actual adjacent preparation; A commit/B final safety/OS save remain separate"}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify(report));quit(1 if failed else 0)
