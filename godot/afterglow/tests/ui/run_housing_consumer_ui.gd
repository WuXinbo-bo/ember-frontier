extends "res://tests/ui/run_architecture_catalog_ui.gd"
## B's unchanged paid porch laboratory capture. Supplies, flat terrain and
## knowledge come from that declared lab, never from this UI consumer.

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(original)
	check("owner declared finite housing lab decodes unchanged",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=TestNative.new();root.add_child(host)
	if not await assemble_capture(decoded.capture):return finish(1)
	var public:Dictionary=runtime.housing_projection("player")
	var homes:Array=F.dictionaries(public.get("homes",[])).filter(func(home:Dictionary):return str(home.get("geometry_version","")).ends_with(".geometry-v2") and home.get("bed_count",0)>0)
	check("real paid geometry2 home publishes actual bed entities",public.get("available",false) and homes.size()==1,homes.map(func(home:Dictionary):return {"id":home.id,"count":home.get("bed_count")}))
	if homes.size()!=1:return finish(1)
	var home:Dictionary=homes[0];var beds:Array=home.beds
	var first:Dictionary=F.dictionaries(beds).filter(func(bed:Dictionary):return bed.get("available",false))[0]
	var before:=runtime.capture_checkpoint()
	ui.open_panel("factory_module",str(home.id));await idle();await idle()
	check("object renders exact real bed identities and occupancy fields",beds.all(func(bed:Dictionary):return keyed("housing:rest:"+str(bed.bed_id))!=null and keyed("housing:walk:"+str(bed.bed_id))!=null) and text_in(ui._body).contains("实际床位 "+str(int(home.bed_count))) and text_in(ui._body).contains("不等于实际床位或入住人数"))
	check("bed rest buttons agree with authority availability",beds.all(func(bed:Dictionary):return (keyed("housing:rest:"+str(bed.bed_id)) as Button).disabled==(not bed.get("available",false) or not ui.availability(ui.request("rest",str(bed.bed_id))).get("ok",false))))
	for viewport:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport;root.content_scale_size=viewport;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5);await idle();await idle()
		check("bed sidebar fits with readable controls "+str(viewport),root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and ui._body.get_combined_minimum_size().x<=ui._scroll.size.x+1,{"dialog":str(ui._dialog.get_global_rect()),"body":str(ui._body.get_combined_minimum_size()),"scroll":ui._scroll.size.x})
	check("reading and scaling housing never changes beds or clock",Data.json_equal(before,runtime.capture_checkpoint()))
	var stale:Dictionary=first.approach.duplicate(true);stale.x+=.5
	var refused:Dictionary=ui.housing_view.walk_to(ui,str(home.id),str(first.bed_id),stale)
	check("explicit stale destination callback fails atomically instead of substituting a bed",not refused.get("ok",false) and refused.get("code")=="HOUSING_ACCESS_CHANGED" and Data.json_equal(before,runtime.capture_checkpoint()))
	ui.notify("");await idle()
	check("native bed guidance submits original walk and returns to scene",await activate("housing:walk:"+str(first.bed_id)) and ui.pages.is_empty() and runtime.actor("player").get("intent",{}).get("kind")=="walk",runtime.actor("player").get("intent"))
	for step in 1000:
		runtime.tick(.1)
		if runtime.actor("player").get("intent")==null:break
	ui.open_panel("factory_module",str(home.id));await idle();await idle()
	check("real arrival makes exact bed rest available",ui.availability(ui.request("rest",str(first.bed_id))).get("ok",false),runtime.actor("player"))
	check("native bed rest starts same exact authority target",await activate("housing:rest:"+str(first.bed_id)) and ui.pages.is_empty() and runtime.actor("player").get("intent",{}).get("target_id")==first.bed_id)
	var occupied:Dictionary=runtime.housing_projection("player")
	var occupied_home:=F.find(F.dictionaries(occupied.homes),str(home.id))
	check("real rest occupancy appears without local capacity changes",F.find(F.dictionaries(occupied_home.get("beds",[])),str(first.bed_id),"bed_id").get("occupied",false) and occupied_home.bed_count==home.bed_count)
	var checkpoint:=runtime.capture_checkpoint();var encoded:=Store.encode(checkpoint);var cold:=Store.decode(encoded.text) if encoded.get("ok",false) else encoded
	check("real sleeping checkpoint encodes through original codec",cold.get("ok",false))
	if cold.get("ok",false) and await assemble_capture(cold.capture):
		check("real cold authority keeps exact rest target and occupied entity",Data.json_equal(cold.capture.facts,runtime.capture_checkpoint().facts) and runtime.actor("player").get("intent",{}).get("target_id")==first.bed_id and F.find(F.dictionaries(F.find(F.dictionaries(runtime.housing_projection("player").get("homes",[])),str(home.id)).get("beds",[])),str(first.bed_id),"bed_id").get("occupied",false))
	check("owner finite laboratory file stays byte exact",FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)
