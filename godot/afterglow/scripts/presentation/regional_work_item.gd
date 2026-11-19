extends RefCounted
## Read the currently disclosed worker pack, never task promise or future output.
const Item=preload("res://scripts/presentation/regional_item_visual.gd")
static func item_for(actor:Dictionary,work:Dictionary)->String:
	if work.get("owner")!="zonework" or work.get("kind")!="zonework" or not work.get("available",false) or not work.get("active",false):return ""
	var item:String={"draw_raw_water":"r34:water_bucket","water":"r34:raw_water"}.get(str(work.get("operation","")),"")
	if item.is_empty():return ""
	if item=="r34:raw_water":
		# The accepted owner's material source must actually be this pack.
		# A nearby stock paying for work cannot borrow a personal can's image.
		var cost:Variant=work.get("cost")
		if work.get("source_id")!="pack:"+str(actor.get("id","")) or not cost is Dictionary:return ""
		var required:Variant=cost.get(item)
		if not (required is int or required is float) or not is_finite(float(required)) or float(required)!=1.0:return ""
	var pack:Variant=actor.get("pack")
	if not pack is Dictionary:return ""
	var quantity:Variant=pack.get(item)
	if not (quantity is int or quantity is float) or not is_finite(float(quantity)) or float(quantity)<1:return ""
	return item

static func create(item:String)->Node3D:
	if item not in ["r34:water_bucket","r34:raw_water"]:return null
	var anchor:=Node3D.new();anchor.name="RegionalWorkingContainer"
	var model:=MeshInstance3D.new();model.mesh=Item.mesh(item)
	# The delivered mesh handle centre is the real hand attachment.
	model.position=Vector3(0,-.425 if item=="r34:water_bucket" else -.4,0);anchor.add_child(model)
	anchor.set_meta("item_id",item);anchor.set_meta("quantity_mode","one actual reusable tool, not water volume" if item=="r34:water_bucket" else "aggregate proxy for actual pack raw water, not a granted bucket or water volume")
	return anchor
