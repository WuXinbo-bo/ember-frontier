extends "res://tests/gameplay/factory_normal_cooperative.gd"
## Inspect only the actual immutable17 completed save and its retained failure.
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output_dir=args[0];source_path=args[1]
	DirAccess.make_dir_recursive_absolute(output_dir)
	var text:String=FileAccess.get_file_as_string(source_path);source_sha=text.sha256_text()
	var decoded:Dictionary=Store.decode(text)
	check("original immutable17 completed native payload decodes unchanged",decoded.ok)
	if not decoded.ok:return finish()
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture);native.free()
	check("actual Native completed restore preserves complete facts all extensions and entities strictly",built.ok and persisted_restore_equal(decoded.capture,built.runtime.facts(),built.world),built.get("reason"))
	if not built.ok:return finish()
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_path.get_base_dir()+"/results.json"))
	var failures:Array=report.checks.filter(func(row:Dictionary)->bool:return not row.ok and row.get("detail") is Dictionary and row.detail.has("differences"))
	var differences:Array=failures[0].detail.differences if failures.size()==1 else []
	check("retained original completed failure contains exactly the three diagnosed leaves",differences.size()==3,differences)
	var evidence:Array=[]
	for difference:Dictionary in differences:
		var path:String=difference.path
		if path=="actors/4/fatigue":
			check("old exact fatigue identity and one ULP still accepted",roundtrip_difference_allowed(difference));continue
		# Godot JSON parsing itself rounds the original report before value.
		# Recreate its independently extracted raw binary evidence, never facts.
		difference.before="7d95dbb982064ac0".hex_decode().decode_double(0)
		difference.after="7e95dbb982064ac0".hex_decode().decode_double(0)
		var actor:Dictionary=built.runtime.facts().actors[3]
		var stock:Dictionary=built.runtime.facts().stocks[71]
		var at:Dictionary=actor if path=="actors/3/z" else stock.location
		var before:Vector3=Vector3(at.x,at.y,difference.before)
		var after:Vector3=Vector3(at.x,at.y,difference.after)
		difference.vector_components_equal=exact_vector_components(before,after)
		if path=="actors/3/z":
			difference.actor_id=actor.id;difference.restored_actor_id=actor.id
		else:
			difference.stock_id=stock.id;difference.restored_stock_id=stock.id
		check("real exact identity and path accepts only diagnosed coordinate "+path,roundtrip_difference_allowed(difference),difference)
		check("actual Vector3 components remain exactly equal "+path,difference.vector_components_equal)
		var first:=PackedByteArray();first.resize(8);first.encode_double(0,difference.before)
		var second:=PackedByteArray();second.resize(8);second.encode_double(0,difference.after)
		check("raw original bitstrings reproduce exactly one ULP "+path,absi(first.decode_s64(0)-second.decode_s64(0))==1 and difference.after-difference.before==difference.delta)
		check("actual decoded coordinate equals the evidenced restored binary value "+path,at.z==difference.after)
		evidence.append({"difference":difference.duplicate(true),"before_bytes_le":first.hex_encode(),"after_bytes_le":second.hex_encode(),"ulp":absi(first.decode_s64(0)-second.decode_s64(0)),"before_vector":[before.x,before.y,before.z],"after_vector":[after.x,after.y,after.z]})
		var wrong:Dictionary=difference.duplicate(true)
		wrong["actor_id" if path=="actors/3/z" else "stock_id"]="other-original-identity"
		check("same coordinate exception rejects another original identity "+path,not roundtrip_difference_allowed(wrong))
		wrong=difference.duplicate(true);wrong.path=path.replace("/3/","/2/").replace("/71/","/70/")
		check("same identity exception rejects unproven index path "+path,not roundtrip_difference_allowed(wrong))
		wrong=difference.duplicate(true);wrong.path=path.trim_suffix("z")+"x"
		check("same identity exception rejects unproven axis "+path,not roundtrip_difference_allowed(wrong))
		wrong=difference.duplicate(true);wrong.vector_components_equal=false
		check("coordinate exception rejects changed actual geometry "+path,not roundtrip_difference_allowed(wrong))
		wrong=difference.duplicate(true);second.encode_s64(0,first.decode_s64(0)+2);wrong.after=second.decode_double(0)
		check("coordinate exception rejects two ULP below absolute bound "+path,not roundtrip_difference_allowed(wrong))
		wrong=difference.duplicate(true);wrong.before=-1e12;wrong.after=-1e12-0.0001220703125
		check("coordinate exception rejects one ULP above absolute bound "+path,not roundtrip_difference_allowed(wrong))
		wrong=difference.duplicate(true);wrong.before=str(wrong.before)
		check("coordinate exception requires float to float "+path,not roundtrip_difference_allowed(wrong))
	var corrupt:Dictionary=decoded.capture.duplicate(true)
	var entity_id:String=corrupt.world.entities.keys()[0]
	corrupt.world.entities[entity_id]["test_only_corrupt_field"]=true
	check("original entity mutation rejects independently of coordinate allowance",not persisted_restore_equal(corrupt,built.runtime.facts(),built.world))
	FileAccess.open(output_dir+"/coordinate-evidence.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t",true,true))
	finish()
