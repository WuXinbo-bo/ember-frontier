extends "res://tests/buildings/domain_suite.gd"
## Real rural structures, explicit spatial observations (not a player route).
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
const Client=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const HOME="rural:v1:RH-HOME:old-house"
var policy:RefCounted
var view:Node3D

func wall_set(p:RefCounted,query:RefCounted)->Array:
	var result:Array=[]
	for piece:Dictionary in query.pieces:
		if p.cut_wall(piece):result.append(piece.id)
	result.sort()
	return result

func install(player:Dictionary,stocks:Array)->void:
	initialize_at(player,[],stocks)
	if view!=null:view.free()
	view=building.create_view({"runtime":runtime});root.add_child(view)
	expect("formal building adapter accepts A policy",view.has_method("set_view_policy"))
	if view.has_method("set_view_policy"):view.call("set_view_policy",policy)

func run()->void:
	var started:=Time.get_ticks_msec()
	expect("real retained rural-1 world loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var seeded:Dictionary=building.seed_rural(world)
	expect("existing B rural seed prepares",seeded.ok,seeded.get("reason"))
	if not seeded.ok:finish(started);return
	var draft:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("real C capabilities commit the B structures",draft.ok and world.commit_prepared(draft.capability).ok)
	initialize_at(seeded.spawn_points.player,[],seeded.initial_stocks)
	var original:Dictionary=runtime.capture_checkpoint()
	var query:RefCounted=building.current_space()
	policy=Policy.new();policy.configure(query)
	var groups:Dictionary={}
	for roof:Dictionary in policy._rooms.roofs:
		if roof.get("buildingId")!=HOME:continue
		var candidate:Dictionary=policy._rooms.room_point(roof)
		var feet:Dictionary=query.standing_point(candidate)
		if feet.is_empty() or feet.get("buildingId")!=HOME:continue
		var component:int=policy._rooms.component_at(feet)
		if not groups.has(component):groups[component]=[]
		groups[component].append(feet)
	expect("real old home supplies several structural rooms",groups.size()>=2,{"rooms":groups.size()})
	var largest:Array=[]
	for points:Array in groups.values():
		if points.size()>largest.size():largest=points
	expect("same real room has multiple supported stations",largest.size()>=3,largest.size())
	if largest.size()<3:finish(started);return
	policy.sample(largest[0],0)
	var signature:String=policy.signature();var cut:Array=wall_set(policy,query)
	var old_variants:Dictionary={};var unstable:Array=[]
	for i in largest.size():
		var location:Dictionary=largest[i]
		# These are sequential observations within one physical room. Larger
		# jumps reset immediately but still resolve exactly the same room key.
		policy.sample(location,100+i*200)
		if policy.signature()!=signature or wall_set(policy,query)!=cut:unstable.append(location)
		var old:Array=[]
		for piece:Dictionary in query.pieces:
			if piece.get("buildingId")==HOME and (float(piece.position.x)>float(location.x)+0.5 or float(piece.position.z)>float(location.z)+0.5):old.append(piece.id)
		old_variants[str(old)]=true
	expect("all same-room stations keep one wall/cap set",unstable.is_empty(),{"stations":largest.size(),"cut_walls":cut.size(),"unstable":unstable})
	expect("same observations reproduce old coordinate-dependent changes",old_variants.size()>1,{"old_variants":old_variants.size()})
	var roofs:Array=query.pieces.filter(func(v:Dictionary)->bool:return v.get("buildingId")==HOME and query.geometry.definition(v).kind=="roof")
	expect("occupied floor opens ALL of its roof as one group",not roofs.is_empty() and roofs.all(func(v:Dictionary)->bool:return not policy.base_visible(v,"roof")),roofs.size())
	var other_roof:Dictionary={}
	for piece:Dictionary in query.pieces:
		if piece.regionId=="RH-HOME" and piece.get("buildingId")!=HOME and query.geometry.definition(piece).kind=="roof":other_roof=piece;break
	expect("neighboring building remains intact",not other_roof.is_empty() and policy.base_visible(other_roof,"roof"))
	var pair:Array=[]
	for a:Array in groups.values():
		for b:Array in groups.values():
			if a==b:continue
			for pa:Dictionary in a:
				for pb:Dictionary in b:
					if Geometry.point(pa).distance_to(Geometry.point(pb))<3.0:pair=[pa,pb];break
				if not pair.is_empty():break
			if not pair.is_empty():break
		if not pair.is_empty():break
	expect("actual neighboring rooms supply a doorway threshold pair",not pair.is_empty(),pair)
	if not pair.is_empty():
		policy=Policy.new();policy.configure(query);policy.sample(pair[0],1000);signature=policy.signature()
		for i in 8:policy.sample(pair[i%2],1020+i*30)
		expect("brief doorway jitter never flaps the wall scope",policy.signature()==signature,policy.statistics())
		policy.sample(pair[1],1500);policy.sample(pair[1],1700)
		expect("stable actual room change activates after confirmation",policy.signature()!=signature and not policy.statistics().pending,policy.statistics())
	var inside:Dictionary=largest[0]
	policy=Policy.new();policy.configure(query);policy.sample(inside,2000)
	var exterior:Dictionary=inside.duplicate(true);exterior.buildingId=null;exterior.storeyId=null
	policy.sample(exterior,2010)
	expect("brief threshold sample retains only the geometry scope",policy.statistics().pending and policy.statistics().building_id==HOME)
	policy.sample(exterior,2200)
	expect("stable exterior restores whole facade and roof",policy.statistics().building_id==null and policy.base_visible(roofs[0],"roof") and wall_set(policy,query).is_empty())
	policy.sample(inside,2500);policy.sample(inside,2700)
	var foreign:Dictionary=inside.duplicate(true);foreign.regionId="RH-VILLAGE";foreign.buildingId=null;foreign.storeyId=null
	policy.sample(foreign,2710)
	expect("actual region change clears indoor scope immediately",policy.statistics().region_id=="RH-VILLAGE" and policy.statistics().building_id==null and not policy.base_visible(roofs[0],"roof"))
	policy=Policy.new();policy.configure(query);policy.sample(inside,3000)
	install(inside,seeded.initial_stocks)
	if view.has_method("set_view_policy"):
		view.update_visibility()
		var shown_roofs:Array=[];var wrong_pairs:Array=[]
		for node:MeshInstance3D in view.static_nodes.values():
			var piece:Dictionary=node.get_meta("piece")
			if piece.get("buildingId")!=HOME:continue
			var role:String=node.get_meta("role")
			if role=="roof" and node.visible:shown_roofs.append(piece.id)
			if role in ["wall","cap"] and node.visible!=(policy.base_visible(piece,role) and (not policy.cut_wall(piece) if role=="wall" else policy.cut_wall(piece))):wrong_pairs.append(piece.id)
		expect("real adapter hides whole roof without hanging pieces",shown_roofs.is_empty(),shown_roofs)
		expect("real full/cap meshes consume the SAME stable policy",wrong_pairs.is_empty(),wrong_pairs)
		var private:Array=[]
		for id:String in view.objects:
			var node:Node3D=view.objects[id]
			if node.visible and not view.visible_shell(node.get_meta("piece"),runtime.actor("player")):private.append(id)
		expect("actual fixed shells honor stable room scope and other props retain true sight",private.is_empty(),private)
	actor_visibility_case(largest,groups,seeded.initial_stocks)
	expect("rural world source facts survive all derived projections",Data.json_equal(original.world,world.snapshot()))
	door_case(seeded.initial_stocks)
	# Reconfigure/query work is derived-only; the explicit actor fixture above
	# is excluded from this comparison, and no tick/save/game command is used.
	var before:Dictionary=runtime.capture_checkpoint()
	for i in 30:policy.sample(largest[i%largest.size()],4000+i*200);wall_set(policy,building.current_space())
	expect("view sampling cannot mutate ANY world/fact/clock/stock",Data.json_equal(before,runtime.capture_checkpoint()))
	if view!=null:view.free();view=null
	legacy_multistorey()
	finish(started)

func actor_visibility_case(same_room:Array,groups:Dictionary,stocks:Array)->void:
	var query:RefCounted=building.current_space()
	var player:Dictionary=same_room[0]
	var hidden:Dictionary={}
	for points:Array in groups.values():
		for candidate:Dictionary in points:
			if not query.line_clear(player,candidate):hidden=candidate;break
		if not hidden.is_empty():break
	expect("actual closed wall supplies an unseen resident fixture",not hidden.is_empty())
	if hidden.is_empty():return
	initialize_at(player,[resident("unseen",hidden),resident("nearby",player)],stocks)
	var projection:Dictionary=runtime.actor_presentation()
	expect("opening render roof never reveals an NPC behind a closed wall",not projection.visible_actor_ids.has("unseen"),projection.visible_actor_ids)
	expect("player and actually visible neighbor remain rendered",projection.visible_actor_ids.has("player") and projection.visible_actor_ids.has("nearby"),projection.visible_actor_ids)
	var before:Dictionary=runtime.capture_checkpoint()
	for i in 20:runtime.actor_presentation()
	expect("actor sight cache is read-only and not saved authority",Data.json_equal(before,runtime.capture_checkpoint()))

func door_case(stocks:Array)->void:
	var id:=HOME+":kitchen-sleep-door"
	var station:Dictionary={}
	for point:Dictionary in building.use_points(id):
		if not building.current_space().standing_point(point).is_empty():station=point;break
	expect("real internal door has its original safe use station",not station.is_empty())
	if station.is_empty():return
	initialize_at(station,[],stocks)
	var p:=Policy.new();p.configure(building.current_space());p.sample(station,0)
	var room:String=p.statistics().room_id;var wall_ids:=wall_set(p,building.current_space())
	var opened:Dictionary=command("door",id,{"operation":"open"})
	expect("original timed internal door command starts",opened.ok,opened.get("reason"))
	if not opened.ok:return
	for i in 4:runtime.tick(0.1)
	expect("original clock opens actual leaf",building.instance(id).door.open)
	p.configure(building.current_space());p.sample(station,500)
	expect("opening door does not re-partition STRUCTURAL render rooms",p.statistics().room_id==room and wall_set(p,building.current_space())==wall_ids,p.statistics())
	var closed:Dictionary=command("door",id,{"operation":"close"})
	expect("original closing safety and timed command remain active",closed.ok,closed.get("reason"))
	if closed.ok:
		for i in 4:runtime.tick(0.1)
		p.configure(building.current_space());p.sample(station,1000)
		expect("closed leaf restores true state without wall-scope flap",not building.instance(id).door.open and p.statistics().room_id==room and wall_set(p,building.current_space())==wall_ids,p.statistics())

func legacy_multistorey()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<2:expect("legacy source argument explicitly supplied",false);return
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	expect("ordinary old-city source decodes",decoded.ok,decoded.get("reason"))
	if not decoded.ok:return
	var host:=Client.new();var built:Dictionary=host._assemble(decoded.capture)
	expect("ordinary old-city formal assembly succeeds",built.ok,built.get("reason"))
	if not built.ok:host.free();return
	var b:RefCounted=built.services.buildings;var q:RefCounted=b.current_space()
	var groups:Dictionary={}
	for storey:Dictionary in q.state.storeys:
		if not groups.has(storey.buildingId):groups[storey.buildingId]=[]
		groups[storey.buildingId].append(storey)
	var floors:Array=[]
	for building_floors:Array in groups.values():
		if building_floors.size()>1:floors=building_floors;break
	expect("preserved city has an actual multistorey building",floors.size()>1)
	if floors.size()>1:
		floors.sort_custom(func(a:Dictionary,c:Dictionary)->bool:return float(a.elevation)<float(c.elevation))
		var lower:Dictionary=floors[0];var upper:Dictionary=floors[1]
		var piece:Dictionary={}
		for v:Dictionary in q.pieces:
			if v.get("storeyId")==lower.id and q.geometry.definition(v).kind=="floor":piece=v;break
		if piece.is_empty():
			for v:Dictionary in q.pieces:
				if v.get("storeyId")==lower.id:piece=v;break
		var location:Dictionary=Geometry.location(piece);location.y=lower.elevation
		var p:=Policy.new();p.configure(q);p.sample(location,0)
		var higher:Array=q.pieces.filter(func(v:Dictionary)->bool:return v.get("storeyId")==upper.id)
		expect("all ACTUAL upper-storey geometry hides together including walls",not higher.is_empty() and higher.all(func(v:Dictionary)->bool:return not p.base_visible(v,str(q.geometry.definition(v).kind))),{"upper":upper.id,"pieces":higher.size()})
		location.storeyId=upper.id;location.y=upper.elevation
		p.sample(location,100);p.sample(location,300)
		expect("landing change exposes that real floor at its real elevation",p.statistics().storey_id==upper.id and higher.any(func(v:Dictionary)->bool:return q.geometry.definition(v).kind!="roof" and p.base_visible(v,str(q.geometry.definition(v).kind))),p.statistics())
	host.free()

func finish(started:int)->void:
	var report:Dictionary={"scope":"A stable interior policy + real B adapter and retained native rural/old-city geometry; explicit spatial fixtures, not VA/player-route acceptance","checks":checks,"failed":failures.size(),"ms":Time.get_ticks_msec()-started}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		var file:=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify(report));quit(1 if failures.size()>0 else 0)
