extends "res://tests/buildings/family_generation_suite.gd"
## Exact candidate10 incident plus real Runtime/CAS consumers. Only the copied
## checkpoint passed on the command line is read. Never fixes or writes a save.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const INCIDENT={"x":40.34417171636596,"y":3.0,"z":56.74938907567412,"regionId":"RH-HOME","buildingId":null,"storeyId":null}

func inspect_capture(capture:Dictionary,label:String)->void:
	var w:=World.new();var loaded:Dictionary=w.load_snapshot(capture.world)
	expect(label+" actual world loads",loaded.ok,loaded.get("reason"))
	if not loaded.ok:return
	var b:=Building.new();var r:=Runtime.new();b.configure({"world":w,"runtime":r})
	var original:Dictionary=w.snapshot();var q:RefCounted=b.current_space()
	var p:Dictionary=INCIDENT.duplicate(true)
	expect(label+" bad logged stance stays invalid and is never auto-relocated",q.body_location(p).is_empty() and q.standing_point(p).is_empty() and q.blockers(p,p,"player").ok)
	var reference:=p.duplicate(true);reference.y=2.5
	var origin:=reference.duplicate(true);origin.z+=0.08
	var feet:Dictionary=q.standing_point(origin)
	expect(label+" real 8cm approach starts with full independent standing proof",not feet.is_empty() and b.space().standing_point(feet)==feet,{"origin":origin,"feet":feet})
	if feet.is_empty():return
	var levels:Dictionary={}
	for dx:float in [-0.26,0.0,0.26]:
		for dz:float in [-0.26,0.0,0.26]:levels[q.ground_height(float(p.x)+dx,float(p.z)+dz)]=true
	expect(label+" actual three foot heights reproduce 1m span around old 2.5 plane",levels.has_all([2.0,2.5,3.0]) and levels.size()==3,levels.keys())
	expect(label+" lower reference cannot resolve an unsupported higher plane",q.body_location(reference).is_empty())
	for repeat_index:int in 2:
		var walked:Dictionary=q.walk("player",feet,reference)
		var direct:Dictionary=q.direct_move("player",feet,reference)
		expect(label+" cold and repeated NPC walk reject unstable endpoint "+str(repeat_index),not walked.ok,walked)
		expect(label+" cold and repeated direct movement reject unstable endpoint "+str(repeat_index),not direct.ok,direct)
	expect(label+" all derived queries preserve complete authority",w.snapshot()==original)
	# Explicit isolated stance fixture. The original checkpoint remains intact;
	# every other actor, tool, work order and terrain cell stays from the source.
	var fixture:=capture.duplicate(true)
	for actor:Dictionary in fixture.facts.actors:
		if actor.id=="player":actor.merge(feet,true);actor.intent=null
	var host:=Client.new();var assembled:Dictionary=host._assemble(fixture)
	expect(label+" formal assembler accepts explicitly supported comparison stance",assembled.ok,assembled.get("reason"))
	if not assembled.ok:host.free();return
	var authority:RefCounted=assembled.runtime;var service:RefCounted=assembled.services.buildings
	var before:Dictionary=authority.capture_checkpoint()
	var rejected:Dictionary=authority.command({"command_id":"support-edge:"+label,"actor_id":"player","kind":"direct_move","destination":reference,"payload":{"movement_dt":0.1,"movement_mode":"walk"}})
	expect(label+" real command rejects with no movement labor cancellation or debit",not rejected.ok and authority.capture_checkpoint()==before,rejected)
	var safe:=feet.duplicate(true);safe.z+=0.08
	var accepted:Dictionary=authority.command({"command_id":"support-safe:"+label,"actor_id":"player","kind":"direct_move","destination":safe,"payload":{"movement_dt":0.1,"movement_mode":"walk"}})
	var at:=Geometry.location(authority.actor("player"))
	expect(label+" nearby legitimate move still commits supported endpoint",accepted.ok and service.space().standing_point(at)==at,accepted)
	var scene:Dictionary=authority.capture_checkpoint()
	var view:RefCounted=assembled.world
	var legal:Array=[{"op":"voxel.set","cell":{"x":80,"y":5,"z":112},"before":view.cell_at(80,5,112),"after":0}]
	var proposed:Dictionary=view.prepare_changes(legal,view.get_revision())
	var safety:Dictionary=service.validate_world_draft(proposed.view,authority.facts(),legal) if proposed.ok else proposed
	expect(label+" adjacent logged dig remains legal from actually supported stance",safety.ok,safety)
	if proposed.ok:view.discard_prepared(proposed.capability)
	var collapse:Array=[]
	for y:int in [4,3]:collapse.append({"op":"voxel.set","cell":{"x":80,"y":y,"z":113},"before":view.cell_at(80,y,113),"after":0})
	proposed=view.prepare_changes(collapse,view.get_revision())
	safety=service.validate_world_draft(proposed.view,authority.facts(),collapse) if proposed.ok else proposed
	expect(label+" real draft removing standing support still rejects",proposed.ok and not safety.ok and safety.code=="SPATIAL_REJECTED",safety)
	if proposed.ok:view.discard_prepared(proposed.capability)
	expect(label+" legal and forbidden previews neither dig nor change materials",authority.capture_checkpoint()==scene)
	host.free()

func run()->void:
	var started:=Time.get_ticks_msec();var args:=OS.get_cmdline_user_args()
	if args.is_empty():expect("requires isolated actual save copy",false);finish(started);return
	var text:String=FileAccess.get_file_as_string(args[0])
	expect("uses A immutable real seed12 slot copy by exact SHA",text.sha256_text()=="52eba1792d1145a6f3de30cc3a8abfe6170f9e524e463191541772793d70690d")
	var decoded:Dictionary=Store.decode(text)
	expect("real copied checkpoint decodes",decoded.ok,decoded.get("reason"))
	if decoded.ok:
		expect("real incident identity is seed12 revision5 runtime1419",decoded.capture.world.seed==12 and decoded.capture.world.revision==5 and decoded.capture.command_revision==1419)
		inspect_capture(decoded.capture,"saved12")
	var fresh:Dictionary=Assembly.prepare(Assembly.generate(12,Building.generation_profiles()))
	expect("fresh12 distinct comparison prepares through actual composition",fresh.ok,fresh.get("reason"))
	if fresh.ok:inspect_capture(fresh.capture,"fresh12-not-rev5")
	finish(started)
