extends "res://tests/gameplay/generated_cooperation.gd"
## Continue the exact retained accepted-work failure. No grants, relocation,
## new work assignment, or replacement of B's existing delivery executor.
const WORKER:="ordinary:E-lifecycle"

func logs()->float:
	var total:=0.0
	for a:Dictionary in runtime.facts().actors:total+=float(a.pack.get("log",0))
	for s:Dictionary in runtime.facts().stocks:total+=float(s.items.get("log",0))
	return total

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	output_dir=args[0];DirAccess.make_dir_recursive_absolute(output_dir)
	evidence_kind="exact-retained-far-tree-pending-delivery-continuation-no-grants"
	host=Client.new()
	if args.size()!=2:check("explicit retained failed delivery checkpoint supplied",false);finish();return
	var capture:Variant=JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not capture is Dictionary or not mount(capture):finish();return
	var person:Dictionary=runtime.actor(WORKER)
	var pending:Dictionary=person.get("pending_delivery",{})
	check("exact far-tree accepted delivery still holds three actual logs",pending.get("source_id")=="rural:v3:713:0:0:tree:60:60:drops" and pending.get("phase")=="deliver" and float(person.pack.get("log",0))==3 and float(pending.get("items",{}).get("log",0))==3,pending)
	if pending.is_empty():finish();return
	var destination:String=pending.destination_id
	var before:float=float(runtime.stock(destination).items.get("log",0))
	var conserved:float=logs()
	check("retained inventory has only original three logs",conserved==3)
	if not roundtrip("retained far-tree pending delivery before recovery"):finish();return
	var travelled:=0.0
	var max_horizontal:=0.0
	var max_vertical:=0.0
	for i:int in 1800:
		if float(runtime.stock(destination).items.get("log",0))==before+3:break
		var start:Vector3=Geometry.point(runtime.actor(WORKER))
		step()
		var delta:Vector3=Geometry.point(runtime.actor(WORKER))-start
		var horizontal:float=Vector2(delta.x,delta.z).length()
		travelled+=horizontal;max_horizontal=maxf(max_horizontal,horizontal);max_vertical=maxf(max_vertical,absf(delta.y))
		if horizontal>Movement.WALK_SPEED*0.1+0.001 or absf(delta.y)>0.501:jumps.append({"id":WORKER,"tick":ticks,"delta":[delta.x,delta.y,delta.z]})
		if logs()!=conserved:check("each delivery tick conserves original log total",false);finish();return
	person=runtime.actor(WORKER)
	check("original B executor physically delivers exact retained three logs",float(runtime.stock(destination).items.get("log",0))==before+3 and float(person.pack.get("log",0))==0 and not person.has("pending_delivery"),person)
	check("far delivery really travels without teleport or higher steps",travelled>20 and jumps.is_empty(),{"metres":travelled,"max_horizontal_step":max_horizontal,"max_vertical_step":max_vertical,"ticks":ticks})
	check("delivery conserves every original log without new grant",logs()==conserved)
	if not roundtrip("recovered far-tree delivery committed exactly once"):finish();return
	for i:int in 10:step()
	check("native restored completed delivery cannot pay the same logs twice",float(runtime.stock(destination).items.get("log",0))==before+3 and logs()==conserved)
	write_json("delivery-evidence.json",{"source":args[1],"worker":WORKER,"destination":destination,"original_logs":conserved,"delivered":3,"travelled_metres":travelled,"ticks":ticks,"max_horizontal_step":max_horizontal,"max_vertical_step":max_vertical})
	finish()
