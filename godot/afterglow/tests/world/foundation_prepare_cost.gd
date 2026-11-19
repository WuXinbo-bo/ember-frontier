extends "res://tests/buildings/legacy_suite.gd"
## Same preserved source and real Runtime.command -> .4s completion on both
## authorities. Only the C implementation differs; B safety is never stubbed.
const Before=preload("res://tests/world/fixtures/prepare_20261115_instrumented.gd")
const Data=preload("res://scripts/world/world_data.gd")
const DOOR="world:713:region:0:0:convenience-store:piece:34"
class BeforeWorld extends Before:
	var samples:Array=[]
	func prepare_changes(ops:Array,revision:int)->Dictionary:
		var t:=Time.get_ticks_usec();var result:=super.prepare_changes(ops,revision)
		samples.append({"usec":Time.get_ticks_usec()-t,"stages":stages.duplicate(),"operations":ops.map(func(op:Dictionary):return op.op+":"+str(op.get("id",""))),"ok":result.ok})
		return result
class AfterWorld extends "res://scripts/world/world_state.gd":
	var samples:Array=[]
	func prepare_changes(ops:Array,revision:int)->Dictionary:
		var t:=Time.get_ticks_usec();var result:=super.prepare_changes(ops,revision)
		samples.append({"usec":Time.get_ticks_usec()-t,"operations":ops.map(func(op:Dictionary):return op.op+":"+str(op.get("id",""))),"ok":result.ok})
		return result

func run()->void:
	var path:="res://../../work/r3-2/ordinary-source-713/checkpoint.v5.json"
	var raw:=FileAccess.get_file_as_string(path)
	var decoded:=Codec.decode_checkpoint(raw)
	expect("original six-region source decodes",decoded.ok)
	if not decoded.ok:quit(1);return
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var rows:Array=[]
	var metadata_rows:Array=[]
	var pair:Array=[BeforeWorld.new(),AfterWorld.new()]
	for world:RefCounted in pair:world.load_snapshot(imported.world)
	for sample in 7:
		for variant:int in ([0,1] if sample%2==0 else [1,0]):
			var world:RefCounted=pair[variant]
			var t:=Time.get_ticks_usec();var detached:Dictionary=world.snapshot()
			var snapshot_us:=Time.get_ticks_usec()-t
			expect("snapshot unchanged same original facts",detached.revision==imported.world.revision)
			world.samples.clear()
			var metadata:Dictionary=world.prepare_changes([{"op":"extension.set","id":"test:C:metadata-only","before_exists":false,"before":null,"after":{"cursor":sample}}],world.get_revision())
			expect("pure metadata real authority prepares",metadata.ok)
			if metadata.ok:world.discard_prepared(metadata.capability)
			metadata_rows.append({"sample":sample,"warmup":sample<2,"variant":"before" if variant==0 else "after","snapshot_usec":snapshot_us,"prepare":world.samples.duplicate(true)})
	pair.clear()
	for sample in 4:
		for side in 2:
			var finals:Array=[]
			for variant:int in ([0,1] if sample%2==0 else [1,0]):
				var world:RefCounted=BeforeWorld.new() if variant==0 else AfterWorld.new()
				expect("source loads %d/%d/%d"%[sample,side,variant],world.load_snapshot(imported.world).ok)
				var building:=Building.new();var runtime:=Runtime.new()
				var services:Dictionary={"buildings":building,"actions":Actions.new(),"production":Production.new()}
				expect("full runtime configures %d/%d/%d"%[sample,side,variant],runtime.configure({"world":world,"facts":imported.facts,"services":services}).ok)
				var q:RefCounted=building.space();var points:Array=q.use_points(q.by_id[DOOR]);var facts:=runtime.facts()
				for a:Dictionary in facts.actors:
					if a.id=="player":a.merge(q.standing_point(points[side]),true);a.intent=null
				expect("explicit real supported side configures",runtime.configure({"world":world,"facts":facts,"services":services}).ok)
				world.samples.clear()
				var t:=Time.get_ticks_usec();var started:=runtime.command({"command_id":"C:prepare-cost:"+str(side),"actor_id":"player","kind":"door","target_id":DOOR,"payload":{"operation":"open"}})
				var start_us:=Time.get_ticks_usec()-t
				expect("actual E starts with complete safety",started.ok)
				for i in 3:runtime.tick(0.1)
				world.samples.clear();t=Time.get_ticks_usec();runtime.tick(0.1)
				var completion_us:=Time.get_ticks_usec()-t
				expect("actual E completes and clears intent",building.instance(DOOR).door.open and runtime.actor("player").intent==null)
				rows.append({"sample":sample,"warmup":sample==0,"side":side,"variant":"before" if variant==0 else "after","start_usec":start_us,"completion_usec":completion_us,"prepare":world.samples.duplicate(true)})
				finals.append({"world":world.snapshot(),"facts":runtime.facts()})
			expect("paired complete world and all runtime facts equal %d/%d"%[sample,side],Data.json_equal(finals[0],finals[1]))
	var result:Dictionary={"failed":checks.filter(func(c:Dictionary):return not c.ok).size(),"checks":checks,"rows":rows,"metadata_rows":metadata_rows,"input_sha256":raw.sha256_text(),"scope":"Same-process alternating actual old 6-region source; door sample0 and metadata sample0/1 warmup excluded; no app/FPS/Metal/quiet qualification. Before fixture byte-preserved with test-only phase timers. Every runtime still executes current complete B safety. Public snapshot and pure metadata rows are separate measured operations, not substitutes for the complete door commit."}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(1 if failed else 0)
