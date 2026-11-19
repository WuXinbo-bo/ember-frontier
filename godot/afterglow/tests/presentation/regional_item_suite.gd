extends SceneTree
## New true item identifiers/amounts; no material grants or inventory mutation.
const Regional=preload("res://scripts/presentation/regional_item_visual.gd")
const Stock=preload("res://scripts/presentation/factory_stock_view.gd")
const Cargo=preload("res://scripts/presentation/factory_cargo_view.gd")
var checks:Array=[]
var failures:Array=[]
func expect(label:String,ok:bool,detail:Variant={})->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func first_hit(mesh:ArrayMesh,a:Vector3,b:Vector3)->Variant:
	var nearest:Variant=null
	for s:int in mesh.get_surface_count():
		var arrays:Array=mesh.surface_get_arrays(s)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for i:int in range(0,indices.size(),3):
			var hit:Variant=Geometry3D.segment_intersects_triangle(a,b,vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]])
			if hit!=null and (nearest==null or a.distance_squared_to(hit)<a.distance_squared_to(nearest)):nearest=hit
	return nearest
func run()->void:
	var stock:=Stock.new();root.add_child(stock)
	for item:String in Regional.MAP:
		var row:Dictionary={"stock_ref":"fixture:stock","item_id":item,"unit":"count","representation":Regional.representation(item),"actual":6,"capacity":12,"reserved":4,"extent":Vector3(.9,.75,.7)}
		var before:String=var_to_str(row)
		expect("true item representation accepts "+item,stock.update(row) and stock.statistics().representation==Regional.representation(item))
		expect("actual quantity and reservation stay separate "+item,stock.statistics().actual==6 and stock.statistics().reserved==4 and stock.statistics().visible_parts==3 and var_to_str(row)==before)
		var fits:bool=true
		for part:Node3D in stock._parts:
			var box:AABB=part.transform*part.mesh.get_aabb()
			fits=fits and box.position.x>=-.4501 and box.end.x<=.4501 and box.position.y>=-.0001 and box.end.y<=.7501 and box.position.z>=-.3501 and box.end.z<=.3501
		expect("exact item proxy fits real owner bay "+item,fits)
		var geometry:int=stock._parts[0].get_instance_id()
		row.actual=5;stock.update(row)
		expect("same band reuses real geometry "+item,stock._parts[0].get_instance_id()==geometry)
		row.actual=0;stock.update(row)
		expect("zero actual shows no phantom stock "+item,stock.statistics().visible_parts==0)
		var cargo:Node3D=Cargo.create(item)
		expect("carried representation matches actual item "+item,cargo!=null and cargo.get_meta("item_id")==item and cargo.get_meta("representation")==Regional.representation(item))
		if cargo!=null:cargo.free()
	var row:Dictionary={"stock_ref":"fixture:stock","item_id":"r34:raw_water","unit":"count","representation":"liquid","actual":1,"capacity":4,"extent":Vector3.ONE}
	expect("count water cannot masquerade as open liquid volume",not stock.update(row))
	row.representation="meal"
	expect("raw water cannot borrow meal mesh",not stock.update(row))
	row.representation="crate"
	expect("legacy generic crate DTO gets known exact item shell",stock.update(row) and stock.statistics().representation=="water_can")
	expect("personal raw water is not automatically held cargo",Cargo.hand_items({"id":"npc:1","pack":{"r34:raw_water":2}}).is_empty())
	var carried:Dictionary=Cargo.hand_items({"id":"npc:1","pack":{"r34:raw_water":2},"pending_delivery":{"phase":"deliver","items":{"r34:raw_water":20}}})
	expect("physical delivery reports actual not promised amount",carried.get("r34:raw_water")==2)
	var bucket:ArrayMesh=Regional.mesh("r34:water_bucket")
	var floor_hit:Variant=first_hit(bucket,Vector3(.04,.3,0),Vector3(.04,-.1,0))
	expect("reusable empty bucket shows floor below open interior",floor_hit!=null and floor_hit.y<.02)
	expect("reusable bucket handle keeps a real opening",first_hit(bucket,Vector3(0,.34,-.2),Vector3(0,.34,.2))==null)
	var bracket:ArrayMesh=Regional.mesh("r34:metal_fitting")
	expect("bracket base bolt hole is actual empty geometry",first_hit(bracket,Vector3(.045,.1,.04),Vector3(.045,-.1,.04))==null)
	expect("bracket upright bolt hole is actual empty geometry",first_hit(bracket,Vector3(.045,.07,-.2),Vector3(.045,.07,.2))==null)
	var beam:ArrayMesh=Regional.mesh("r34:structural_timber")
	expect("structural mortise is actual empty geometry",first_hit(beam,Vector3(.15,.3,0),Vector3(.15,-.1,0))==null)
	expect("structural member retains solid thick body",first_hit(beam,Vector3(0,.3,0),Vector3(0,-.1,0))!=null)
	stock.free();await process_frame
	var result:Dictionary={"scope":"actual item IDs, explicit stock DTO and native mesh CPU bounds, not owner workflow/GPU/VA/OS/FPS","checks":checks,"failures":failures}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DDD_REGIONAL_ITEM ",JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
