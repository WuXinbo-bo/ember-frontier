extends SceneTree
## Narrow C-layer probe for the real eighth-run warning; not an alarm replay.
const State=preload("res://scripts/world/world_state.gd")
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Contract=preload("res://scripts/world/generation_contract.gd")
var checks:Array=[]
var details:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func raster(snapshot:Dictionary)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256)
	var keys:Array=snapshot.chunks.keys();keys.sort()
	for key:String in keys:
		h.update(key.to_utf8_buffer());h.update(PackedInt32Array(snapshot.chunks[key].cells).to_byte_array())
	return h.finish().hex_encode()
func without_revision(proof:Dictionary)->Dictionary:
	var result:=proof.duplicate(true);result.erase("world_revision");return result
func at(x:float,y:float,z:float,region:String)->Dictionary:
	return {"x":x,"y":y,"z":z,"regionId":region,"buildingId":null,"storeyId":null}
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2:push_error("expected output and captured-input paths");quit(2);return
	var input:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var profiles:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/generation_profiles.json")).profiles
	var pinned:Dictionary=Contract.fresh(profiles).contract;pinned.landscape_model="local-apron-v3"
	var source:Dictionary=Landscape.generate(int(input.seed),profiles,pinned)
	var world:=State.new();var loaded:Dictionary=world.load_snapshot(source)
	check("real seed973339546 fresh terrain and saved v3 model load",loaded.ok and source.get("seed")==input.seed and source.get("generatorVersion")=="rural-3" and source.get("extensions",{}).get("generation:rural2",{}).get("landscape_model")=="local-apron-v3",loaded)
	if not loaded.ok:return finish(args[0])
	var digest:String=raster(source)
	check("same seed current profiles reproduce complete original terrain and plans",source==Landscape.generate(int(input.seed),profiles))
	# The generated C world intentionally has no A gameplay extension yet. This
	# tests extension.set COW semantics, not the unknown rejected gameplay plan.
	var draft:Dictionary=world.prepare_changes([{"op":"extension.set","id":"r33:gameplay","before_exists":false,"before":null,"after":{"version":1,"diagnostic":"eighth native metadata-only C projection"}}],world.get_revision())
	check("isolated metadata-only extension draft prepares",draft.ok,draft.get("code"))
	if not draft.ok:return finish(args[0])
	var projected:RefCounted=draft.view
	var snapshot:Dictionary=projected.snapshot()
	check("metadata draft keeps all512 chunk records and integer cells exact",snapshot.chunks==source.chunks and raster(snapshot)==digest,{"chunks":snapshot.chunks.size(),"raster_sha256":digest})
	check("metadata draft keeps actual regions entities and both persistent plans exact",snapshot.regions==source.regions and snapshot.entities==source.entities and projected.extension("generation:RH-HOME")==world.extension("generation:RH-HOME") and projected.extension("generation:RH-VILLAGE")==world.extension("generation:RH-VILLAGE"))
	var samples:Array=[];var compared_cells:Dictionary={}
	for sample:Dictionary in input.samples:
		var p:Dictionary=sample.player
		var row:Dictionary={"sample":sample.sample,"window_endpoint":sample.endpoint,"logged_revision":sample.world_revision,"logged_player":p,"logged_support_cell":sample.support_cell,"source_center_surface":world.surface_height(p.x,p.z),"surfaces":[],"envelope_cells":0}
		var surfaces_equal:bool=true;var cells_equal:bool=true
		for dx:float in [-0.26,0.0,0.26]:
			for dz:float in [-0.26,0.0,0.26]:
				var actual:Variant=world.surface_height(float(p.x)+dx,float(p.z)+dz)
				var prepared:Variant=projected.surface_height(float(p.x)+dx,float(p.z)+dz)
				row.surfaces.append({"dx":dx,"dz":dz,"current":actual,"prepared":prepared})
				if actual!=prepared or actual==null:surfaces_equal=false
		for x in range(floori((float(p.x)-0.26)/0.5),floori((float(p.x)+0.26)/0.5)+1):
			for z in range(floori((float(p.z)-0.26)/0.5),floori((float(p.z)+0.26)/0.5)+1):
				for y in range(floori((float(p.y)-0.5)/0.5),ceili((float(p.y)+1.8)/0.5)+1):
					row.envelope_cells+=1;compared_cells[Vector3i(x,y,z)]=true
					if world.cell_at(x,y,z)!=projected.cell_at(x,y,z) or world.is_cell_known(x,y,z)!=projected.is_cell_known(x,y,z) or world.is_cell_resident(x,y,z)!=projected.is_cell_resident(x,y,z):cells_equal=false
		check("current/prepared half-meter surfaces match at nine foot samples "+str(sample.sample)+sample.endpoint,surfaces_equal)
		check("current/prepared material known and resident envelope match "+str(sample.sample)+sample.endpoint,cells_equal)
		samples.append(row)
	var boundaries:Array=[];var proof_equal:bool=true
	for x:float in [1.25,8.25,16.25,32.25,48.25,62.75]:
		var a:=at(x,float(world.surface_height(x,0.25)),0.25,"RH-HOME")
		var b:=at(x,float(world.surface_height(x,-0.25)),-0.25,"RH-VILLAGE")
		for pair:Array in [[a,b],[b,a]]:
			var current:Dictionary=world.continuous_outdoor_step(pair[0],pair[1])
			var prepared:Dictionary=projected.continuous_outdoor_step(pair[0],pair[1])
			var same:bool=without_revision(current)==without_revision(prepared)
			proof_equal=proof_equal and same
			boundaries.append({"from":pair[0],"to":pair[1],"current":current,"prepared":prepared,"equal_except_expected_draft_revision":same})
	check("twelve bidirectional real boundary proofs agree except draft revision",proof_equal)
	check("preparing metadata leaves committed terrain plans entities and regions untouched",world.snapshot()==source)
	world.discard_prepared(draft.capability)
	check("discard leaves source facts and revision untouched",world.snapshot()==source and world.get_revision()==int(source.revision))
	details={"seed":input.seed,"model":world.extension("generation:rural2").landscape_model,"raster_sha256":digest,"sample_points":samples,"compared_unique_envelope_cells":compared_cells.size(),"boundary_proofs":boundaries,"scope":"Fresh deterministic C terrain only; logged window points are not exact warning location. No live world read/write, B station/body replay, actual rejected gameplay plan, app, import/export, or VA/performance qualification."}
	finish(args[0])
func finish(path:String)->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var result:Dictionary={"checks":checks,"failed":failed,"details":details}
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed,"scope":details.get("scope","")}));quit(1 if failed else 0)
