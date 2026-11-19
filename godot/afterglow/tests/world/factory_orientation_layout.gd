extends "res://tests/world/factory_country.gd"
## Independent C layout/lock properties against actual immutable B profiles.
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Turn=preload("res://scripts/world/factory_parcel_orientation.gd")

func run()->void:
	var profiles:Array=Catalog.profiles();var policy:Dictionary=Contract.fresh(profiles,4,1)
	check("production profile values accepted by4",policy.ok)
	if not policy.ok:return finish()
	for turns:Array in [[0,4],[0,1,1],[0,true],[0,"1"]]:
		var bad:Array=profiles.duplicate(true);bad[0].allowed_quarter_turns=turns
		check("new4 rejects ambiguous or unsupported transform "+str(turns),Contract.fresh(bad,4).get("code")=="UNSUPPORTED_MODULE_ORIENTATION" and Contract.fresh(bad,3).ok)
	for normal:Variant in [null,[0,0,0],[1,0,0],[0,1,-1]]:
		var bad:Array=profiles.duplicate(true);bad[0].ports[0].normal=normal
		check("new4 refuses inconsistent B direction/normal "+str(normal),Contract.fresh(bad,4).get("code")=="INVALID_MODULE_SERVICE_NORMAL" and Contract.fresh(bad,3).ok)
	var selected:Dictionary={};var bounded:bool=true;var canonical:bool=true;var count:int=0
	for seed:int in [42,713,2026,9001]:
		for z:int in range(-2,3):
			for x:int in range(-2,3):
				var coord:=Vector2i(x,z)
				var lots:Array=Factory._lots(seed,coord,policy.profiles,4)
				for p:Dictionary in lots:
					selected[p.definition_id]=true;count+=1
					var r:Array=p.pad.xz;var ox:float=x*64;var oz:float=z*64
					bounded=bounded and r[0]>=ox+2 and r[1]>=oz+2 and r[2]<=ox+30 and r[3]<=oz+44
					var profile:Dictionary=policy.profiles.filter(func(v:Dictionary)->bool:return v.id==p.definition_id)[0]
					var reversed:Dictionary=profile.duplicate(true);reversed.allowed_quarter_turns.reverse()
					var origin:=Vector2(ox+6,oz+(24 if p.site_id in ["home","store"] else 6 if p.site_id in ["neighbor","woodwork"] else 22))
					canonical=canonical and Data.json_equal(Turn.parcel(profile,origin,Vector2(ox+34,oz+30),p.id),Turn.parcel(reversed,origin,Vector2(ox+34,oz+30),p.id))
	check("four-seed100-coordinate actual family choices retain full slot collars",bounded,{"parcels":count,"definitions":selected.keys()})
	check("all six generated designs covered without a free fuel machine",selected.size()==6 and not selected.has("r34.module.woodshop_long_v2"),selected.keys())
	check("permuting allowed quarter-turn list does not change selection or whole parcel",canonical)
	var deterministic:bool=true;var metrics:Array=[]
	for seed:int in [42,9001]:
		var sequence:Array=[]
		for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1),Vector2i(0,1),Vector2i(-1,-1),Vector2i(1,0)]:
			var a:Dictionary=Factory.plan_region(seed,coord,profiles,policy.contract)
			check("nonprimary seed full roads/pads/ecology compile "+str(seed)+str(coord),a.ok,a.get("reason"))
			if not a.ok:return finish()
			sequence.append({"coord":coord,"plan":a.plan})
		sequence.reverse()
		for row:Dictionary in sequence:
			var b:Dictionary=Factory.plan_region(seed,row.coord,profiles,policy.contract)
			deterministic=deterministic and b.ok and Data.json_equal(row.plan,b.plan)
		metrics.append({"seed":seed,"home":Contract.digest(sequence[-1].plan),"families":sequence[-1].plan.module_seeds.map(func(p:Dictionary)->String:return p.definition_id)})
	check("reverse-order independent plans exact across extra seeds and coordinates",deterministic)
	check("distinct seeds retain real terrain and layout variation",metrics[0].home!=metrics[1].home,metrics)
	var old_policy:Dictionary=Contract.fresh(profiles,3,1)
	var old_source:Dictionary=Factory.generate(713,profiles,old_policy.contract);var new_source:Dictionary=Factory.generate(713,profiles,policy.contract)
	var old_world:=State.new();var new_world:=State.new()
	check("both old/new voxel sources independently validate",old_world.load_snapshot(old_source).ok and new_world.load_snapshot(new_source).ok)
	var to_new:Dictionary=Factory.draft_region_request(Factory.region_generation_input(old_world,profiles),Vector2i(0,1))
	var to_old:Dictionary=Factory.draft_region_request(Factory.region_generation_input(new_world,profiles),Vector2i(0,1))
	check("same-seed late content3 worker cannot enter4 authority",Factory.prepare_region_draft(new_world,to_new,new_world.get_revision()).get("code")=="STALE_GENERATION_CONFIGURATION")
	check("same-seed late content4 worker cannot rotate3 authority",Factory.prepare_region_draft(old_world,to_old,old_world.get_revision()).get("code")=="STALE_GENERATION_CONFIGURATION")
	var extended:Array=profiles.duplicate(true);var added:Dictionary=profiles[0].duplicate(true);added.id="test:additive-module";extended.append(added)
	var recovered:Dictionary=Contract.resolve(policy.contract,extended)
	var pinned:Dictionary=Factory.plan_region(713,Vector2i(0,1),profiles,policy.contract)
	var additive:Dictionary=Factory.plan_region(713,Vector2i(0,1),extended,policy.contract)
	check("additive current catalogue never reselects unexplored pinned4 profile",recovered.ok and Data.json_equal(recovered.profiles,policy.profiles) and additive.ok and pinned.ok and Data.json_equal(additive.plan,pinned.plan))
	var changed:Array=profiles.duplicate(true);changed[0].ports[0].position[0]+=0.5
	check("changed pinned4 service geometry refused",Contract.resolve(policy.contract,changed).get("code")=="MODULE_PROFILE_VERSION_MISMATCH")
	costs={"selected_definitions":selected.keys(),"parcels_checked":count,"extra_seed_signatures":metrics,"scope":"C independent layout/immutable lock properties, actual B profiles only; no renderer/normal route/Native or formal package qualification"}
	finish()
