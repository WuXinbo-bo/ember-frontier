extends SceneTree
## Metadata readiness is independent of residency and must never load cells.
const Data=preload("res://scripts/world/world_data.gd")
const View=preload("res://scripts/world/world_view.gd")
const State=preload("res://scripts/world/world_state.gd")
const Factory=preload("res://scripts/world/factory_generator.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Codec=preload("res://scripts/world/world_codec.gd")
class CopyProbe extends "res://scripts/world/world_view.gd":
	var aggregate_reads:int=0
	func chunk(id:String)->Dictionary:
		aggregate_reads+=1
		return super.chunk(id)
var checks:Array=[]
var costs:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"costs":costs},"\t"))
	print("chunk metadata readiness: ",checks.size()," checks, ",failed," failed")
	quit(0 if failed==0 else 1)
func apply(world:RefCounted,changes:Array)->Dictionary:
	var tx:Dictionary=world.prepare_changes(changes,world.get_revision())
	return world.commit_prepared(tx.capability) if tx.ok else tx
func sample(world:RefCounted,keys:Array,aggregate:bool)->Dictionary:
	var found:int=0;var started:int=Time.get_ticks_usec()
	for repeat_index in 40:
		for key:String in keys:
			if world.chunk(key).get("generated",false) if aggregate else world.chunk_is_generated(key):found+=1
	return {"usec":Time.get_ticks_usec()-started,"found":found,"queries":40*keys.size()}
func run()->void:
	var fixture:Dictionary={"chunks":{"-1,0,-2":{"generated":true,"resident":false,"cells":[]},"0,0,0":{"generated":false,"resident":true,"cells":[2]},"1,0,0":{"resident":true,"cells":[2]}}}
	var probe:=CopyProbe.new(fixture)
	check("negative known key reads only generated metadata",probe.chunk_is_generated("-1,0,-2"))
	check("unknown key and empty view return false",not probe.chunk_is_generated("missing") and not View.new().chunk_is_generated("0,0,0"))
	check("resident cells never imply generated",not probe.chunk_is_generated("0,0,0") and not probe.chunk_is_generated("1,0,0"))
	fixture.chunks["-1,0,-2"].generated=false
	check("metadata changes are observed without memoization",not probe.chunk_is_generated("-1,0,-2"))
	fixture.chunks["-1,0,-2"].generated=true
	check("restored metadata is observed without memoization",probe.chunk_is_generated("-1,0,-2") and probe.aggregate_reads==0)
	var world:=State.new();var loaded:Dictionary=world.load_snapshot(Factory.generate(713,Catalog.profiles()))
	check("actual generated world loads in sole authority",loaded.ok)
	if not loaded.ok:return finish()
	var region:String="RH-VILLAGE";var keys:Array=world.region_chunk_keys(region)
	check("actual resident chunk lattice reports generated",keys.size()==256 and keys.all(func(key:String)->bool:return world.chunk_is_generated(key)))
	var frozen:Dictionary=world.snapshot();var revision:int=world.get_revision()
	var aggregate:Dictionary=world.chunk(keys[0]);aggregate.generated=false;aggregate.cells[0]=999
	check("existing aggregate API remains detached",world.chunk_is_generated(keys[0]) and world.chunk(keys[0]).cells[0]!=999)
	var before:Dictionary=world.cell_storage_statistics()
	var warm_old:Dictionary=sample(world,keys,true);var warm_new:Dictionary=sample(world,keys,false)
	check("same warm inputs match copied API without changing facts",warm_old.found==warm_new.found and warm_new.found==warm_new.queries and Data.json_equal(frozen,world.snapshot()) and world.get_revision()==revision and world.cell_storage_statistics()==before)
	var cold:Dictionary=world.prepare_region_residency(region,false,world.get_revision())
	check("actual cold conversion prepares",cold.ok)
	if not cold.ok:return finish()
	var prepared:Dictionary=world.prepare_changes(cold.world_changes,world.get_revision())
	check("prepared cold view inherits generated query without warming live source",prepared.ok and prepared.view.chunk_is_generated(keys[0]) and not prepared.view.region_is_resident(region) and world.region_is_resident(region))
	if not prepared.ok:return finish()
	var committed:Dictionary=world.commit_prepared(prepared.capability)
	check("cold pages remain generated while detailed readiness stays false",committed.ok and keys.all(func(key:String)->bool:return world.chunk_is_generated(key)) and not world.region_is_resident(region))
	var cold_before:Dictionary=world.snapshot();before=world.cell_storage_statistics();revision=world.get_revision()
	var cold_old:Dictionary=sample(world,keys,true);var cold_new:Dictionary=sample(world,keys,false)
	check("repeated cold queries do not unpack pages or mutate authority",cold_old.found==cold_new.found and before.cold_page_count==256 and before==world.cell_storage_statistics() and Data.json_equal(cold_before,world.snapshot()) and world.get_revision()==revision,before)
	var encoded:Dictionary=Codec.encode_checkpoint(cold_before,{},"r34:readiness")
	var decoded:Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
	var restored:=State.new();loaded=restored.load_snapshot(decoded.state) if decoded.ok else decoded
	check("codec-restored cold chunks retain exact generated flags",loaded.ok and keys.all(func(key:String)->bool:return restored.chunk_is_generated(key)) and not restored.chunk_is_generated("999,0,-999") and restored.region_residency_state(region).unpacked_bytes==0 and restored.region_residency_state(region).page_chunks==256 and restored.cell_storage_statistics()==before,{"loaded":loaded.ok,"region":restored.region_residency_state(region),"storage":restored.cell_storage_statistics()})
	if not loaded.ok:return finish()
	var warm:Dictionary=restored.prepare_region_residency(region,true,restored.get_revision())
	var warmed:Dictionary=apply(restored,warm.world_changes) if warm.ok else warm
	check("explicit warm restores cells without changing generated meaning",warmed.ok and restored.region_is_resident(region) and keys.all(func(key:String)->bool:return restored.chunk_is_generated(key)) and restored.cell_storage_statistics().cold_page_count==0,{"warmed":warmed.ok,"region":restored.region_residency_state(region),"storage":restored.cell_storage_statistics()})
	check("restored warm lattice equals original cells",keys.all(func(key:String)->bool:return restored.chunk(key).cells==frozen.chunks[key].cells))
	costs={"warm_copied":warm_old,"warm_metadata":warm_new,"cold_copied":cold_old,"cold_metadata":cold_new,"scope":"same-process bounded CPU query samples only, no renderer/frame/performance acceptance"}
	finish()
