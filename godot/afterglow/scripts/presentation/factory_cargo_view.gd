extends RefCounted
## Display an actual pack item. Never infer quantity from jobs/reservations.
const Stock=preload("res://scripts/presentation/factory_stock_view.gd")
const Surfaces=preload("res://scripts/presentation/held_tool_view.gd")
const Materials=preload("res://scripts/presentation/factory_materials.gd")
const Regional=preload("res://scripts/presentation/regional_item_visual.gd")
const BUNDLE="res://data/gameplay/props/r1_dropped_bundle.glb"
const BULK=["log","timber","scrap","r34:salvaged_drive_unit","stone_m3","gravel_m3","soil_m3"]

static func actual_items(actor:Dictionary)->Dictionary:
	var result:Dictionary={}
	var pack:Variant=actor.get("pack",{})
	if not pack is Dictionary:return result
	# E confirmed: jobs may stop while physical cargo remains in the same pack.
	# Small personal supplies stay packed unless a real legacy delivery owns them.
	for item:String in BULK:
		if Stock._number(pack.get(item)) and float(pack[item])>0:result[item]=float(pack[item])
	var delivery:Variant=actor.get("pending_delivery",{})
	if not delivery is Dictionary or delivery.get("phase")!="deliver":return result
	var requested:Variant=delivery.get("items",{})
	if not requested is Dictionary:return result
	for item:String in requested:
		if Stock._number(requested[item]) and float(requested[item])>0 and Stock._number(pack.get(item)) and float(pack[item])>0:
			# Metadata remains actual carried amount, never promised task amount.
			result[item]=float(pack[item])
	return result

static func hand_items(actor:Dictionary)->Dictionary:
	# Inventory bulk is not a player's two-hand holding instruction. Preserve
	# NPC cargo presentation, including interrupted deliveries without intent.
	if str(actor.get("id",""))!="player":return actual_items(actor)
	var delivery:Variant=actor.get("pending_delivery",{})
	var pack:Variant=actor.get("pack",{})
	if not delivery is Dictionary or delivery.get("phase")!="deliver" or not pack is Dictionary:return {}
	var requested:Variant=delivery.get("items",{})
	if not requested is Dictionary:return {}
	var result:Dictionary={}
	for item:String in requested:
		if Stock._number(requested[item]) and float(requested[item])>0 and Stock._number(pack.get(item)) and float(pack[item])>0:
			result[item]=float(pack[item])
	return result

static func representative(items:Dictionary)->String:
	for item:String in BULK:
		if items.has(item):return item
	var keys:Array=items.keys();keys.sort()
	return str(keys[0]) if not keys.is_empty() else ""

static func create(item:String)->Node3D:
	var result:=Node3D.new();result.name="CarriedLoad"
	result.set_meta("item_id",item);result.set_meta("quantity_mode","aggregate proxy; actual amount in metadata")
	if not Regional.representation(item).is_empty():
		var part:Node3D=Regional.create(item,Vector3(.48,.42,.35))
		if part==null:result.free();return null
		result.add_child(part);result.set_meta("representation",Regional.representation(item))
	elif item=="log":
		var part:=MeshInstance3D.new();part.mesh=Stock._log_mesh(0.94,0.10)
		part.rotation.z=PI/2;result.add_child(part)
	elif item=="timber":
		for i:int in 3:
			Materials.timber(result,Vector3(0,float(i-1)*0.055,0),Vector3(0.88,0.045,0.16),0)
	elif item=="scrap":
		Surfaces.box(result,Vector3.ZERO,Vector3(0.52,0.065,0.22),"metal")
		var brace:Node3D=Surfaces.box(result,Vector3(0.13,0.085,0),Vector3(0.28,0.04,0.12),"metal");brace.rotation.z=0.28
	elif item=="r34:salvaged_drive_unit":
		var housing:=MeshInstance3D.new()
		housing.mesh=Materials.drive_housing_mesh(0.26,0.12);housing.rotation.z=PI/2;result.add_child(housing)
		var base:MeshInstance3D=Surfaces.box(result,Vector3(0,-0.13,0),Vector3(0.34,0.04,0.22),"metal")
		base.mesh=Surfaces.metric_box(Vector3(0.34,0.04,0.22),1.0);base.material_override=Materials.material("drive_rust")
		Surfaces.box(result,Vector3(0.18,0,0),Vector3(0.13,0.045,0.045),"metal")
	else:
		# Existing sack is a declared fallback for loose soil/stone and small
		# mixed legacy deliveries; it does not pretend to be a log or machine.
		var resource:Variant=load(BUNDLE) if ResourceLoader.exists(BUNDLE,"PackedScene") else null
		if not resource is PackedScene:result.free();return null
		var bundle:Node3D=resource.instantiate();result.add_child(bundle)
		result.set_meta("fallback_resource",BUNDLE)
	return result
