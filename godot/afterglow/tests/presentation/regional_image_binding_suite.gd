extends SceneTree
const Ecology=preload("res://scripts/presentation/ecology_visual.gd")
var checks:Array=[]
var failures:Array=[]
func expect(label:String,ok:bool,detail:Variant={})->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var view:=Ecology.new();root.add_child(view);view.set_process(false);view.sync({"available":true,"visuals":[]})
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Ecology.REGIONAL_ASSETS))
	for row:Dictionary in manifest.assets:
		expect("source SHA exact "+row.id,FileAccess.get_sha256(row.resource)==row.sha256)
		var material:StandardMaterial3D=view._quality.material(row.id)
		var source:Image=material.albedo_texture.get_image() if material.albedo_texture!=null else null
		expect("actual 512RGBA texture with native mip chain "+row.id,source!=null and source.get_width()==512 and source.get_height()==512 and source.has_mipmaps() and source.detect_alpha()!=Image.ALPHA_NONE)
		expect("native cutout and depth sampling "+row.id,material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and is_equal_approx(material.alpha_scissor_threshold,.4) and not material.texture_repeat and not material.no_depth_test and material.cull_mode==BaseMaterial3D.CULL_DISABLED)
		var parts:Array=view._quality.cutout_parts(row.id,float(row.visible_size_m[0]))
		var mesh:Mesh=parts[0].mesh;var bounds:AABB=mesh.get_aabb()
		expect("fixed species canvas, not mature-normalized seedling "+row.id,absf(bounds.size.x-float(row.full_canvas_m[0]))<.00001 and absf(bounds.size.y-float(row.full_canvas_m[1]))<.00001,{"bounds":str(bounds)})
		var top:float=(float(row.pivot[1])-float(row.alpha_bbox[1])/512.0)*float(row.full_canvas_m[1])
		var bottom:float=(float(row.pivot[1])-float(row.alpha_bbox[3])/512.0)*float(row.full_canvas_m[1])
		expect("pixel baseline reaches actual root and metric height "+row.id,absf(bottom)<.00001 and absf(top-float(row.visible_size_m[1]))<=float(row.full_canvas_m[1])/512.0,{"top_m":top,"bottom_m":bottom})
	expect("all seven stage images registered once",manifest.assets.size()==7 and view._quality.failures.is_empty())
	view.free();await process_frame
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"scope":"exact pixel source/native material/metric UV and cutout mesh, headless only, no renderer/PCK/normal-camera VA","checks":checks,"failures":failures},"\t"))
	print("DDD_REGIONAL_IMAGES ",JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
