extends "res://tests/world/factory_country.gd"
## Actual finite C generation/storage scope. No copied B catalogue, fabricated
## modules/people, renderer, A scheduler or whole-game scale qualification.
var profiles:Array=[]
var policy:Dictionary={}

func region_digest(world:RefCounted,id:String)->Dictionary:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	var keys:Array=world.region_chunk_keys(id);keys.sort()
	for key:String in keys:hash.update(key.to_utf8_buffer());hash.update(world.chunk(key).cells.to_byte_array())
	return {"raster_sha256":hash.finish().hex_encode(),"plan_sha256":Contract.digest(world.extension("generation:"+id))}

func order(reverse:bool)->Array:
	var remaining:Array=[];var result:Array=[];var known:Array=[Vector2i.ZERO,Vector2i(0,-1)]
	for z in range(-2,3):
		for x in range(-2,3):
			var at:=Vector2i(x,z)
			if at not in known and at!=Vector2i(2,2):remaining.append(at)
	if reverse:remaining.reverse()
	while not remaining.is_empty():
		var chosen:int=-1
		for i in remaining.size():
			if known.any(func(p:Vector2i)->bool:return absi(p.x-remaining[i].x)+absi(p.y-remaining[i].y)==1):chosen=i;break
		if chosen<0:return []
		var point:Vector2i=remaining.pop_at(chosen);known.append(point);result.append(point)
	return result

func build(reverse:bool)->Dictionary:
	var world:=State.new();var source:Dictionary=Factory.generate(713,profiles,policy)
	var loaded:Dictionary=world.load_snapshot(source);source.clear()
	if not loaded.ok:return loaded
	var coords:Array=order(reverse);var route:Array=[];var rows:Array=[]
	for coord:Vector2i in coords:
		var began:int=Time.get_ticks_usec()
		var input:Dictionary=Factory.region_generation_input(world,profiles)
		var draft:Dictionary=Factory.draft_region_request(input,coord) if input.ok else input
		var ready:Dictionary=Factory.prepare_region_draft(world,draft,world.get_revision()) if draft.ok else draft
		var tx:Dictionary=world.prepare_changes(ready.world_changes,world.get_revision()) if ready.ok else ready
		var done:Dictionary=world.commit_prepared(tx.capability) if tx.ok else tx
		if not done.ok:return done.merged({"coord":str(coord)})
		rows.append({"coord":[coord.x,coord.y],"generate_usec":draft.cost.get("generate_usec",draft.cost.get("total_usec",0)),"full_data_path_usec":Time.get_ticks_usec()-began,"chunks":draft.chunks.size()})
		route.append([coord.x,coord.y])
	var ids:Array=[];var fingerprints:Dictionary={};var spaces:Dictionary={};var unique_entities:Dictionary={};var stable:bool=true
	for region:Dictionary in world.regions():
		ids.append(region.id);fingerprints[region.id]=region_digest(world,region.id)
		var plan:Dictionary=world.extension("generation:"+str(region.id));var kinds:Dictionary={}
		for space:Dictionary in plan.spaces:kinds[space.type]=true
		spaces[region.id]=kinds.keys();stable=stable and kinds.size()==6 and world.region_is_resident(region.id)
		for e:Dictionary in world.entities(region.id):
			if unique_entities.has(e.id):stable=false
			unique_entities[e.id]=true
	var seams:bool=true;var seam_count:int=0
	for region:Dictionary in world.regions():
		var at:Dictionary=region.data.regionCoord;var coord:=Vector2i(at.x,at.z)
		var plan:Dictionary=world.extension("generation:"+str(region.id))
		for direction:String in ["east","south"]:
			var delta:Vector2i=Vector2i.RIGHT if direction=="east" else Vector2i.DOWN
			var neighbor_id:String=Factory.region_id(coord+delta)
			if world.region(neighbor_id).is_empty():continue
			var other:Dictionary=world.extension("generation:"+neighbor_id)
			var p:Dictionary=plan.road_ports.filter(func(v:Dictionary)->bool:return v.direction==direction)[0]
			var q:Dictionary=other.road_ports.filter(func(v:Dictionary)->bool:return v.direction==("west" if direction=="east" else "north"))[0]
			seams=seams and p.id==q.id and Data.json_equal(p.position,q.position)
			for i in 128:
				var x:float=region.bounds.max.x if direction=="east" else region.bounds.min.x+(i+0.5)*0.5
				var z:float=region.bounds.min.z+(i+0.5)*0.5 if direction=="east" else region.bounds.max.z
				var a:float=world.surface_height(x-(0.25 if direction=="east" else 0.0),z-(0.25 if direction=="south" else 0.0))
				var b:float=world.surface_height(x+(0.25 if direction=="east" else 0.0),z+(0.25 if direction=="south" else 0.0))
				seams=seams and absf(a-b)<=0.5
			seam_count+=1
	var input:Dictionary=Factory.region_generation_input(world,profiles)
	var overflow:Dictionary=Factory.draft_region_request(input,Vector2i(2,2))
	var rejected:Dictionary=Factory.prepare_region_draft(world,overflow,world.get_revision()) if overflow.ok else overflow
	var storage:Dictionary=world.cell_storage_statistics()
	var checkpoint:Dictionary=Codec.encode_checkpoint(world.snapshot(),{},"r34:scale:"+str(reverse))
	var restore_ok:bool=false;var saved_bytes:int=0
	var decoded_restore_exact:bool=false;var restored_records_exact:bool=false;var future_lock_code:String=""
	if checkpoint.ok:
		saved_bytes=checkpoint.envelope.payloadBytes
		var decoded:Dictionary=Codec.decode_checkpoint(checkpoint.envelope)
		if decoded.ok:
			var cold:=State.new();var restored:Dictionary=cold.load_snapshot(decoded.state)
			restore_ok=restored.ok
			if restored.ok:
				decoded_restore_exact=Data.json_equal(decoded.state,cold.snapshot())
				restored_records_exact=Data.json_equal(world.identity(),cold.identity()) and Data.json_equal(world.config(),cold.config()) and Data.json_equal(world.extension(Factory.CONFIG_KEY),cold.extension(Factory.CONFIG_KEY)) and Data.json_equal(world.snapshot().regions,decoded.state.regions) and Data.json_equal(world.snapshot().entities,decoded.state.entities) and Data.json_equal(world.retired_entity_ids(),cold.retired_entity_ids())
				future_lock_code=str(Factory.prepare_region_draft(cold,overflow,cold.get_revision()).get("code"))
				for id:String in ids:
					var same_region:bool=region_digest(cold,id)==fingerprints[id]
					restore_ok=restore_ok and same_region
	return {"ok":true,"regions":world.regions().size(),"chunks":world.chunk_keys().size(),"route":route,"fingerprints":fingerprints,"six_spaces_all_resident_unique_entities":stable,"adjacent_seams_ok":seams,"adjacent_seams":seam_count,"capacity_refused":rejected.get("code")=="GENERATION_CAPACITY","storage":storage,"save_ok":checkpoint.ok,"save_code":checkpoint.get("code"),"payload_bytes":saved_bytes,"restore_exact":restore_ok,"decoded_restore_exact":decoded_restore_exact,"restored_records_exact":restored_records_exact,"future_locked_worker_code":future_lock_code,"samples":rows}

func run()->void:
	var args:Array=OS.get_cmdline_user_args()
	if args.size()<2:check("explicit original normal-route checkpoint is required",false);return finish()
	var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(str(args[1])))
	var native:Variant=JSON.parse_string(raw.payload) if raw is Dictionary else null
	var decoded:Dictionary=Codec.decode_checkpoint(native.world) if native is Dictionary else {"ok":false}
	check("real archived source gives immutable old profile and content lock",decoded.ok)
	if not decoded.ok:return finish()
	policy=decoded.state.extensions[Factory.CONFIG_KEY];profiles=policy.profile_input
	var first:Dictionary=build(false)
	check("first legal adjacent exploration reaches configured actual 24-region data limit",first.ok and first.regions==24 and first.chunks==6144,first.get("reason"))
	if not first.ok:return finish()
	check("all first-order regions retain six spaces full lattices and unique entity ownership",first.six_spaces_all_resident_unique_entities)
	check("all positive negative shared faces and ports match at scale",first.adjacent_seams_ok and first.adjacent_seams>=30,first.adjacent_seams)
	check("25th real draft cannot exceed finite generation capacity",first.capacity_refused)
	check("actual maximum C world checkpoint fits and restores every raster and plan",first.save_ok and first.restore_exact,{"code":first.save_code,"payload_bytes":first.payload_bytes})
	var second:Dictionary=build(true)
	check("opposite legal adjacent exploration also reaches actual limit",second.ok and second.regions==24 and second.chunks==6144,second.get("reason"))
	if second.ok:
		check("opposite orders preserve every full region raster and saved plan",Data.json_equal(first.fingerprints,second.fingerprints) and first.route!=second.route)
		check("reverse order shares real seams unique ownership and capacity safety",second.six_spaces_all_resident_unique_entities and second.adjacent_seams_ok and second.capacity_refused)
		check("reverse-order native checkpoint restores exact generated facts",second.save_ok and second.restore_exact)
	costs={"forward":first,"reverse":second,"scope":"actual C 24-region/6144-chunk voxel/plan/native codec scale only; same archived immutable production profiles, no actual B module registration/NPC/economy/render/RSS or formal performance qualification"}
	finish()
