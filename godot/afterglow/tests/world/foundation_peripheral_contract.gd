extends SceneTree
const Rural=preload("res://scripts/world/rural_generator.gd")
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const Contract=preload("res://scripts/world/generation_contract.gd")
const Generator=preload("res://scripts/world/settlement_generator.gd")
const State=preload("res://scripts/world/world_state.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"label":label,"ok":ok})
	if not ok:push_error("FAIL "+label)
func run()->void:
	var profiles:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/generation_profiles.json")).profiles
	var base:Dictionary=Landscape.generate(973339546,profiles)
	var world:=State.new();check("actual two-region base loads",world.load_snapshot(base).ok)
	var input:=Rural.region_generation_input(world,profiles)
	var started:=Time.get_ticks_usec();var draft:=Rural.draft_region_request(input,Vector2i(1,0));var worker_usec:=Time.get_ticks_usec()-started
	check("detached request creates actual neighboring raster",draft.ok and draft.chunks.size()==256)
	started=Time.get_ticks_usec();var prepared:=Rural.prepare_region_draft(world,draft,world.get_revision());var prepare_usec:=Time.get_ticks_usec()-started
	check("complete exact lattice prepares through real current CAS",prepared.ok and prepared.world_changes.size()>257)
	for delta:Vector2i in [Vector2i(9,0),Vector2i(0,-9),Vector2i(-9,9)]:
		check("coordinate cap enforced before worker "+str(delta),Rural.draft_region_request(input,delta).get("code")=="GENERATION_COORD_LIMIT")
	var bounds:Dictionary=draft.region.bounds.duplicate(true);draft.region.bounds.min.x+=0.5
	check("worker cannot displace declared region bounds",Rural.prepare_region_draft(world,draft,world.get_revision()).get("code")=="INVALID_REGION_DRAFT")
	draft.region.bounds=bounds
	var key:String=draft.chunks.keys()[0];var chunk:Dictionary=draft.chunks[key];draft.chunks.erase(key);draft.chunks["1000,0,1000"]=chunk
	check("256 wrong-coordinate chunks cannot pass as the expected lattice",Rural.prepare_region_draft(world,draft,world.get_revision()).get("code")=="INVALID_REGION_DRAFT")
	draft.chunks.erase("1000,0,1000");draft.chunks[key]=chunk
	var tx:=world.prepare_changes([{"op":"extension.set","id":"test:cursor","before_exists":false,"before":null,"after":{"cursor":1}}],world.get_revision());world.commit_prepared(tx.capability)
	check("unrelated revision needs fresh CAS but reuses same worker raster",Rural.prepare_region_draft(world,draft,world.get_revision()).ok and Rural.prepare_region_draft(world,draft,int(input.expected_world_revision)).get("code")=="STALE_REVISION")
	var old_config:Dictionary=world.extension("generation:rural2");var config:=old_config.duplicate(true);config.layout_policy={"id":"rural-bounded-layout","version":1}
	tx=world.prepare_changes([{"op":"extension.set","id":"generation:rural2","before_exists":true,"before":old_config,"after":config}],world.get_revision());world.commit_prepared(tx.capability)
	check("changed persisted layout configuration rejects in-flight worker",Rural.prepare_region_draft(world,draft,world.get_revision()).get("code")=="STALE_GENERATION_CONFIGURATION")
	tx=world.prepare_changes([{"op":"extension.set","id":"generation:rural2","before_exists":true,"before":config,"after":old_config}],world.get_revision());world.commit_prepared(tx.capability)
	prepared=Rural.prepare_region_draft(world,draft,world.get_revision())
	tx=world.prepare_changes(prepared.world_changes,world.get_revision())
	check("same worker returns to unchanged geometry config and atomically commits",tx.ok and world.commit_prepared(tx.capability).ok and world.regions().size()==3)
	var region_cells:Dictionary=world.snapshot();var again:=Rural.prepare_region_draft(world,draft,world.get_revision())
	check("already generated request never re-rasterizes explored facts",again.ok and again.already_generated and again.world_changes.is_empty() and Data.json_equal(world.snapshot(),region_cells))
	var malformed:Dictionary=base.duplicate(true);malformed.config.maxReach=3.0
	var custom:=State.new();check("schema-valid alternate config fixture loads",custom.load_snapshot(malformed).ok)
	check("fixed generator refuses foreign lattice config at capture and prepare",Rural.region_generation_input(custom,profiles).get("code")=="GENERATION_CONFIG_MISMATCH" and Rural.prepare_region_draft(custom,draft,custom.get_revision()).get("code")=="GENERATION_CONFIG_MISMATCH")
	var capped:Dictionary=base.duplicate(true)
	for i in 22:
		var r:Dictionary=base.regions["RH-HOME"].duplicate(true);r.id="capacity:"+str(i);r.bounds.min.x+=float((i+2)*64);r.bounds.max.x+=float((i+2)*64);capped.regions[r.id]=r
	var full:=State.new();check("24 schema-valid region-count capacity fixture loads",full.load_snapshot(capped).ok and full.regions().size()==24)
	check("final preparation still enforces finite24-region capacity",Rural.prepare_region_draft(full,draft,full.get_revision()).get("code")=="GENERATION_CAPACITY")
	var result:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary):return not c.ok).size(),"limits":{"abs_coordinate":Generator.COORD_LIMIT,"regions":Generator.MAX_REGIONS,"per_region_chunks":256,"per_region_cells":1048576,"lattice":"64m / 0.5m /16 cells / cy=-1..2"},"worker_usec":worker_usec,"prepare_usec":prepare_usec,"scope":"C actual source/worker/lattice/current-CAS/config/capacity contract; capacity fixture counts valid region records, not24 fully rasterized regions. A owns runtime epoch cancellation/one worker/queue/retire and B final safety; not claiming the C direct commit is formal runtime integration."}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(1 if result.failed else 0)
