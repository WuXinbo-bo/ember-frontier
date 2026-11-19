extends "res://tests/world/settlement_joint.gd"
## Actual fresh selection, B recipes, real body routes and persisted C terrain.
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const Contract=preload("res://scripts/world/generation_contract.gd")
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Terrain=preload("res://scripts/terrain/terrain_service.gd")
const Data=preload("res://scripts/world/world_data.gd")
func first_difference(a:Variant,b:Variant,path:String="plan")->Dictionary:
	if a is Dictionary and b is Dictionary:
		for key:Variant in a:
			if not b.has(key):return {"path":path+"."+str(key),"reason":"missing in right"}
			var found:Dictionary=first_difference(a[key],b[key],path+"."+str(key))
			if not found.is_empty():return found
		return {} if a.size()==b.size() else {"path":path,"reason":"extra right keys"}
	if a is Array and b is Array:
		if a.size()!=b.size():return {"path":path,"reason":"array length"}
		for i in a.size():
			var found:Dictionary=first_difference(a[i],b[i],path+"["+str(i)+"]")
			if not found.is_empty():return found
		return {}
	return {} if Data.json_equal(a,b) else {"path":path,"left":a,"right":b}
func run()->void:
	var profiles:Array=Building.generation_profiles()
	var ids:Array=profiles.map(func(row:Dictionary)->String:return row.id)
	check("B real compact and courtyard profiles are delivered",ids.has("homestead_compact") and ids.has("homestead_courtyard"),ids)
	if not ids.has("homestead_compact") or not ids.has("homestead_courtyard"):return finish()
	var cases:Array=[{"seed":6,"home":"homestead_compact"},{"seed":12,"home":"homestead_courtyard"}]
	for sample:Dictionary in cases:
		var started:=Time.get_ticks_usec()
		var source:Dictionary=Landscape.generate(sample.seed,profiles)
		costs[str(sample.seed)+"_dual_generation_ms"]=(Time.get_ticks_usec()-started)/1000.0
		check("fresh actual dual terrain generates seed "+str(sample.seed),source.has("worldId"),source.get("reason"))
		if not source.has("worldId"):return finish()
		var config:Dictionary=source.extensions["generation:rural2"]
		var home:Dictionary=source.extensions["generation:RH-HOME"]
		var village:Dictionary=source.extensions["generation:RH-VILLAGE"]
		check("fresh persistent HOME actually selects "+sample.home,home.parcels[0].profile_id==sample.home and config.profile_ids.size()==8 and config.residential_selection.version==2,home.parcels[0])
		var repeat:Dictionary=Landscape.plan_region(sample.seed,Vector2i.ZERO,profiles,config)
		costs[str(sample.seed)+"_raw_plan_raster_difference"]=first_difference(home,repeat.get("plan",{}))
		var repeat_draft:Dictionary=Landscape.draft_region(sample.seed,Vector2i.ZERO,profiles,config)
		check("same seed saved contract reproduces actual complete rasterized plan "+sample.home,repeat_draft.ok and Data.json_equal(home,repeat_draft.plan))
		check("dual regions use identical selected-family grade controls "+sample.home,Data.json_equal(home.grade_controls,village.grade_controls))
		started=Time.get_ticks_usec()
		var assembled:Dictionary=Assembly.prepare(source)
		costs[str(sample.seed)+"_actual_A_B_assembly_ms"]=(Time.get_ticks_usec()-started)/1000.0
		check("formal A/B assembler installs real new recipe "+sample.home,assembled.ok,{"code":assembled.get("code"),"reason":assembled.get("reason")})
		if not assembled.ok:return finish()
		var world:=State.new();world.load_snapshot(assembled.capture.world)
		var runtime:=Runtime.new();var building:=Building.new()
		var facts:Dictionary=assembled.capture.facts.duplicate(true)
		# Isolated domain route fixture only: do not call this OS birth/tool play.
		facts.actors=[actor_at(home.anchors.arrival)]
		var ready:Dictionary=runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"terrain":Terrain.new(),"production":Production.new(),"actions":Actions.new()}})
		check("sole actual runtime accepts new family assembled facts "+sample.home,ready.ok,ready.get("reason"))
		if not ready.ok:return finish()
		var marker:Dictionary=world.extension("r3:building-generation")
		var structures:Dictionary=building.structures(world)
		var pieces:Array=structures.instances.filter(func(piece:Dictionary)->bool:return piece.buildingId=="RH-HOME:home" and piece.get("presentation",{}).get("profile_id")==sample.home)
		check("new profile is real persistent B geometry instead of empty metadata "+sample.home,marker.parcels["RH-HOME:home"].profile_id==sample.home and pieces.size()>30,{"pieces":pieces.size(),"parcels":marker.parcels.keys()})
		var query:RefCounted=building.current_space()
		var unsupported:Array=[];var invalid_ports:Array=[]
		for region_id:String in ["RH-HOME","RH-VILLAGE"]:
			for parcel:Dictionary in world.extension("generation:"+region_id).parcels:
				var profile:Dictionary=profiles.filter(func(row:Dictionary)->bool:return row.id==parcel.profile_id)[0]
				for rect:Array in profile.foundation.pad_rectangles:
					for x in range(floori(rect[0]*2),ceili(rect[2]*2)):
						for z in range(floori(rect[1]*2),ceili(rect[3]*2)):
							var wx:float=parcel.origin.x+(x+0.5)*0.5;var wz:float=parcel.origin.z+(z+0.5)*0.5
							if world.surface_height(wx,wz)!=parcel.origin.y and unsupported.size()<8:unsupported.append({"parcel":parcel.id,"x":wx,"z":wz,"expected":parcel.origin.y,"actual":world.surface_height(wx,wz)})
				for port:Dictionary in parcel.entrance_ports:
					var at:Dictionary=port.position.duplicate();at.merge({"regionId":region_id,"buildingId":null,"storeyId":null})
					if query.standing_point(at).is_empty():invalid_ports.append({"parcel":parcel.id,"port":port})
		check("all real B foundation rectangles have authoritative half-metre support "+sample.home,unsupported.is_empty(),unsupported)
		check("all transformed entrance ports support actual B standing bodies "+sample.home,invalid_ports.is_empty(),invalid_ports)
		walk_paths(world,building,"new residential "+sample.home)
		var route:Dictionary=walk_home_to_village(runtime,world)
		check("actual direct runtime traverses new HOME to village road "+sample.home,route.ok,route)
		var path:Dictionary=home.paths.filter(func(row:Dictionary)->bool:return row.id=="RH-HOME:north")[0]
		var point:Dictionary=path.points[3]
		var cx:int=floori(point.x*2);var cz:int=floori(point.z*2)
		var cy:int=roundi(world.surface_height((cx+0.5)*0.5,(cz+0.5)*0.5)*2)-1
		var material:int=world.cell_at(cx,cy,cz)
		var before_plan:Dictionary=world.extension("generation:RH-HOME")
		var before_plan_wire:Dictionary=JSON.parse_string(JSON.stringify(before_plan,"",true,true))
		var change:Dictionary=world.prepare_changes([{"op":"voxel.set","cell":{"x":cx,"y":cy,"z":cz},"before":material,"after":0}],world.get_revision())
		if change.ok:world.commit_prepared(change.capability)
		check("actual C edit fixture changes one saved road cell without rerolling house "+sample.home,change.ok and world.cell_at(cx,cy,cz)==0 and Data.json_equal(before_plan,world.extension("generation:RH-HOME")),change.get("code"))
		var encoded:Dictionary=Codec.encode_checkpoint(world.snapshot(),{"runtime":runtime.facts()},"test:housing:"+str(sample.seed))
		var decoded:Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
		var restored:=State.new();var loaded:Dictionary=restored.load_snapshot(decoded.state) if decoded.ok else decoded
		var input:Dictionary=OldGenerator.region_generation_input(restored,profiles) if loaded.ok else loaded
		check("real codec restores selected house contract and actual modified cell "+sample.home,loaded.ok and input.ok and restored.cell_at(cx,cy,cz)==0 and Data.json_equal(config,restored.extension("generation:rural2")),input.get("code"))
		if not input.ok:return finish()
		var revisit:Dictionary=OldGenerator.prepare_region(restored,Vector2i.ZERO,[])
		costs[str(sample.seed)+"_codec_raw_metadata_difference"]=first_difference(before_plan,restored.extension("generation:RH-HOME"))
		check("cold revisit does not move new house or replenish its stocks "+sample.home,revisit.ok and revisit.already_generated and revisit.world_changes.is_empty() and revisit.initial_stocks.is_empty() and Data.json_equal(before_plan_wire,restored.extension("generation:RH-HOME")))
		var before:Dictionary=restored.snapshot()
		var restored_runtime:=Runtime.new();var restored_building:=Building.new()
		var reconfigured:Dictionary=restored_runtime.configure({"world":restored,"facts":decoded.extensions.runtime,"services":{"buildings":restored_building,"terrain":Terrain.new(),"production":Production.new(),"actions":Actions.new()}})
		check("saved B marker prevents reassembly of new family after restore "+sample.home,reconfigured.ok and restored_building.prepare_generation(restored).get("code")=="ALREADY_SEEDED" and Data.json_equal(before,restored.snapshot()))
		var east:Dictionary=Landscape.plan_region(sample.seed,Vector2i(1,0),input.profiles,input.generation_contract)
		var west:Dictionary=Landscape.plan_region(sample.seed,Vector2i(-1,0),input.profiles,input.generation_contract)
		var seam:float=0
		if east.ok and west.ok:
			for z in 128:
				var wz:float=(z+0.5)*0.5
				seam=maxf(seam,absf(Generator.planned_surface(home,63.75,wz).height-Generator.planned_surface(east.plan,64.25,wz).height))
				seam=maxf(seam,absf(Generator.planned_surface(west.plan,-0.25,wz).height-Generator.planned_surface(home,0.25,wz).height))
		check("new selected pads keep both coordinate borders within one voxel "+sample.home,east.ok and west.ok and seam<=0.5,seam)
	finish()
