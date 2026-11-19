extends SceneTree
## Quality change cost disclosure, not an exact-output speedup or frame test.
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const Contract=preload("res://scripts/world/generation_contract.gd")
const State=preload("res://scripts/world/world_state.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Mesher=preload("res://scripts/terrain/terrain_mesher.gd")
const CATALOG="res://data/buildings/generation_profiles.json"
const MODELS=["local-apron-v3","village-contours-v4"]
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"label":label,"ok":ok})
	if not ok:push_error("FAIL "+label)
func run()->void:
	var profiles:Array=JSON.parse_string(FileAccess.get_file_as_string(CATALOG)).profiles
	var contracts:Dictionary={};var sources:Dictionary={};var times:Dictionary={}
	for model:String in MODELS:
		contracts[model]=Contract.fresh(profiles).contract;contracts[model].landscape_model=model
		sources[model]=Landscape.generate(973339546,profiles,contracts[model]);times[model]=[]
	for iteration in 3:
		for model:String in (MODELS if iteration%2==0 else [MODELS[1],MODELS[0]]):
			var started:int=Time.get_ticks_usec()
			var again:Dictionary=Landscape.generate(973339546,profiles,contracts[model])
			times[model].append((Time.get_ticks_usec()-started)/1000.0)
			check("same-model full source repeat "+model+" "+str(iteration),Data.json_equal(again,sources[model]))
	var costs:Dictionary={}
	for model:String in MODELS:
		var world:=State.new();check("actual source loads "+model,world.load_snapshot(sources[model]).ok)
		var original:Dictionary=world.snapshot();var rows:Array=[];var quads:int=0;var keys:Array=world.chunk_keys();keys.sort()
		var complete:bool=true;var started:int=Time.get_ticks_usec()
		for key:String in keys:
			var one:int=Time.get_ticks_usec();var mesh:Dictionary=Mesher.build(world,key)
			rows.append({"chunk":key,"ms":(Time.get_ticks_usec()-one)/1000.0,"quads":mesh.get("quads",0)})
			complete=complete and mesh.ok;quads+=int(mesh.get("quads",0))
		var mesh_ms:float=(Time.get_ticks_usec()-started)/1000.0
		check("full 512-chunk greedy projection preserves facts "+model,complete and keys.size()==512 and Data.json_equal(original,world.snapshot()))
		rows.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.ms<b.ms)
		var sorted:Array=times[model].duplicate();sorted.sort()
		var content:Dictionary={}
		for region:String in ["RH-HOME","RH-VILLAGE"]:
			var plan:Dictionary=world.extension("generation:"+region)
			content[region]={"trees":plan.resource_sites.size(),"patches":plan.ecology.patches.size(),"fields":plan.landforms.filter(func(row:Dictionary)->bool:return row.use=="field").size()}
		costs[model]={"two_region_generation_ms":times[model],"generation_median_ms":sorted[1],"greedy_total_ms":mesh_ms,"greedy_chunk_p95_ms":rows[floori((rows.size()-1)*0.95)].ms,"greedy_chunk_max_ms":rows[-1].ms,"greedy_slowest_five":rows.slice(-5),"greedy_quads":quads,"triangles":quads*2,"persistent_content":content}
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var result:Dictionary={"seed":973339546,"scope":"Same catalogue and seed, one generation warmup/model then three alternating CPU generations and one complete 512-chunk greedy build/model. Different quality geometry, not exact-output optimization; live formal app not touched; not quiet-window/Metal/GPU/FPS or VA qualification.","checks":checks,"failed":failed,"costs":costs}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(1 if failed else 0)
