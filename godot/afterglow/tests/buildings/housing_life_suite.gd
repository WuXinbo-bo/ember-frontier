extends "res://tests/buildings/generated_camp_suite.gd"
## New residences use real generated terrain, the sole runtime, finite stock,
## existing labor and actual native renderer. Not OS input or VA evidence.
var active_view:Node3D

func perform(label:String,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->bool:
	print("HOUSING_ACTION_BEGIN "+JSON.stringify({"seed":world.identity().seed,"label":label,"kind":kind,"time":runtime.clock()}))
	var accepted:=super.perform(label,kind,target,payload,destination)
	print("HOUSING_ACTION_END "+JSON.stringify({"seed":world.identity().seed,"label":label,"ok":accepted,"time":runtime.clock(),"activity":runtime.actor("player").get("activity")}))
	return accepted

func seeds_to_check()->Array:
	return [6,12]

func expected_home_profile(seed:int)->String:
	return "homestead_compact" if seed==6 else "homestead_courtyard"

func generated_opening()->void:
	super.generated_opening()
	if active_view!=null:
		expect("actual completed labor keeps cabinet and removes dismantled workbench",active_view.objects.has("RH-HOME:home:storage") and not active_view.objects.has("RH-HOME:home:workbench-reservation"))
		for child:Node in active_view.get_children():child.queue_free()
		await process_frame
		active_view.queue_free();active_view=null
		await process_frame

func verify_domestic_route()->void:
	active_view=building.create_view({"runtime":runtime})
	active_view.set_view_policy(preload("res://scripts/presentation/interior_view_policy.gd").new())
	var floors:Dictionary={};var native_surfaces:Dictionary={};var purposes:Dictionary={}
	for piece:Dictionary in building.structures().instances:
		if piece.get("buildingId")!="RH-HOME:home" or piece.definitionId!="foundation":continue
		var finish:Dictionary=piece.get("presentation",{})
		floors[finish.get("floor","")]=true
		if finish.has("room_purpose"):purposes[finish.room_purpose]=true
	for node:MeshInstance3D in active_view.static_nodes.values():
		var piece:Dictionary=node.get_meta("piece")
		if piece.get("buildingId")!="RH-HOME:home":continue
		for surface:int in node.mesh.get_surface_count():
			var material:Material=node.mesh.surface_get_material(surface)
			for id:String in ["wood_floor","ceramic","concrete"]:
				if material==active_view.materials.get(id):native_surfaces[id]=true
	expect("authored sleep kitchen living storage and work zones have actual distinct floor finishes",floors.has_all(["wood_floor","ceramic","concrete"]) and native_surfaces.has_all(["wood_floor","ceramic","concrete"]) and purposes.has_all(["sleep","cooking-water","living","stock","work"]),{"floors":floors,"native_surfaces":native_surfaces,"purposes":purposes})
	for suffix:String in ["storage","kitchen","table","chair","writing-desk"]:
		var target:String="RH-HOME:home:"+suffix
		var at_target:=false;var refusals:Array=[]
		for point:Dictionary in building.use_points(target):
			var attempt:=command("walk","",{},point)
			if not attempt.ok:refusals.append(attempt.get("reason"));continue
			if completed() and building.can_use("player",building.instance(target))==null:at_target=true;break
		expect("real body route and true use line reach residential "+suffix,at_target,refusals)
		if not at_target:return
	print("ACTUAL_HOUSING_ROOMS "+JSON.stringify({"profile":world.extension("r3:building-generation").parcels["RH-HOME:home"].profile_id,"floors":floors.keys(),"native_surfaces":native_surfaces.keys(),"purposes":purposes.keys(),"scope":"real finite runtime commands, not OS inputs or rendered screenshot"}))
