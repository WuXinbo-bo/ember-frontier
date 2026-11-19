extends "res://tests/world/village_contours.gd"
const Hills=preload("res://scripts/world/local_hills.gd")
const Relief=preload("res://scripts/world/local_relief.gd")
const Mesher=preload("res://scripts/terrain/terrain_mesher.gd")
func run()->void:
	var profiles:Array=Building.generation_profiles();var samples:Array=[];var detail:Array=[];var signatures:Dictionary={}
	for iteration in 3:
		for seed:int in [12,713]:
			var order:Array=[Hills.MODEL,Relief.MODEL] if iteration%2==0 else [Relief.MODEL,Hills.MODEL]
			for model:String in order:
				var input:Dictionary=Contract.fresh(profiles).contract;input.landscape_model=model
				var start:=Time.get_ticks_usec();var source:Dictionary=Landscape.generate(seed,profiles,input)
				var elapsed:float=(Time.get_ticks_usec()-start)/1000.0
				var key:String=str(seed)+":"+model;var digest:String=raster_digest(source)
				if signatures.has(key):check("alternating same-input raster exact "+str(iteration)+key,signatures[key]==digest)
				else:signatures[key]=digest
				samples.append({"iteration":iteration,"seed":seed,"model":model,"generate_ms":elapsed,"raster_sha256":digest})
				if iteration!=0:continue
				var world:=State.new();world.load_snapshot(source)
				var quads:=0;var vertices:=0;var groups:=0
				start=Time.get_ticks_usec()
				for chunk:String in world.chunk_keys():
					var mesh:Dictionary=Mesher.build(world,chunk)
					quads+=int(mesh.quads);groups+=mesh.groups.size()
					for g:Dictionary in mesh.groups.values():vertices+=g.vertices.size()
				var row:Dictionary={"seed":seed,"model":model,"single_full_CPU_mesh_ms":(Time.get_ticks_usec()-start)/1000.0,"chunks":source.chunks.size(),"quads":quads,"vertices":vertices,"groups":groups,"raw_source_variant_bytes":var_to_bytes(source).size(),"plan_json_bytes":0,"content":{}}
				for id:String in ["RH-HOME","RH-VILLAGE"]:
					var plan:Dictionary=world.extension("generation:"+id)
					row.plan_json_bytes+=JSON.stringify(plan,"",true,true).to_utf8_buffer().size()
					var species:Dictionary={}
					for site:Dictionary in plan.resource_sites:species[site.appearance.model]=int(species.get(site.appearance.model,0))+1
					row.content[id]={"trees":plan.resource_sites.size(),"species":species,"grove_trees":plan.resource_sites.filter(func(s:Dictionary)->bool:return s.use=="courtyard-forest-edge").size(),"patches":plan.ecology.patches.size(),"fields":plan.landforms.filter(func(l:Dictionary)->bool:return l.use=="field").size(),"dressing":plan.dressing.size()}
				detail.append(row)
	costs.samples=samples;costs.geometry_and_memory=detail
	costs.scope="3 sequential alternating identical pinned input per model/seed full generation CPU samples. v6 and v7 are DIFFERENT world facts/content, not a same-facts optimization or quality qualification. One complete pure-CPU mesher pass each; no ArrayMesh/GPU or native shape timing. Parallel development/no quiet window; not FPS, hard budget or performance qualification. Plan/source bytes are serialized size, not process RSS."
	finish()
