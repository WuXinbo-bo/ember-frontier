extends "res://tests/world/factory_orientation_scale.gd"
## Diagnose every live->JSON coordinate leaf; no production float relaxation.
func differences(a:Variant,b:Variant,path:String="plan",segments:Array=[])->Array:
	var result:Array=[]
	if (a is int or a is float) and (b is int or b is float):
		if a!=b:
			var before_bits:PackedByteArray=PackedFloat64Array([float(a)]).to_byte_array()
			var after_bits:PackedByteArray=PackedFloat64Array([float(b)]).to_byte_array()
			result.append({"path":path,"segments":segments,"before":a,"after":b,"before_type":typeof(a),"after_type":typeof(b),"before_literal":JSON.stringify(a,"",true,true),"after_literal":JSON.stringify(b,"",true,true),"before_bits_le":before_bits.hex_encode(),"after_bits_le":after_bits.hex_encode(),"abs":absf(float(a)-float(b)),"ulp":absi(before_bits.decode_s64(0)-after_bits.decode_s64(0)) if signf(float(a))==signf(float(b)) else 9223372036854775807})
	elif a is Dictionary and b is Dictionary:
		for key:Variant in a:
			if not b.has(key):result.append({"path":path+"."+str(key),"reason":"missing restored key"});continue
			result.append_array(differences(a[key],b[key],path+"."+str(key),segments+[key]))
		for key:Variant in b:
			if not a.has(key):result.append({"path":path+"."+str(key),"reason":"unexpected restored key"})
	elif a is Array and b is Array:
		if a.size()!=b.size():result.append({"path":path,"reason":"array count changed","before_size":a.size(),"after_size":b.size()});return result
		for i:int in a.size():result.append_array(differences(a[i],b[i],path+"["+str(i)+"]",segments+[i]))
	elif a!=b:result.append({"path":path,"reason":"non-numeric difference","before":a,"after":b,"before_type":typeof(a),"after_type":typeof(b)})
	return result

func run()->void:
	profiles=Catalog.profiles();var configured:Dictionary=Contract.fresh(profiles,4,1)
	check("actual4/1 policy resolves for exact numeric diagnostics",configured.ok)
	if not configured.ok:return finish()
	policy=configured.contract
	var decoded_contract:Variant=JSON.parse_string(JSON.stringify(policy,"",true,true))
	check("authoritative configuration preserves exact values and digest through JSON",Data.json_equal(policy,decoded_contract) and Contract.digest(policy)==Contract.digest(decoded_contract))
	var coords:Array=[Vector2i.ZERO,Vector2i(0,-1)];coords.append_array(order(false))
	var observations:Array=[];var all_bounded:bool=true;var noncoordinate:Array=[]
	var approved_indexed:bool=true;var vectors_exact:bool=true
	for seed:int in [713,2026]:
		for coord:Vector2i in coords:
			var generated:Dictionary=Factory.plan_region(seed,coord,profiles,policy)
			if not generated.ok:check("diagnostic actual plan compiles "+str(seed)+str(coord),false,generated);return finish()
			var before:Dictionary=generated.plan
			var after:Variant=JSON.parse_string(JSON.stringify(before,"",true,true))
			var leaves:Array=Roundtrip.differences(before,after)
			var bounds_ok:bool=true
			for leaf:Dictionary in leaves:
				bounds_ok=bounds_ok and not leaf.has("reason") and leaf.before_type==TYPE_FLOAT and leaf.after_type==TYPE_FLOAT and leaf.abs<1e-12 and leaf.ulp<=1
				vectors_exact=vectors_exact and leaf.get("vector2_components_exact",false) and leaf.get("vector3_components_exact",false)
				if not Roundtrip.approved(seed,before.region_id,leaf):noncoordinate.append({"seed":seed,"region":before.region_id,"difference":leaf});approved_indexed=false
			all_bounded=all_bounded and bounds_ok
			var old_summary:String=Contract.digest(before);var new_summary:String=Contract.digest(after)
			if not leaves.is_empty() or old_summary!=new_summary:
				observations.append({"seed":seed,"region":before.region_id,"leaves":leaves,"summary_before":old_summary,"summary_after":new_summary,"default_precision_canonical_differences":differences(JSON.parse_string(JSON.stringify(before)),JSON.parse_string(JSON.stringify(after))) if old_summary!=new_summary else []})
	check("all48 actual plans have only sub1e-12 at-most1ULP float changes",all_bounded)
	check("all changed leaves match A exact indexed path and bit-pair whitelist",approved_indexed and noncoordinate.is_empty(),noncoordinate)
	check("all changed geometric inputs convert to exactly identical Vector2 and Vector3 components",vectors_exact)
	var observed_leaf:Dictionary=observations[0].leaves[0].duplicate(true)
	observed_leaf.path="plan.unapproved.x"
	check("same tiny float delta outside exact indexed field cannot pass",not Roundtrip.approved(713,"R34:0:1",observed_leaf))
	check("ID count and quarter-turn mutations remain strict failures",not Roundtrip.compare(713,"R34:0:1",{"id":"one","quarter_turn":1,"items":[1]},{"id":"two","quarter_turn":2,"items":[1,2]}).ok)
	costs={"seeds":[713,2026],"plans":coords.size()*2,"observations":observations,"non_path_point_changes":noncoordinate,"scope":"all live->full-precision JSON leaves only; raw bit evidence, no blanket tolerance, codec change or declared native acceptance"}
	finish()
