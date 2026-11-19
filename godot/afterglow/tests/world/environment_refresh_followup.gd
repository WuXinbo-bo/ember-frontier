extends "res://tests/world/environment_mount.gd"
## Compare adopted139 exact preimage, not older mount86 or entity-before86.
const CurrentBefore=preload("res://tests/world/fixtures/environment_before_refresh_followup.gd")
const Profile=preload("res://tests/world/fixtures/environment_refresh_profile.gd")
var order_flip:bool=false
func notify_pair(note:Dictionary,a:Node3D,b:Node3D,label:String)->void:
	var before_usec:int;var after_usec:int;var started:int
	if order_flip:
		started=Time.get_ticks_usec();b.on_world_changed(note);after_usec=Time.get_ticks_usec()-started
		started=Time.get_ticks_usec();a.on_world_changed(note);before_usec=Time.get_ticks_usec()-started
	else:
		started=Time.get_ticks_usec();a.on_world_changed(note);before_usec=Time.get_ticks_usec()-started
		started=Time.get_ticks_usec();b.on_world_changed(note);after_usec=Time.get_ticks_usec()-started
	order_flip=not order_flip
	if not costs.has("samples"):costs.samples=[]
	costs.samples.append({"label":label,"before_usec":before_usec,"after_usec":after_usec,"after_first":not order_flip,"scope":"same world/input, alternating synchronous notifications, headless CPU under concurrent A longtest; not OS/FPS/quiet-window"})
	compare(a,b,label)
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2:quit(2);return
	var output:String=args[0];var input:String=args[1]
	check("original real24 source SHA",FileAccess.get_sha256(input)=="ef226d9ddcc26834acb691bfec09623fbb32c7408804a1575ce9887a2f26ae48")
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input))
	var host:=DiagnosticClient.new();root.add_child(host);host.set_process(false)
	var built:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded
	check("actual Native original24/current fields assemble",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish(output)
	world=built.world
	var original:Dictionary=built.runtime.capture_checkpoint()
	var before:=CurrentBefore.new();var after:=EnvironmentView.new();root.add_child(before);root.add_child(after)
	before.configure({"world":world});after.configure({"world":world,"materials":before.materials})
	compare(before,after,"initial24 exact current geometry")
	for i:int in 6:notify_pair({"entities":[]},before,after,"unknown full %d"%i)
	var profile:=Profile.new();root.add_child(profile);profile.configure({"world":world,"materials":before.materials});profile.reset_profile()
	var started:int=Time.get_ticks_usec();profile.on_world_changed({"entities":[]})
	costs.attribution={"total_usec":Time.get_ticks_usec()-started,"inclusive_phase_usec":profile.phase,"scope":"instrumented current preimage, nested inclusive timers add overhead; not before-after timing"}
	profile.free()
	check("all configure/unknown full passes preserve complete authoritative checkpoint",Data.json_equal(original,built.runtime.capture_checkpoint()))
	var tree:Dictionary={}
	for id:String in before._roots:
		tree=world.entity(id);break
	var p:Dictionary=tree.position;var cell:Dictionary={"x":floori(p.x*2),"y":roundi(p.y*2)-1,"z":floori(p.z*2)}
	var material:int=world.cell_at(cell.x,cell.y,cell.z)
	for i:int in 4:
		var e:Dictionary=world.entity(tree.id);var changed:Dictionary=e.duplicate(true);changed.data.appearance.yaw+=0.05
		var tx:Dictionary=world.prepare_changes([{"op":"entity.put","id":e.id,"before_exists":true,"before":e,"after":changed},{"op":"voxel.set","cell":cell,"before":material if i%2==0 else 0,"after":0 if i%2==0 else material}],world.get_revision())
		var result:Dictionary=world.commit_prepared(tx.capability) if tx.ok else tx
		check("explicit isolated mixed entity+voxel accepted %d"%i,result.ok)
		if result.ok:notify_pair(result.changes,before,after,"mixed full %d"%i)
		check("mixed support/collision exact immediate current geometry %d"%i,after._roots.has(e.id)==(i%2==1))
	# Impacted scoped sampling affects first partial warm, support edits, cold
	# pages, saved plan invalidation and save/revisit; reuse these exact checks.
	await semantics(before,after)
	check("sampling leaves no cross-notification world/chunk cache",not after.get("_support_sampler") if after.get("_support_sampler")!=null else true)
	before.free();after.free();built.runtime.retire();host.free()
	finish(output)
