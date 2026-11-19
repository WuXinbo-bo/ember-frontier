extends SceneTree
## Owner placement availability affects disposable stock meshes only, not stock.
const Stock=preload("res://scripts/presentation/factory_stock_view.gd")
const Factory=preload("res://scripts/presentation/factory_view.gd")
const Contracts=preload("res://scripts/runtime/factory_contracts.gd")
var checks:Array=[]
var failures:Array=[]

func expect(label:String,ok:bool,evidence:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"evidence":evidence})
	if not ok:failures.append(label);print("FAIL ",label," ",JSON.stringify(evidence))

func _initialize()->void:call_deferred("run")

func run()->void:
	for kind:String in Stock.KINDS:test_stock(kind)
	test_public_consumer()
	var report:Dictionary={"scope":"D stock consumer and public FactoryView DTO transitions; owner terrain/solid placement and cold-recovery recomputation belong to B; not OS or VA","checks":checks,"failures":failures}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DDD_STOCK_VISIBILITY "+JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)

func test_stock(kind:String)->void:
	var stock:=Stock.new();root.add_child(stock)
	var row:Dictionary={"stock_ref":"fixture:stock","item_id":"fixture:"+kind,"unit":"l" if kind=="liquid" else "m3","actual":6.0,"capacity":10.0,"reserved":2.0,"representation":kind,"extent":Vector3(.8,.6,1.2)}
	var original:Dictionary=row.duplicate(true)
	expect(kind+" old DTO defaults to visible",stock.update(row) and stock.visible and stock.statistics().visual_available and stock.statistics().visual_reason=="")
	var node_id:int=stock.get_instance_id();var mesh_id:int=stock._parts[0].get_instance_id()
	for reason:String in ["unsupported","occupied","not_detailed"]:
		row.visual_available=false;row.visual_reason=reason
		var before:Dictionary=row.duplicate(true)
		expect(kind+" accepts unavailable placement "+reason,stock.update(row))
		var hidden:Dictionary=stock.statistics()
		expect(kind+" hides mesh without quantity or validation loss "+reason,not stock.visible and hidden.visible_parts==0 and hidden.actual==6 and hidden.capacity==10 and hidden.reserved==2 and hidden.band==Stock.band(6,10) and hidden.issue=="" and hidden.visual_reason==reason,hidden)
		expect(kind+" retains same legal row and geometry "+reason,row==before and stock.get_instance_id()==node_id and stock._parts[0].get_instance_id()==mesh_id)
		row.actual=10.0;row.reserved=0.0
		stock.update(row)
		expect(kind+" hidden stock follows actual changes "+reason,stock.statistics().actual==10 and stock.statistics().reserved==0 and stock.statistics().band==4 and stock.statistics().visible_parts==0)
		row.visual_available=true;row.visual_reason=""
		stock.update(row)
		var shown:Dictionary=stock.statistics()
		expect(kind+" restores current stock on same proxy "+reason,stock.visible and shown.visible_parts==(1 if kind=="liquid" else 9) and shown.actual==10 and shown.reserved==0 and shown.issue=="" and stock._parts[0].get_instance_id()==mesh_id,shown)
		row=original.duplicate(true)
		stock.update(row)
		expect(kind+" absent fields restore compatible defaults "+reason,stock.visible and stock.statistics().visual_available and stock.statistics().visual_reason=="" and stock.statistics().band==Stock.band(6,10))
	row.visual_available=false;row.visual_reason="unsupported";row.actual=0.0
	stock.update(row);row.visual_available=true;row.visual_reason="";stock.update(row)
	expect(kind+" restored true never invents empty stock",stock.visible and stock.statistics().actual==0 and stock.statistics().band==0 and stock.statistics().visible_parts==0)
	stock.free()

func test_public_consumer()->void:
	var view:=Factory.new();root.add_child(view)
	var buffers:Array=[]
	for id:String in ["input","output"]:
		buffers.append({"id":id,"stock_ref":"fixture:"+id,"item_id":"fixture:log","unit":"m3","actual":3.0,"capacity":10.0,"reserved":2.0,"representation":"log","anchor_id":"rack","extent":[.8,.6,1.2]})
	var instance:Dictionary={"id":"fixture:module","definition_id":"fixture:def","location":{"x":4.0,"y":0.0,"z":8.0},"quarter_turn":1,"state_code":"idle","visuals":{"anchors":{"rack":{"position":[4.0,.7,8.0],"forward":[1,0],"quarter_turn":1}},"buffers":buffers}}
	var snapshot:Dictionary={"schema":Contracts.SCHEMA,"version":Contracts.VERSION,"available":true,"world_id":"fixture:world","modules":{"available":true,"instances":[instance],"definitions":[]}}
	view.apply_snapshot(snapshot)
	var first:Node3D=view._buffers["fixture:module"]["input"]
	var sibling:Node3D=view._buffers["fixture:module"]["output"]
	var node_id:int=first.get_instance_id();var mesh_id:int=first._parts[0].get_instance_id()
	var original_transform:Transform3D=first.global_transform
	buffers[0].visual_available=false;buffers[0].visual_reason="occupied"
	var before:Dictionary=snapshot.duplicate(true)
	view.apply_snapshot(snapshot)
	var stats:Dictionary=view.statistics()
	expect("public DTO hides only its addressed buffer",not first.visible and sibling.visible and stats.buffers.size()==2 and stats.required_errors.is_empty(),stats)
	expect("public DTO retained verbatim with fixed world anchor",snapshot==before and first.get_instance_id()==node_id and first._parts[0].get_instance_id()==mesh_id and first.global_transform.is_equal_approx(original_transform))
	view.apply_snapshot(snapshot)
	expect("stable hidden DTO remains a legal cached row",view.statistics().required_errors.is_empty() and view.statistics().buffers.size()==2 and first.statistics().actual==3 and first.statistics().reserved==2)
	buffers[0].actual=8.0;buffers[0].reserved=1.0
	view.apply_snapshot(snapshot)
	expect("hidden public row keeps live quantities",not first.visible and first.statistics().actual==8 and first.statistics().reserved==1 and first.statistics().band==3)
	buffers[0].visual_available=true;buffers[0].visual_reason=""
	view.apply_snapshot(snapshot)
	expect("public DTO true resumes same mesh without moving stock",first.visible and first._parts[0].get_instance_id()==mesh_id and first.statistics().visible_parts==6 and first.statistics().actual==8 and first.global_transform.is_equal_approx(original_transform))
	view.free()
