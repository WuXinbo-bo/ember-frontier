extends "res://tests/world/settlement_joint.gd"
const Before=preload("res://tests/world/fixtures/landscape_generator_before_housing.gd")
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Data=preload("res://scripts/world/world_data.gd")
func excluded(plan:Dictionary,x:float,z:float)->bool:
	for pad:Dictionary in plan.grade_controls:
		if Generator._rect_distance(x,z,pad.xz)<1.0:return true
	for land:Dictionary in plan.landforms:
		if Generator._rect_distance(x,z,land.xz)<0.5:return true
	return false
func risers(world:RefCounted)->Dictionary:
	var heights:Dictionary={};var plan:Dictionary=world.extension("generation:RH-HOME")
	for z in 128:
		for x in 128:heights[Vector2i(x,z)]=roundi(world.surface_height((x+0.5)*0.5,(z+0.5)*0.5)*2)
	var longest:=0;var total_long:=0;var runs:Array=[]
	for axis in 2:
		for cross in range(1,128):
			var last:Variant=null;var count:=0
			for along in 129:
				var pair:Variant=null
				if along<128:
					var a:=Vector2i(cross-1,along) if axis==0 else Vector2i(along,cross-1)
					var b:=a+(Vector2i.RIGHT if axis==0 else Vector2i.DOWN)
					if not excluded(plan,(a.x+0.5)*0.5,(a.y+0.5)*0.5) and not excluded(plan,(b.x+0.5)*0.5,(b.y+0.5)*0.5) and heights[a]!=heights[b]:pair=Vector2i(heights[a],heights[b])
				if pair!=last:
					longest=maxi(longest,count)
					if count>=16:total_long+=count;runs.append({"axis":axis,"cross":cross*0.5,"end":along*0.5,"metres":count*0.5,"levels":str(last)})
					count=0;last=pair
				if pair!=null:count+=1
	return {"longest_m":longest*0.5,"total_risers_ge8m_m":total_long*0.5,"runs":runs,"min_y":heights.values().min()*0.5,"max_y":heights.values().max()*0.5}
func run()->void:
	var profiles:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/world/fixtures/generation_profiles_before_housing.json")).profiles
	var old_source:Dictionary=Before.generate(713,profiles)
	var new_source:Dictionary=Landscape.generate(713,profiles)
	var old:=State.new();var revised:=State.new()
	check("same seed original six-profile rural3 terrain pair loads",old.load_snapshot(old_source).ok and revised.load_snapshot(new_source).ok)
	var old_metrics:Dictionary=risers(old);var new_metrics:Dictionary=risers(revised)
	costs.riser_definition="axis-aligned identical exposed height pairs outside pad+1m and deliberate field/bank/ditch+0.5m; no shader/image inference"
	costs.old_actual_cells=old_metrics;costs.new_actual_cells=new_metrics
	check("finite local grading reduces artificial long risers by at least thirty percent",new_metrics.total_risers_ge8m_m<=old_metrics.total_risers_ge8m_m*0.7,{"old":old_metrics.total_risers_ge8m_m,"new":new_metrics.total_risers_ge8m_m})
	check("revised world retains genuine height variation",new_metrics.max_y-new_metrics.min_y>=1.5,new_metrics.max_y-new_metrics.min_y)
	var plan:Dictionary=new_source.extensions["generation:RH-HOME"]
	var unchanged:=true;var outside:=0
	for z in range(-64,128,4):
		for x in range(-64,128,4):
			if plan.grade_controls.any(func(p:Dictionary)->bool:return Generator._rect_distance(x,z,p.xz)<12):continue
			outside+=1;unchanged=unchanged and Generator._bounded_grade(plan,1.2345,x,z)==1.2345
	check("new saved model cannot grade beyond twelve metres of any real pad",unchanged and outside>100,outside)
	var arrival:Dictionary=plan.anchors.arrival
	var footprint:Array=[]
	for dx:float in [-0.26,0.0,0.26]:
		for dz:float in [-0.26,0.0,0.26]:footprint.append({"x":arrival.x+dx,"z":arrival.z+dz,"height":revised.surface_height(arrival.x+dx,arrival.z+dz)})
	var initial_building:=Building.new();var temporary:=Runtime.new();initial_building.configure({"world":revised,"runtime":temporary})
	var generated:Dictionary=initial_building.prepare_generation(revised)
	costs.arrival={"plan":arrival,"actual_nine_columns":footprint,"spawn":generated.get("spawn_points",{}).get("player")}
	var structures:Dictionary=initial_building.structures(revised)
	for change:Dictionary in generated.get("world_changes",[]):
		if change.get("id")==initial_building.EXTENSION:structures=change.after
	var initial_query:RefCounted=initial_building.space(revised,structures)
	var at:=arrival.duplicate();at.regionId="RH-HOME";at.buildingId=null;at.storeyId=null
	costs.arrival.body=initial_query.body_location(at);costs.arrival.standing=initial_query.standing_point(at)
	var assembled:Dictionary=Assembly.prepare(new_source)
	check("same original-profile formal A/B assembly accepts revised authoritative terrain",assembled.ok,assembled.get("reason"))
	if not assembled.ok:return finish()
	var world:=State.new();world.load_snapshot(assembled.capture.world)
	var facts:Dictionary=assembled.capture.facts.duplicate(true);facts.actors=[actor_at(plan.anchors.arrival)]
	var runtime:=Runtime.new();var building:=Building.new()
	check("revised grade uses original sole runtime and real building space",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"production":Production.new(),"actions":Actions.new()}}).ok)
	walk_paths(world,building,"finite apron original seed713")
	var route:Dictionary=walk_home_to_village(runtime,world)
	check("actual old-home to village direct route survives finite local grading",route.ok,route)
	finish()
