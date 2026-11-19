extends SceneTree
## Actual consumer meshes, explicit metric owner DTOs, no stock authority or VA.
const Stock=preload("res://scripts/presentation/factory_stock_view.gd")
var checks:Array=[]
var failures:Array=[]
var observations:Array=[]
func expect(label:String,ok:bool,evidence:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"evidence":evidence})
	if not ok:failures.append(label);print("FAIL ",label," ",JSON.stringify(evidence))
func _initialize()->void:call_deferred("run")
func run()->void:
	for extent:Vector3 in [Vector3(.34,.36,.32),Vector3(.40,.38,1.30),Vector3(.40,.38,.48),Vector3(.34,.38,.375)]:
		for kind:String in Stock.KINDS:
			for turn:int in 4:test_bay(kind,extent,turn)
	var report:Dictionary={"scope":"actual stock consumer mesh support and layer contact under explicit finite DTOs; not actual B bay placement, owner economy, OS or VA","checks":checks,"failures":failures,"observations":observations}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DDD_STOCK_SUPPORT "+JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
func test_bay(kind:String,extent:Vector3,turn:int)->void:
	var stock:=Stock.new();root.add_child(stock)
	stock.position=Vector3(5,.17,8);stock.rotation.y=-turn*PI/2
	var row:Dictionary={"stock_ref":"fixture:stock","item_id":"fixture:"+kind,"unit":"l" if kind=="liquid" else "m3","actual":0.0,"capacity":10.0,"representation":kind,"extent":extent}
	var tag:String=kind+" "+str(extent)+" q"+str(turn)
	expect("real consumer accepts finite metric bay "+tag,stock.update(row))
	expect("zero owner stock produces no visible commodity "+tag,stock.statistics().visible_parts==0)
	var geometry_id:int=stock._parts[0].get_instance_id()
	for amount:float in [1.0,10.0]:
		row.actual=amount;stock.update(row)
		var boxes:Array[AABB]=[];var supported:=true;var bounded:=true;var max_gap:float=0;var horizontal_escape:float=0
		for part:MeshInstance3D in stock._parts:
			var box:AABB=part.transform*part.mesh.get_aabb();boxes.append(box)
			bounded=bounded and box.position.y>=-0.00001 and box.end.y<=extent.y+0.00001
			horizontal_escape=maxf(horizontal_escape,maxf(maxf(-extent.x*.5-box.position.x,box.end.x-extent.x*.5),maxf(-extent.z*.5-box.position.z,box.end.z-extent.z*.5)))
		for i:int in boxes.size():
			var bottom:float=boxes[i].position.y
			var top_below:float=0.0 if i<3 else boxes[i-3].end.y
			var gap:float=absf(bottom-top_below);max_gap=maxf(max_gap,gap)
			supported=supported and gap<0.00001
		var expected:int=1 if kind=="liquid" else Stock.BAND_COUNTS[Stock.band(amount,10)]
		expect("actual mesh stays in exact bay with supported floor and layers "+tag+" amount"+str(amount),supported and bounded and horizontal_escape<0.00001,{"maximum_vertical_gap_m":max_gap,"maximum_height_m":boxes[-1].end.y,"maximum_horizontal_escape_m":horizontal_escape})
		expect("amount bands retain original mesh identity and owner quantities "+tag+" amount"+str(amount),stock._parts[0].get_instance_id()==geometry_id and stock.statistics().visible_parts==expected and stock.statistics().actual==amount and row.actual==amount)
		observations.append({"kind":kind,"extent":extent,"quarter_turn":turn,"actual":amount,"top_m":boxes[-1].end.y,"max_layer_gap_m":max_gap,"max_horizontal_escape_m":horizontal_escape})
	stock.free()
