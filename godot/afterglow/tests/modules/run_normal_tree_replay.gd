extends "res://tests/buildings/domain_suite.gd"
## Replays A's immutable-build16 normal-economy checkpoint, with no relocation,
## supplies, permission changes or replacement terrain.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Interaction=preload("res://scripts/buildings/interaction_contact.gd")
func run()->void:
	var args:=OS.get_cmdline_user_args()
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[0]))
	expect("original normal journey checkpoint decodes",decoded.ok,decoded.get("reason"))
	if not decoded.ok:return done({})
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	expect("original source reassembles with all formal services",built.ok,built.get("reason"))
	if not built.ok:return done({})
	var rt:RefCounted=built.runtime;var tree_id:String="RH-HOME:home:grove3:3"
	var facts_before_warm:Dictionary=rt.facts()
	while not built.world.region_is_resident("RH-HOME"):
		var warm:Dictionary=built.world.prepare_region_residency("RH-HOME",true,built.world.get_revision(),32)
		if not warm.ok or warm.world_changes.is_empty():expect("real target warm prepares",false,warm);return done({})
		var committed:Dictionary=rt._commit(warm)
		if not committed.ok:expect("target warm commits through original safety",false,committed);return done({})
	expect("real target data warming preserves all people stocks and clock",facts_before_warm==rt.facts())
	var tree:Dictionary=built.world.entity(tree_id);var ac:RefCounted=built.services.actions
	var pr:RefCounted=built.services.production;var query:RefCounted=built.services.buildings.current_space()
	var drop:Dictionary=built.world.entity(tree.data.outputId)
	var hints:Array=ac.work_points({"kind":"harvest","target_id":tree_id});var hint_evidence:Array=[]
	for hint:Dictionary in hints:
		var plan:Dictionary=ac.route("player",Geometry.location(rt.actor("player")),hint)
		hint_evidence.append({"at":hint,"actual_contact":Interaction.entity(query,hint,tree),"drop_contact":Interaction.entity(query,hint,drop),"standing":query.standing_point(hint),"route":plan})
	var axe:String="r34:generated:RH-HOME:woodwork:tool:salvaged_axe"
	var before_pack:Dictionary=rt.actor("player").pack.duplicate(true)
	var wear_before:float=rt.tool(axe).durability
	var unchanged:Dictionary=rt.capture_checkpoint()
	var direct:Dictionary=rt.command({"command_id":"B:normal:tree:blocked-direct","actor_id":"player","kind":"harvest","target_id":tree_id,"payload":{"direct":true,"tool_ids":[axe]}})
	expect("same blocked direct location never grants remote labor",not direct.ok and DataEquality(unchanged,rt.capture_checkpoint()),direct.get("reason"))
	var start:Dictionary=rt.command({"command_id":"B:normal:tree:replay","actor_id":"player","kind":"harvest","target_id":tree_id,"payload":{"direct":false,"tool_ids":[axe]}})
	expect("normal finite axe starts original approach",start.ok and rt.actor("player").intent is Dictionary,start.get("reason"))
	var route_before:Variant=rt.actor("player").get("intent");var trace:Array=[];var previous:String=""
	for i:int in 1000:
		var a:Dictionary=rt.actor("player");var intent:Dictionary=a.intent if a.intent is Dictionary else {}
		var stage:String=str(intent.get("kind"))+":"+str(intent.get("step"))+":"+str(a.activity)
		if stage!=previous:
			trace.append({"clock":rt.clock(),"at":Geometry.location(a),"kind":intent.get("kind"),"step":intent.get("step"),"activity":a.activity,"contact":Interaction.entity(built.services.buildings.current_space(),Geometry.location(a),built.world.entity(tree_id))})
			previous=stage
		if a.intent==null:break
		rt.tick(0.1)
	var final:Dictionary=rt.actor("player");var output:Dictionary=rt.stock(tree.data.outputId)
	expect("same normal long route actually fells original tree",built.world.entity(tree_id).data.harvest.phase=="stump",{"actor":final,"trace":trace,"hints":hint_evidence})
	expect("normal labor yields three logs only in original drop",output.items.get("log",0)==3 and final.pack==before_pack,output)
	expect("normal original axe settles exactly six wear",is_equal_approx(float(rt.tool(axe).durability),wear_before-6.0),rt.tool(axe))
	done({"checkpoint":args[0],"initial_route":route_before,"hints":hint_evidence,"trace":trace,"final":final,"orders":pr.state().orders,"final_tree_contact":Interaction.entity(built.services.buildings.current_space(),Geometry.location(final),tree),"final_drop_contact":Interaction.entity(built.services.buildings.current_space(),Geometry.location(final),drop),"final_drop_reach":pr.reach("player",drop.id,rt.stock(drop.id))})

func done(evidence:Dictionary)->void:
	print(JSON.stringify({"checks":checks,"ok":failures.is_empty(),"evidence":evidence,"scope":"actual build16 normal pre-tree checkpoint replay; no injected body/items/permissions; source only, not PCK/OS/VA"}));quit(0 if failures.is_empty() else 1)

func DataEquality(a:Dictionary,b:Dictionary)->bool:
	return preload("res://scripts/world/world_data.gd").json_equal(a,b)
