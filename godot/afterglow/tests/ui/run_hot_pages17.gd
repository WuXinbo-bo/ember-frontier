extends "res://tests/ui/run_controls15.gd"
## Same-frame read fences plus real retained management pages. No GPU claim.
const UI17=preload("res://scripts/ui/game_ui.gd")
const Catalog17=preload("res://scripts/ui/factory_catalog.gd")
class ReadOwner extends RefCounted:
	var frame:int=1
	var revision:int=0
	var reads:int=0
	var factory_reads:int=0
	var person_reads:int=0
	var full_reads:int=0
	var notify_ui:Variant=null
	func snapshot()->Dictionary:return {}
	func ui_read_basis()->Dictionary:return {"frame":frame,"revision":revision}
	func ui_page_snapshot(_page:String,_subject:String)->Dictionary:
		reads+=1
		if notify_ui!=null:
			var target:Variant=notify_ui;notify_ui=null;target._on_changed({"unrecognized":true})
		return {"player":{"id":"player"},"hand":{"value":reads}}
	func factory_page_snapshot(_actor:String,_page:String,_subject:String)->Dictionary:
		factory_reads+=1
		return {"schema":"afterglow-factory-display-v1","version":1,"available":true}
	func workforce_person_snapshot(id:String)->Dictionary:
		person_reads+=1;return {"actor_id":id,"candidates":[{"id":"actual"}]}
	func workforce_snapshot(_id:String)->Dictionary:
		full_reads+=1;return {}

func probes()->void:
	var owner:=ReadOwner.new();var probe:=UI17.new();probe.runtime=owner
	var first:Dictionary=probe._read_page("factory_inventory","")
	var again:Dictionary=probe._read_page("factory_inventory","")
	check("exact same-frame page reuses both detached owner reads",owner.reads==1 and owner.factory_reads==1 and first==again)
	probe._read_page("factory_inventory","other")
	check("subject is part of query identity",owner.reads==2)
	owner.frame+=1;probe._read_page("factory_inventory","")
	check("next process frame always rereads",owner.reads==3)
	owner.revision+=1;probe._read_page("factory_inventory","")
	check("same-frame authority revision forces reread",owner.reads==4)
	probe._on_changed({"unrecognized":true});probe._read_page("factory_inventory","")
	check("unknown notification invalidates exact same-frame read",owner.reads==5)
	owner.frame+=1;owner.notify_ui=probe;probe._read_page("factory_inventory","")
	check("notification raised during read remains queued",probe._refresh_queued)
	probe._read_page("factory_inventory","")
	check("read invalidated during construction cannot enter cache",owner.reads==7)
	var person:Dictionary=F.read_person(owner,"companion")
	check("narrow person facade avoids whole-workforce API",person.actor_id=="companion" and owner.person_reads==1 and owner.full_reads==0)
	probe.free()
	var data:Dictionary={"modules":{"available":true,"instances":[null,{"id":"wanted","nested":{"value":1}},{"id":"other"}],"definitions":[{"id":"def","architecture":{"set":Catalog17.SET,"family":"home","tier":"small","design_capacity":3}}]}}
	var selected:Dictionary=F.instance(data,"wanted");selected.nested.value=2
	check("selected row remains deeply detached",data.modules.instances[1].nested.value==1)
	var definition:Dictionary=F.definition(data,"def");definition.architecture.family="changed"
	check("selected definition remains detached",data.modules.definitions[0].architecture.family=="home")
	var metadata:Dictionary=Catalog17.architecture(data.modules.definitions[0]);metadata.family="changed"
	check("public architecture metadata remains detached",Catalog17.family(data.modules.definitions[0])=="home")
	check("empty and named search retain architecture filters",Catalog17.matches(data.modules.definitions[0],"all","home","small","  ",{}) and not Catalog17.matches(data.modules.definitions[0],"all","water","all","",{}) and Catalog17.matches(data.modules.definitions[0],"all","all","all","住宅",{}))
	data.modules.available=false
	check("unavailable modules cannot leak definitions or instances",F.instance(data,"wanted").is_empty() and F.definition(data,"def").is_empty())

func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	probes()
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=ControlsHost.new();root.add_child(host)
	var profiles:Dictionary=Assembly.generation_profiles()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("actual village prepares",prepared.get("ok",false))
	if not prepared.get("ok",false):return finish()
	var made:Dictionary=host._assemble(Opening.prepare_opening(prepared.capture,"normal"))
	check("same Native authority assembles",made.get("ok",false))
	if not made.get("ok",false):return finish()
	runtime=made.runtime;router=RealRouter.new();router.controls_path=output+"/controls.json"
	host.add_child(router);router.configure(runtime,false,true)
	ui=Mount.mount(host,runtime,router);await flush()
	var original:Dictionary=runtime.capture_checkpoint()
	for page:String in ["factory_people","factory_alerts"]:
		ui.close_panels();ui.open_panel(page);await flush()
		var body_id:int=ui._body.get_instance_id();var child_id:int=ui._body.get_child(0).get_instance_id()
		var map_id:int=ui._known_map_canvas.get_instance_id() if is_instance_valid(ui._known_map_canvas) else 0
		ui.close_panels();ui.open_panel("pause");await flush()
		ui.close_panels();ui.open_panel(page);await flush()
		check("unchanged reopen retains full native subtree "+page,ui._body.get_instance_id()==body_id and ui._body.get_child(0).get_instance_id()==child_id)
		if page=="factory_alerts":check("restored map reference belongs to restored body",is_instance_valid(ui._known_map_canvas) and ui._known_map_canvas.get_instance_id()==map_id and ui._body.is_ancestor_of(ui._known_map_canvas))
		if page=="factory_people":
			var members:Array=F.rows(ui.factory,"workforce","members")
			var member_id:String=""
			for member:Dictionary in members:
				if member.get("actor_id")!="player":member_id=str(member.actor_id);break
			check("normal opening has a public companion",not member_id.is_empty())
			var before:int=ui.workforce_detail_reads
			ui.refresh_workforce_person(member_id);await flush()
			check("explicit candidate refresh refetches original person and rebuilds controls",ui.workforce_detail_reads>before and ui._body.get_child(0).get_instance_id()!=child_id)
			var signature:int=ui._visible_panel_signature()
			ui.factory.runtime_revision=int(ui.factory.get("runtime_revision",0))+1
			check("person authority revision invalidates retained candidate controls",ui._visible_panel_signature()!=signature)
	check("all read and native view probes preserve exact real authority",Data.json_equal(original,runtime.capture_checkpoint()))
	finish()

func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"observed":observed,"scope":"Headless source read-fence probes and native retained subtrees over current Native authority; direct UI method calls. No Viewport/OS input, GPU, packaged behavior or FPS claim."},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
