extends "res://tests/buildings/camp_suite.gd"
## Approved native resources + existing real finite repair/build/restore route.
## Catalogue access is explicit here; the actual view stays demand-loaded.
func run()->void:
	var view:=preload("res://scripts/buildings/building_view.gd").new()
	view.manifest=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/asset_manifest.json"))
	var rows:Array=[]
	for family:String in ["brick","plaster","wood","roof","zinc","paint"]:
		for state:String in ["intact","aged","damaged","repaired","damage_detail","repair_detail"]:
			var id:="b_"+family+"_"+state
			var entry:Dictionary=view.manifest.textures.get(id,{})
			var m:StandardMaterial3D=view.material(id)
			var valid:bool=not entry.is_empty() and m!=null and m.albedo_texture!=null
			if valid:
				var bytes:PackedByteArray=FileAccess.get_file_as_bytes(entry.resource)
				var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
				valid=hash.finish().hex_encode()==entry.sha256 and entry.image_QA=="passed_image_QA"
				valid=valid and m.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				if state.ends_with("detail"):
					valid=valid and not m.texture_repeat and m.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and m.albedo_texture.get_size()==Vector2(512,512)
				else:valid=valid and m.texture_repeat and m.albedo_texture.get_image().has_mipmaps() and m.albedo_texture.get_size()==Vector2(1024,1024)
			expect("approved original resource/native material contract "+id,valid,entry.get("resource"))
			rows.append({"id":id,"valid":valid,"metres":entry.get("uv",{}).get("meters_xy")})
	view.free()
	print("ACTUAL_STATE_RESOURCE_CONTRACT "+JSON.stringify(rows))
	# The inherited route creates actual finite tool/material work, waits for
	# repair completion, hinges the real leaf, and restores its world/stock.
	super.run()
