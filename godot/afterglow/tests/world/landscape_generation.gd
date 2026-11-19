extends SceneTree
const Generator=preload("res://scripts/world/landscape_generator.gd")
const Legacy=preload("res://scripts/world/settlement_generator.gd")
const LegacyBefore=preload("res://tests/world/fixtures/rural2_generator_before_landscape.gd")
const Contract=preload("res://scripts/world/generation_contract.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const State=preload("res://scripts/world/world_state.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const EnvironmentView=preload("res://scripts/environment/environment_view.gd")
const Models=preload("res://scripts/environment/ecology_models.gd")
const Codec=preload("res://scripts/world/world_codec.gd")
const Mesher=preload("res://scripts/terrain/terrain_mesher.gd")
const Queries=preload("res://scripts/terrain/terrain_queries.gd")
var checks:Array=[]
var costs:Dictionary={}
var details:Dictionary={}
var codec_max_error:float=0.0
var codec_first_numeric_difference:String=""
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func fingerprint(world:RefCounted)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	var keys:Array=world.chunk_keys();keys.sort()
	for key:String in keys:hash.update(key.to_utf8_buffer());hash.update(PackedInt32Array(world.chunk(key).cells).to_byte_array())
	return hash.finish().hex_encode()
func wire_equal(a:Variant,b:Variant,path:String="world")->bool:
	if a is PackedInt32Array or b is PackedInt32Array:return a==b
	if (a is int or a is float) and (b is int or b is float):
		var difference:float=absf(float(a)-float(b))
		codec_max_error=maxf(codec_max_error,difference)
		if difference>0 and codec_first_numeric_difference.is_empty():codec_first_numeric_difference=path
		return a==b if a is int or b is int else difference<=0.0000000000001
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key:Variant in a:
			if not b.has(key) or not wire_equal(a[key],b[key],path+"."+str(key)):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not wire_equal(a[i],b[i],path+"["+str(i)+"]"):return false
		return true
	return a==b
func run()->void:
	var profiles:Array=Buildings.generation_profiles()
	var old:Dictionary=Legacy.generate(713,profiles);var frozen:Dictionary=LegacyBefore.generate(713,Contract.baseline(profiles))
	check("rural2 complete snapshot matches frozen pre-refactor generator",Data.json_equal(old,frozen))
	var started:=Time.get_ticks_usec();var snapshot:=Rural.generate_settlement(713,profiles)
	costs.generate_dual_region_ms=(Time.get_ticks_usec()-started)/1000.0
	var world:=State.new();var loaded:=world.load_snapshot(snapshot)
	check("explicit new rural3 has independent ID and complete half-metre world",loaded.ok and world.identity().worldId=="rural:v3:713" and world.config().cellSize==0.5,loaded)
	if not loaded.ok:return finish()
	var same:=State.new();same.load_snapshot(Generator.generate(713,profiles))
	check("same seed version coordinates reproduce all cell bytes and ecology facts",fingerprint(world)==fingerprint(same) and Data.json_equal(world.snapshot(),same.snapshot()))
	var different:=State.new();different.load_snapshot(Generator.generate(2026,profiles))
	check("different seed changes actual terrain and stable ecology",fingerprint(world)!=fingerprint(different) and world.entities()!=different.entities())
	var trees:Dictionary={};var patches:=0;var slots:=0
	for tree:Dictionary in world.entities():
		if tree.kind=="tree":trees[tree.data.appearance.model]=int(trees.get(tree.data.appearance.model,0))+1
	check("all three existing species are real harvest tree entities",trees.has_all(["broadleaf_tree","conifer_tree","dead_tree"]),trees)
	for region:Dictionary in world.regions():
		var plan:Dictionary=world.extension("generation:"+str(region.id))
		patches+=plan.ecology.patches.size();slots+=plan.dressing.size()
		check("persisted ecology and physical dressing carry versions "+region.id,plan.ecology.version==1 and plan.dressing_version==1 and plan.dressing_contract_sha256.length()==64,{"patches":plan.ecology.patches.size(),"dressing":plan.dressing,"skipped":plan.dressing_candidate_rejections})
	check("real field understorey and released B scenery slots exist",patches>30 and slots>=8,{"patches":patches,"slots":slots})
	started=Time.get_ticks_usec();var composed:=Assembly.prepare(snapshot)
	costs.actual_A_B_composition_ms=(Time.get_ticks_usec()-started)/1000.0
	check("actual formal assembler accepts C terrain and B buildings props actors",composed.ok,{"code":composed.get("code"),"reason":composed.get("reason")})
	if not composed.ok:return finish()
	world.load_snapshot(composed.capture.world)
	var marker:Dictionary=world.extension("r3:dressing")
	details.dressing=marker
	var placed:=0;var skipped:=0
	for row:Dictionary in marker.get("entries",{}).values():
		if row.status=="placed":placed+=1
		else:skipped+=1
	check("B actual final support collision road actor checks install persistent props",placed>=8,{"placed":placed,"skipped":skipped})
	var models:=Models.new();var assets_ok:=true
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Models.MANIFEST))
	for row:Dictionary in manifest.models:
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(FileAccess.get_file_as_bytes(row.resource))
		assets_ok=assets_ok and hash.finish().hex_encode()==row.sha256 and not models.parts(row.id).is_empty() and models.bounds(row.id).size.y>0
	check("eight original GLB bytes parse into real meshes with original materials",assets_ok and models.failures.is_empty(),models.failures)
	var env:=EnvironmentView.new();root.add_child(env);started=Time.get_ticks_usec();env.configure({"world":world})
	costs.environment_cold_ms=(Time.get_ticks_usec()-started)/1000.0
	check("formal terrain environment component mounts native tree and MultiMesh layers",env.statistics().ecology_patches>20 and env.statistics().missing_models.is_empty(),env.statistics())
	var tree_models:Dictionary={}
	for node:Node3D in env._roots.values():
		for child:Node in node.get_children():
			if child.has_meta("existing_model"):tree_models[child.get_meta("existing_model")]=true
	check("all three tree silhouettes mounted on saved tree IDs",tree_models.has_all(["broadleaf_tree","conifer_tree","dead_tree"]),tree_models.keys())
	var before:=world.snapshot();started=Time.get_ticks_usec();env.sync()
	costs.environment_warm_sync_ms=(Time.get_ticks_usec()-started)/1000.0
	check("derived presentation leaves all world facts unchanged",Data.json_equal(before,world.snapshot()))
	details.environment=env.statistics()
	# Remove the exact surface below one persisted patch, never alter its plan.
	var patch:Dictionary={}
	for region:Dictionary in world.regions():
		for candidate:Dictionary in world.extension("generation:"+str(region.id)).ecology.patches:
			var p:=Vector3(candidate.position.x,candidate.position.y,candidate.position.z)
			if env._grounded(p,Vector2.ONE*float(candidate.footprint[0])*float(candidate.scale)*sqrt(2.0),int(candidate.material)):patch=candidate;break
		if not patch.is_empty():break
	var p:Dictionary=patch.position;var cell:Dictionary={"x":floori(p.x*2),"y":roundi(p.y*2)-1,"z":floori(p.z*2)}
	var material:int=world.cell_at(cell.x,cell.y,cell.z)
	var hit:Dictionary=Queries.pick(world,Vector3(p.x,p.y+3,p.z),Vector3(p.x,p.y-1,p.z))
	check("patch surface is stable actual authoritative target",hit.get("target_id")=="terrain:%d:%d:%d"%[cell.x,cell.y,cell.z])
	var count:int=env.statistics().ecology_patches
	var draft:Dictionary=world.prepare_changes([{"op":"voxel.set","cell":cell,"before":material,"after":0}],world.get_revision())
	if draft.ok:world.commit_prepared(draft.capability)
	env.sync()
	check("dig invalidates actual ground layer without changing persistent layout",draft.ok and env.statistics().ecology_patches<count and world.extension("generation:RH-HOME").ecology==before.extensions["generation:RH-HOME"].ecology)
	draft=world.prepare_changes([{"op":"voxel.set","cell":cell,"before":0,"after":material}],world.get_revision())
	if draft.ok:world.commit_prepared(draft.capability)
	env.sync()
	check("matching fill restores only derived layer with no added resources",draft.ok and env.statistics().ecology_patches==count)
	var encoded:=Codec.encode_checkpoint(world.snapshot(),{"runtime":composed.capture.facts},"test:rural3")
	var decoded:=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
	var restored:=State.new();var accepted:Dictionary=restored.load_snapshot(decoded.state) if decoded.ok else decoded
	var cold_expected:Dictionary=world.snapshot()
	for c:Dictionary in cold_expected.chunks.values():c.resident=false
	var equal:bool=accepted.ok and wire_equal(cold_expected,restored.snapshot())
	check("new landscape metadata and exact cell buffers restore cold",equal,{"code":accepted.get("code"),"max_metadata_numeric_error":codec_max_error,"first_numeric_difference":codec_first_numeric_difference,"cell_buffers_exact":accepted.ok and fingerprint(world)==fingerprint(restored)})
	var repeat:Dictionary=Rural.prepare_region(restored,Vector2i.ZERO,profiles)
	check("explored revised region never rerolls replenishes or adds scenery",repeat.ok and repeat.already_generated and repeat.world_changes.is_empty() and repeat.initial_stocks.is_empty())
	var old_world:=State.new();old_world.load_snapshot(old)
	check("old rural2 prepare dispatch preserves original persistent plan",Rural.prepare_region(old_world,Vector2i.ZERO,profiles).plan==old.extensions["generation:RH-HOME"])
	env.free();finish()
func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var result:Dictionary={"checks":checks,"failed":failed,"costs":costs,"details":details,"scope":"actual C generation and A/B formal assembler/native meshes/collision contracts and memory codec; not formal app OS/Metal/VA"}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(1 if failed else 0)
