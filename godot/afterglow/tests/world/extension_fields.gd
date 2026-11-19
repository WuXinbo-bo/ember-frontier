extends SceneTree
## Small read projections keep public aggregates detached without whole-plan copy.
const Data=preload("res://scripts/world/world_data.gd")
const View=preload("res://scripts/world/world_view.gd")
const State=preload("res://scripts/world/world_state.gd")
const Factory=preload("res://scripts/world/factory_generator.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
class CopyProbe extends "res://scripts/world/world_view.gd":
	var aggregate_reads:int=0
	func extension(id:String)->Variant:
		aggregate_reads+=1
		return super.extension(id)
var checks:Array=[]
var costs:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"costs":costs},"\t",true,true))
	print("extension fields: ",checks.size()," checks, ",failed," failed");quit(0 if failed==0 else 1)
func selected(world:RefCounted,id:String)->Dictionary:
	var fields:Array[String]=["module_seeds","regional_sites"]
	return world.extension_fields(id,fields)
func sample(world:RefCounted,ids:Array,full:bool)->Dictionary:
	var found:int=0;var started:int=Time.get_ticks_usec()
	for repeat_index in 100:
		for id:String in ids:
			var data:Dictionary=world.extension(id) if full else selected(world,id)
			found+=data.get("module_seeds",[]).size()+data.get("regional_sites",[]).size()
	return {"queries":100*ids.size(),"found":found,"usec":Time.get_ticks_usec()-started}
func run()->void:
	var raw:Dictionary={"extensions":{"fixture":{"module_seeds":[{"id":"one","nested":{"values":[1,2]}}],"regional_sites":[{"id":"site"}],"nullable":null,"text":"same","number":3,"unused":{"large":[1,2,3]}},"array":[1,2],"scalar":4,"null":null}}
	var view:=CopyProbe.new(raw)
	check("unknown and empty view project to empty dictionary",view.extension_fields("missing",["module_seeds"]).is_empty() and View.new().extension_fields("missing",[]).is_empty())
	check("non-dictionary extensions project to empty dictionary",view.extension_fields("array",["0"]).is_empty() and view.extension_fields("scalar",["value"]).is_empty() and view.extension_fields("null",["value"]).is_empty())
	check("empty selection returns no extension fields",view.extension_fields("fixture",[]).is_empty())
	var row:Dictionary=view.extension_fields("fixture",["module_seeds","regional_sites","nullable","missing","text","number","module_seeds"])
	check("only selected existing fields are present",row.size()==5 and not row.has("missing") and not row.has("unused"))
	check("present null remains distinct from absent field",row.has("nullable") and row.nullable==null)
	check("selected scalar values retain exact meaning",row.text=="same" and row.number==3)
	row.module_seeds[0].nested.values.append(99);row.regional_sites[0].id="changed";row.number=99
	check("nested selected arrays dictionaries and scalars are detached",raw.extensions.fixture.module_seeds[0].nested.values==[1,2] and raw.extensions.fixture.regional_sites[0].id=="site" and raw.extensions.fixture.number==3)
	raw.extensions.fixture.module_seeds[0].id="two"
	check("next query observes live metadata without caching",selected(view,"fixture").module_seeds[0].id=="two" and view.aggregate_reads==0)
	check("existing extension aggregate semantics are unchanged",view.extension("missing")==null and view.extension("array")==[1,2] and view.extension("scalar")==4)
	var profiles:Array=Catalog.profiles();var configured:Dictionary=Contract.fresh(profiles,4,1)
	var world:=State.new();var loaded:Dictionary=world.load_snapshot(Factory.generate(713,profiles,configured.contract))
	check("actual current4 story world loads",loaded.ok)
	if not loaded.ok:return finish()
	var ids:Array=[];var same:bool=true
	for region:Dictionary in world.regions():
		var id:String="generation:"+str(region.id);ids.append(id)
		var full:Dictionary=world.extension(id);var result:Dictionary=selected(world,id)
		for field:String in ["module_seeds","regional_sites"]:same=same and result.has(field)==full.has(field) and Data.json_equal(result.get(field),full.get(field))
		var seeds:Array=result.get("module_seeds",[])
		if not seeds.is_empty():seeds[0].id="external mutation"
		same=same and Data.json_equal(full,world.extension(id))
	check("actual source receipts story descriptors and regional sites match original aggregate exactly",same)
	var before:Dictionary=world.snapshot();var storage:Dictionary=world.cell_storage_statistics()
	var full_sample:Dictionary=sample(world,ids,true);var field_sample:Dictionary=sample(world,ids,false)
	check("same actual field consumers return equal results without changing facts",full_sample.found==field_sample.found and Data.json_equal(before,world.snapshot()) and world.cell_storage_statistics()==storage)
	var tx:Dictionary=world.prepare_changes([{"op":"extension.set","id":"test:fields","before_exists":false,"before":null,"after":{"module_seeds":[{"id":"draft-only"}],"unused":[1,2]}}],world.get_revision())
	var fields:Array[String]=["module_seeds"]
	check("prepared read view gets isolated selected draft facts",tx.ok and tx.view.extension_fields("test:fields",fields).module_seeds[0].id=="draft-only" and world.extension_fields("test:fields",fields).is_empty(),tx.get("reason"))
	if tx.ok:
		var draft_fields:Dictionary=tx.view.extension_fields("test:fields",fields);draft_fields.module_seeds[0].id="mutated detached"
		check("selected draft aggregate cannot mutate prepared capability",tx.view.extension_fields("test:fields",fields).module_seeds[0].id=="draft-only")
	costs={"whole_plan":full_sample,"selected_fields":field_sample,"scope":"same current4 actual plans and source identities, bounded CPU copy samples; no cross-STEP cache or update reduction, no renderer/FPS/package qualification"}
	finish()
