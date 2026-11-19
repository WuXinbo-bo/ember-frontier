extends "res://tests/world/factory_modules.gd"
## Synthetic additive-ID counterexamples only. Actual six-design geometry
## and source adoption are tested separately when B's definitions arrive.

func run()->void:
	var profiles:Array=Catalog.profiles().filter(func(p:Dictionary)->bool:return not p.has("design_id"));var extra:Array=profiles.duplicate(true)
	for source:Dictionary in profiles:
		if source.generation_role not in ["home","storage","workshop"]:continue
		var added:Dictionary=source.duplicate(true)
		added.id="test:added:"+str(source.id);added.geometry_version="test:additive-v1"
		added.visual_family={"home":"home","storage":"warehouse","workshop":"roadside"}[source.generation_role]
		added.design_id="test:design:"+str(source.generation_role);extra.append(added)
	for content:int in [1,2]:
		var locked:Dictionary=Contract.fresh(profiles,content)
		var original:String=JSON.stringify(locked.contract,"",true,true)
		var accepted:Dictionary=Contract.resolve(locked.contract,extra)
		check("additive catalogue IDs preserve exact old pinned input v"+str(content),accepted.ok and Data.json_equal(accepted.profiles,locked.profiles) and JSON.stringify(accepted.contract,"",true,true)==original,accepted.get("reason"))
		var before:Dictionary=Factory.plan_region(713,Vector2i(1,-1),profiles,locked.contract)
		var after:Dictionary=Factory.plan_region(713,Vector2i(1,-1),extra,locked.contract)
		check("old unexplored parcel terrain and resource plan does not reroll v"+str(content),before.ok and after.ok and Data.json_equal(before.plan,after.plan))
		for mode:String in ["missing","geometry","port","metadata"]:
			var bad:Array=extra.duplicate(true)
			if mode=="missing":bad.remove_at(0)
			elif mode=="geometry":bad[0].geometry_version="test:changed"
			elif mode=="port":bad[0].ports[0].use_points[0][0]+=0.5
			else:bad[0].visual_family="home";bad[0].design_id="test:changed"
			check("same saved ID refuses silent "+mode+" v"+str(content),Contract.resolve(locked.contract,bad).get("code")=="MODULE_PROFILE_VERSION_MISMATCH")
	var fresh:Dictionary=Contract.fresh(extra,3)
	check("explicit v3 records additive design metadata and separate content policy",fresh.ok and fresh.contract.content_version==3 and fresh.profiles.any(func(p:Dictionary)->bool:return p.has("visual_family")))
	var bad:Array=extra.duplicate(true);bad[-1].visual_family="unsupported"
	check("invalid selection family is rejected before plan",Contract.fresh(bad,3).get("code")=="INVALID_MODULE_PROFILE_DESIGN")
	var p3:Dictionary=Factory.plan_region(713,Vector2i.ZERO,extra,fresh.contract)
	check("v3 explicitly selects new compatible design roles",p3.ok and p3.plan.parcels.all(func(p:Dictionary)->bool:return str(p.definition_id).begins_with("test:added:")),p3.get("reason"))
	var current:Array=Catalog.profiles();var default_lock:Dictionary=Contract.fresh(current)
	var default_plan:Dictionary=Factory.plan_region(713,Vector2i.ZERO,current,default_lock.contract)
	check("fresh default content2 excludes all newly added design IDs",default_lock.ok and default_lock.contract.content_version==2 and default_plan.ok and default_plan.plan.parcels.all(func(p:Dictionary)->bool:return not Catalog.definition(p.definition_id).has("design_id")))
	# Decode the exact previous real normal-route native evidence without
	# starting its runtime, replacing actors, or promoting its old qualification.
	var args:Array=OS.get_cmdline_user_args()
	if args.size()>1:
		var old:Variant=JSON.parse_string(FileAccess.get_file_as_string(str(args[1])))
		var saved:Variant=JSON.parse_string(old.payload) if old is Dictionary and old.get("payload") is String else null
		var decoded:Dictionary=Codec.decode_checkpoint(saved.world) if saved is Dictionary else {"ok":false}
		check("actual archived normal-route world decodes with its old exact lock",decoded.ok)
		if decoded.ok:
			var world:=State.new();var loaded:Dictionary=world.load_snapshot(decoded.state)
			var input:Dictionary=Factory.region_generation_input(world,extra) if loaded.ok else loaded
			check("actual old world accepts extra definitions and retains original content2 lock",input.ok and input.generation_contract.content_version==2 and Data.json_equal(input.generation_contract,decoded.state.extensions[Factory.CONFIG_KEY]),input.get("reason"))
			var original:Dictionary=Factory.draft_region(713,Vector2i(-1,0),profiles,input.generation_contract)
			var draft:Dictionary=Factory.draft_region_request(input,Vector2i(-1,0))
			check("actual archived-world new region uses old exact profile plan",original.ok and draft.ok and Data.json_equal(original.plan,draft.plan))
	finish()
