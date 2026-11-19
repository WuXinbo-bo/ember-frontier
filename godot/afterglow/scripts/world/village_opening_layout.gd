extends RefCounted
## Content13: one compact restoration settlement, with seeded rural neighbours.
## These persisted layout inputs create no stock, occupants, permissions or work.
const Landscape=preload("res://scripts/world/factory_landscape.gd")
const Orientation=preload("res://scripts/world/factory_parcel_orientation.gd")
const HOME="r35.module.village_home"
const WAREHOUSE="r35.module.village_warehouse"
const WORKSHOP="r35.module.village_workshop"
const WORKSHOP15="r35.module.village_workshop.opening-v15"
const Compact=preload("res://scripts/modules/compact_catalog.gd")
const Families=preload("res://scripts/modules/village_family_catalog.gd")
const Chapter=preload("res://scripts/modules/village_chapter_catalog.gd")
const RegionalArt=preload("res://scripts/modules/village_regional_catalog.gd")
const POLICY="old-village-valley-v1"
const COMPACT_POLICY="compact-village-valley-v17"
const REQUIRED=[HOME,WAREHOUSE,WORKSHOP]

static func variant(seed:int,coord:Vector2i)->int:
	return Landscape.hash_key(seed,"layout","village13:%d:%d"%[coord.x,coord.y])%4

static func lots(seed:int,coord:Vector2i,profiles:Array,content_version:int=13)->Array:
	var result:Array=[];var specs:Array=[]
	if coord==Vector2i.ZERO:
		# Keep heavy traffic on the east; all three opening buildings share
		# short, independently connected approaches and a clear central court.
		var choice:int=variant(seed,coord);var shift:int=choice%2
		specs=[["home",HOME,6+shift,23+shift*2],["woodwork",WORKSHOP15 if content_version in [15,16] else WORKSHOP,6,7+shift],["village-warehouse",WAREHOUSE,19,8+(choice/2)*7],["workyard","r34.module.woodshop_yard_v3",18,36]]
		if content_version==17:
			specs[1]=["woodwork",Compact.WORKSHOP,6,8+shift]
			specs[2]=["village-warehouse",Compact.WAREHOUSE,19,8+shift]
		elif content_version>=18:
			specs[0][1]=Families.HOME
			specs[1]=["woodwork",Families.WORKSHOP,6,8+shift]
			specs[2]=["village-warehouse",Families.WAREHOUSE,19,8+shift]
			if content_version>=20:
				for item:Array in specs:item[1]=Chapter.id_for(str(item[1]))
	elif coord==Vector2i(0,-1):
		# This optional excursion still owns the one finite original seed bag.
		specs=[["store","r34.module.supply_rear_v3",6,24],["neighbor","r34.module.home_roadside_v3",12,6]]
	elif variant(seed,coord)==3:
		specs=[["field-stockyard","r34.module.warehouse_long_v3",6,22]]
	for spec:Array in specs:
		var expected:=RegionalArt.id_for(spec[1],content_version)
		var found:Array=profiles.filter(func(p:Dictionary)->bool:return p.id==expected)
		if found.size()!=1:continue
		var profile:Dictionary=found[0];var id:String=Landscape.region_id(coord)+":"+str(spec[0])
		var p:Dictionary=Orientation.parcel(profile,Vector2(coord.x*64+float(spec[2]),coord.y*64+float(spec[3])),Vector2(coord.x*64+34,coord.y*64+30),id,true)
		p.merge({"id":id,"site_id":spec[0],"profile_id":profile.id,"definition_id":profile.id,"definition_version":profile.version,"geometry_version":profile.geometry_version},true)
		if spec[0]=="workyard":p.placement="space-suggestion-only"
		result.append(p)
	return result

static func decorate_plan(plan:Dictionary)->void:
	plan.opening_version=3;plan.village_layout_policy=POLICY
	var compact:bool=int(plan.get("generation_content_version",1)) in [17,18,19,20,21]
	if compact:plan.village_layout_policy=COMPACT_POLICY
	plan.rural_character=["wooded-foothill","fallow-agricultural-valley","stone-working-slope","abandoned-roadside-yard"][variant(plan.seed,Vector2i(plan.region_coord.x,plan.region_coord.z))]
	if plan.region_id!="RH-HOME":
		# Management hints must describe the selected landscape, rather than
		# advertise another starting village/field in every streamed region.
		plan.spaces=plan.spaces.filter(func(space:Dictionary)->bool:return space.type!="home-terrace" and (space.type!="fields-bunds-ditch" or plan.rural_character=="fallow-agricultural-valley"))
		return
	plan.rural_character="old-village-foothill-valley"
	plan.opening_landmarks={"home":"RH-HOME:home","warehouse":"RH-HOME:village-warehouse","manual_work":"RH-HOME:woodwork","raw_water":"r34:ecology:raw-source:RH-HOME","first_forest":"near-village-grove","outward_route":"RH-HOME:north"}
	plan.expansion_spaces=[{"id":"RH-HOME:residential-expansion","xz":[4,35,15,43],"purpose":"future-housing","reservation":"generation-clear-only; live construction still validates"},{"id":"RH-HOME:production-expansion","xz":[18,34,30,43],"purpose":"future-powered-woodwork","reservation":"generation-clear-only; live construction still validates"}]
	if compact:
		plan.expansion_spaces[1].xz=[27,17,39,26]
		plan.expansion_spaces[1].purpose="stockyard-and-compact-saw-line"
	plan.opening_route=["settle-three-companions","secure-food-and-treated-water","gather-nearby-logs","haul-to-manual-work","saw-boards","restore-existing-warehouse","stabilise-supply","restore-home","repair-radio","expand-production"]
	if int(plan.get("generation_content_version",1))>=20:
		plan.opening_landmarks.starter_supplies="r34:generated:RH-HOME:woodwork:stock:tools"
		plan.opening_landmarks.salvage="RH-HOME:stockyard-content:container"
		plan.opening_route=["settle-three-companions","collect-starter-seeds-and-bucket","secure-food-and-treated-water","gather-nearby-logs","haul-to-manual-work","saw-boards","restore-existing-warehouse","restore-home","stabilise-supply","restore-first-sawmill","repair-radio","expand-production"]

static func resource_bounds(seed:int,coord:Vector2i)->Array:
	# The opening always has its close grove plus this transport-worthy forest.
	# Peripheral regions trade forest density against stone/field development.
	if coord==Vector2i.ZERO:return [45+(variant(seed,coord)%2)*2,21+(variant(seed,coord)/2)*4,62,62,4]
	match variant(seed,coord):
		0:return [44,21,63,63,3]
		1:return [49,42,62,61,5]
		2:return [49,26,61,48,5]
	return [46,32,62,61,4]

static func clear_expansion(plan:Dictionary,x:float,z:float,radius:float)->bool:
	for space:Dictionary in plan.get("expansion_spaces",[]):
		var r:Array=space.xz
		if x>r[0]-radius and x<r[2]+radius and z>r[1]-radius and z<r[3]+radius:return false
	return true
