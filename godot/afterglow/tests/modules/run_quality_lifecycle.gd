extends "res://tests/modules/run_factory_lifecycle.gd"
## Reuse the original finite, isolated supplies/labor/stock/damage fixture for
## each new woodshop. This is NOT normal resources, natural attack or VA.
var last_capture:Dictionary={}
var checked_projection:=false
func commit(rt:RefCounted,prepared:Dictionary)->Dictionary:
	var result:Dictionary=super.commit(rt,prepared)
	if result.ok:last_capture=rt.capture_checkpoint()
	if result.ok and not checked_projection:
		checked_projection=true
		var before:Dictionary=rt.capture_checkpoint();var public:Dictionary=rt.factory_snapshot()
		check("real public snapshot exposes current ten build IDs and all nineteen definitions",public.modules.build_definition_ids.size()==10 and public.modules.definitions.size()==19)
		check("build menu projection remains pure",Data.json_equal(before,rt.capture_checkpoint()))
	return result
func command(rt:RefCounted,id:String,kind:String,target:String="",payload:Dictionary={},actor_id:String="player")->Dictionary:
	var result:Dictionary=super.command(rt,id,kind,target,payload,actor_id)
	if result.ok:last_capture=rt.capture_checkpoint()
	return result
func finish()->void:
	var out:String=OS.get_cmdline_user_args()[0]
	var report:Dictionary={"ok":checks.all(func(c:Dictionary)->bool:return c.ok),"checks":checks,"scope":"Current B additive geometry, original isolated fixture supplies and repositioned service actors; explicit fixture damage, not natural economy or enemy attack/VA/package."}
	var f:=FileAccess.open(out+"/results.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	if not last_capture.is_empty():
		f=FileAccess.open(out+"/last-success-capture.json",FileAccess.WRITE);f.store_string(JSON.stringify(last_capture));f.close()
	print("QUALITY LIFECYCLE "+str(checks.size())+" "+str(report.ok));quit(0 if report.ok else 1)
