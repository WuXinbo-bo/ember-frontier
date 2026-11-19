extends "res://tests/ui/run_controls15.gd"
const P=preload("res://scripts/ui/ui_projection.gd")
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=ControlsHost.new();root.add_child(host)
	var profiles:Dictionary=Assembly.generation_profiles();var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("actual fresh16 normal opening prepares",prepared.get("ok",false))
	if not prepared.get("ok",false):return finish()
	var made:Dictionary=host._assemble(Opening.prepare_opening(prepared.capture,"normal"))
	check("same real fresh authority assembles",made.get("ok",false))
	if not made.get("ok",false):return finish()
	runtime=made.runtime;router=RealRouter.new();router.controls_path=output+"/controls.json";host.add_child(router);router.configure(runtime,false,true)
	ui=Mount.mount(host,runtime,router);await flush()
	var before:Dictionary=runtime.capture_checkpoint();var id:String="r34:generated:RH-HOME:home"
	ui.open_panel("factory_module",id);await flush()
	var row:Dictionary=F.instance(ui.factory,id);var action:Dictionary=row.get("restoration_action",{})
	check("actual old home is repairable but lacks original required supplies",row.get("state_code")=="needs_restoration" and not action.get("available",true) and not action.get("materials",[]).is_empty(),row)
	var start:Button=keyed("factory:command:module.restore:"+id)
	check("visible simple repair button has real disabled reason",start!=null and start.text=="修复" and start.disabled and not start.tooltip_text.is_empty())
	var primary:Node=null
	for candidate:Node in ui._body.find_children("*","VBoxContainer",true,false):
		if candidate.get_meta("ui_restoration_card","")==id:primary=candidate;break
	check("repair primary keeps tool/source choices out",primary!=null and primary.find_children("*","OptionButton",true,false).is_empty())
	if primary!=null:
		var text:String=text_in(primary)
		for item:Dictionary in action.get("materials",[]):
			var expected:String=P.item_name(str(item.item_id))+" · 需要 "+P.number(item.required)+" / 随身可用 "+P.number(item.available)
			if float(item.missing)>0:expected+=" · 还缺 "+P.number(item.missing)
			check("exact owner required/carried/missing amount "+str(item.item_id),text.contains(expected),expected)
		check("real missing hammer is explicitly explained",not action.get("tool",{}).get("available",true) and text.contains("锤子") and text.contains("随身缺少可用工具"),text)
	for page:String in ["pause","inventory","factory_catalog"]:
		ui.close_panels();ui.open_panel(page);await flush();var identity:int=ui._body.get_instance_id()
		ui.close_panels();ui.open_panel(page);await flush()
		check("unchanged native warm page remains retained "+page,identity==ui._body.get_instance_id())
	check("read-only conditions and retained pages preserve exact authority",Data.json_equal(before,runtime.capture_checkpoint()))
	finish()
