extends SceneTree
## Metric UV regression on original Godot primitive vertices, not a visual claim.
const Tools=preload("res://scripts/presentation/held_tool_view.gd")
var checks:Array=[]
var failures:Array=[]
func expect(label:String,ok:bool,evidence:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"evidence":evidence})
	if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/asset_manifest.json"))
	for kind:String in ["salvaged_axe","hammer","hand_saw","shovel","pickaxe"]:
		var tool:Node3D=Tools.create(kind)
		expect(kind+" keeps existing tool geometry",tool!=null and tool.get_child_count()>1)
		if tool==null:continue
		var bad:Array=[];var tested:int=0
		for mesh:MeshInstance3D in tool.get_children():
			var material:StandardMaterial3D=mesh.material_override
			var texture_id:String="wood_floor" if mesh==tool.get_child(0) else "zinc"
			var tile:float=float(manifest.textures[texture_id].tile_meters)
			var arrays:Array=mesh.mesh.surface_get_arrays(0)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			for triangle:int in range(0,indices.size(),3):
				for edge:int in 3:
					var a:int=indices[triangle+edge];var b:int=indices[triangle+(edge+1)%3]
					var delta_uv:Vector2=(uv[b]-uv[a])*Vector2(material.uv1_scale.x,material.uv1_scale.y)
					var length_m:float=vertices[a].distance_to(vertices[b])
					if absf(delta_uv.length()*tile-length_m)>0.00001:
						if bad.size()<3:bad.append({"mesh":mesh.name,"metres":length_m,"uv_implied_metres":delta_uv.length()*tile})
					tested+=1
		expect(kind+" samples the manifest metres on every face",bad.is_empty(),{"edges":tested,"mismatches":bad})
		tool.free()
	var stage:=Node3D.new()
	var small:MeshInstance3D=Tools.box(stage,Vector3.ZERO,Vector3(0.045,0.43,0.05),"wood")
	var large:MeshInstance3D=Tools.box(stage,Vector3.ZERO,Vector3(0.52,0.32,0.26),"metal")
	expect("different box dimensions retain exact primitive bounds",small.mesh.get_aabb().size.is_equal_approx(Vector3(0.045,0.43,0.05)) and large.mesh.get_aabb().size.is_equal_approx(Vector3(0.52,0.32,0.26)))
	expect("material sampling still uses original delivered texture pixels",same_base_image(small.material_override.albedo_texture,load(manifest.textures.wood_floor.resource)) and same_base_image(large.material_override.albedo_texture,load(manifest.textures.zinc.resource)))
	expect("both real surface textures contain actual mip levels",small.material_override.albedo_texture.get_image().has_mipmaps() and large.material_override.albedo_texture.get_image().has_mipmaps())
	expect("materials keep nearest mip filtering",small.material_override.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
	expect("unknown legacy tool shape remains explicit null",Tools.create("legacy_tool")==null)
	stage.free()
	print("DDD_SURFACE "+JSON.stringify({"checks":checks,"failures":failures,"ok":failures.is_empty(),"scope":"DDD metric primitive UV regression; no formal app/VA/performance"}))
	quit(0 if failures.is_empty() else 1)
func same_base_image(actual:Texture2D,source:Texture2D)->bool:
	var a:Image=actual.get_image();var b:Image=source.get_image()
	if a==null or b==null:return false
	a=a.duplicate();b=b.duplicate()
	a.clear_mipmaps();b.clear_mipmaps()
	return a.get_size()==b.get_size() and a.get_format()==b.get_format() and a.get_data()==b.get_data()
