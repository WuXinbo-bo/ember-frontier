extends "res://tests/modules/run_opening_bed.gd"
func run()->void:
	out=OS.get_cmdline_user_args()[0]
	var input:String=OS.get_cmdline_user_args()[1];var raw:String=FileAccess.get_file_as_string(input);var decoded:=Store.decode(raw)
	var live:=mount(decoded.capture) if decoded.ok else decoded
	check("unchanged real processing12 Native mounts",live.get("ok",false),live.get("reason"))
	if not live.get("ok",false):return finish()
	var rt:RefCounted=live.runtime;var modules:RefCounted=live.services.modules;var home:Dictionary=modules.instance("r34:generated:RH-HOME:home");var d:=Catalog.definition_view(str(home.definition_id));var bed_id:String=str(home.id)+":bed:opening:v1"
	check("original real12 has no silently appended bed",not home.config.has("opening_bed_v1") and live.world.entity(bed_id).is_empty())
	var before:Dictionary=rt.capture_checkpoint();var far:=send(rt,"module.bed.install",home.id)
	check("attachment cannot be installed remotely",not far.ok and Data.json_equal(before,rt.capture_checkpoint()),far)
	var port:Dictionary=Shape.ports(home,d)[0];var at:Dictionary=port.use_points[0]
	sequence+=1;var walk:Dictionary=rt.command({"kind":"walk","actor_id":"player","command_id":"B:bed-install-route:"+str(sequence),"destination":at,"payload":{}});idle(rt,2000)
	check("original paid-processing player really walks back to home service",walk.ok and G.point(G.location(rt.actor("player"))).distance_to(G.point(at))<.1,rt.actor("player"))
	var facts:Dictionary=rt.facts();var entities:Dictionary={}
	for member:Dictionary in home.members:
		if member.kind=="entity":entities[member.id]=live.world.entity(member.id)
	var installed:=send(rt,"module.bed.install",home.id);home=modules.instance(str(home.id))
	check("public explicit version1 attachment with original safety commits",installed.ok and home.config.get("opening_bed_v1")==1 and not live.world.entity(bed_id).data.prepared,installed)
	if not installed.ok:rt.retire();return finish()
	check("attachment changes no actor stock tool item or time",Data.json_equal(facts.actors,rt.facts().actors) and Data.json_equal(facts.stocks,rt.facts().stocks) and facts.time==rt.clock())
	var untouched:=true
	for id:String in entities:
		if id.contains(":part:road-entry-porch:"):continue
		untouched=untouched and Data.json_equal(entities[id],live.world.entity(id))
	check("old IDs and all nonporch members retain exact bytes",untouched)
	var once:Dictionary=rt.capture_checkpoint();var duplicate:=send(rt,"module.bed.install",home.id)
	check("receipt prevents repeat and no materials can refill",not duplicate.ok and duplicate.code=="OPENING_BED_ALREADY_INSTALLED" and Data.json_equal(once,rt.capture_checkpoint()),duplicate)
	var save:=Store.encode(rt.capture_checkpoint());var cold:=mount(Store.decode(save.text).capture) if save.ok else save
	check("exact old12 plus explicit attachment fullcold",cold.get("ok",false),cold.get("reason"))
	if save.ok:FileAccess.open(out+"/actual-processing12-attachment.native.json",FileAccess.WRITE).store_string(save.text)
	if cold.get("ok",false):cold.runtime.retire()
	rt.retire();check("input archive bytes unchanged",FileAccess.get_file_as_string(input)==raw);finish()
