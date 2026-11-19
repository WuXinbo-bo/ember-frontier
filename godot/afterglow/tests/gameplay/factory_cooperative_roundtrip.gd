extends "res://tests/gameplay/factory_normal_cooperative.gd"
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output_dir=args[0];source_path=args[1]
	DirAccess.make_dir_recursive_absolute(output_dir)
	var text:String=FileAccess.get_file_as_string(source_path);source_sha=text.sha256_text()
	var decoded:Dictionary=Store.decode(text)
	check("original candidate17 prepared native save decodes without edits",decoded.ok)
	if not decoded.ok:return finish()
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture);native.free()
	check("original candidate17 prepared payload restores exact complete facts and all extensions",built.ok and persisted_restore_equal(decoded.capture,built.runtime.facts(),built.world),built.get("reason"))
	if not built.ok:return finish()
	var path:String="event/regional_objectives/r34:regional:townward-roadfall:RH-VILLAGE/warning_basis/defense_route_distance_m"
	var difference:Dictionary={"path":path,"before":97.34375208616257,"after":97.34375208616255}
	check("only diagnosed candidate17 route-distance one ULP is accepted",roundtrip_difference_allowed(difference),difference)
	difference.path=path.replace("defense_route_distance_m","home_route_distance_m")
	check("unlisted route-distance path rejects even one ULP",not roundtrip_difference_allowed(difference))
	difference.path=path
	var bits:=PackedByteArray();bits.resize(8);bits.encode_double(0,difference.before);bits.encode_s64(0,bits.decode_s64(0)-2);difference.after=bits.decode_double(0)
	check("diagnosed path rejects more than one ULP below absolute bound",not roundtrip_difference_allowed(difference))
	difference={"path":"actors/3/fatigue","actor_id":"infected:r34:first-defense:0","restored_actor_id":"infected:r34:first-defense:0","before":22.028800000000018,"after":22.028800000000015}
	check("exact prior diagnosed fatigue path and actor identity accept one ULP",roundtrip_difference_allowed(difference))
	difference.actor_id="another-person"
	check("fatigue exception rejects unproven actor identity",not roundtrip_difference_allowed(difference))
	difference.actor_id="infected:r34:first-defense:0"
	difference.path="actors/1/fatigue"
	check("fatigue exception rejects unproven structure path",not roundtrip_difference_allowed(difference))
	difference.path="actors/1/hp"
	check("HP never inherits fatigue numeric exception",not roundtrip_difference_allowed(difference))
	difference.path="actors/1/pack/water"
	check("inventory never inherits numeric exception",not roundtrip_difference_allowed(difference))
	difference={"path":path,"missing":true}
	check("missing structure at the allowed path still rejects",not roundtrip_difference_allowed(difference))
	difference={"path":path,"before":1e12,"after":1e12+0.0001220703125}
	check("absolute error bound rejects large values even one ULP apart",not roundtrip_difference_allowed(difference))
	var negative_route:Dictionary={"path":path,"before":-97.34375208616257,"after":-97.34375208616255}
	check("diagnosed route distance keeps nonnegative invariant",not roundtrip_difference_allowed(negative_route))
	var negative_fatigue:Dictionary={"path":"actors/3/fatigue","actor_id":"infected:r34:first-defense:0","restored_actor_id":"infected:r34:first-defense:0","before":-22.028800000000018,"after":-22.028800000000015}
	check("diagnosed exact fatigue identity keeps nonnegative invariant",not roundtrip_difference_allowed(negative_fatigue))
	var original_report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_path.get_base_dir()+"/results.json"))
	var failures:Array=original_report.checks.filter(func(row:Dictionary)->bool:return not row.ok)
	var original_differences:Array=failures[0].detail.differences if failures.size()==1 else []
	check("retained original candidate17 failure has only the exact route leaf and all warning behavior equal",original_differences.size()==1 and original_differences[0].path==path and roundtrip_difference_allowed(original_differences[0]),original_differences)
	for field:String in ["started_at","warning_seconds","warning_basis/return_seconds","warning_basis/defense_route_seconds","warning_basis/preparation_seconds"]:
		var forbidden:Dictionary={"path":"event/regional_objectives/r34:regional:townward-roadfall:RH-VILLAGE/"+field,"before":97.34375208616257,"after":97.34375208616255}
		check("warning behavior stays exact "+field,not roundtrip_difference_allowed(forbidden))
	var corrupt:Dictionary=built.runtime.facts();corrupt.actors[0].hp-=1
	check("canonical persisted body mismatch rejects independently of path exceptions",not persisted_restore_equal(decoded.capture,corrupt,built.world))
	corrupt=built.runtime.facts();corrupt.stocks[0].items.water=float(corrupt.stocks[0].items.get("water",0))+1
	check("canonical persisted stock mismatch rejects independently of path exceptions",not persisted_restore_equal(decoded.capture,corrupt,built.world))
	for key:String in [Gameplay.KEY,"r34:workforce","r34:logistics","r34:production"]:
		var changed:Dictionary=decoded.capture.duplicate(true);changed.world.extensions[key]["test_only_corrupt_field"]=true
		check("canonical persisted extension mismatch rejects "+key,not persisted_restore_equal(changed,built.runtime.facts(),built.world))
	finish()
