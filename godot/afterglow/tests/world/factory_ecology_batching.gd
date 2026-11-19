extends "res://tests/world/factory_modules.gd"
## One-input before/after native geometry equivalence and measured CPU work.
const EnvironmentView=preload("res://scripts/environment/environment_view.gd")

func observed_script(source:String)->GDScript:
	# Headless dummy RenderingServer does not read back uploaded instance
	# transforms. Observe the exact native upload arguments in BOTH sources;
	# do not pretend this checks GPU output or use dummy identity matrices.
	source=source.replace("for i in group.transforms.size():","var recorded_uploads:Array=[]\n\t\t\t\tfor i in group.transforms.size():")
	source=source.replace("multimesh.set_instance_transform(i,group.transforms[i]*transform)","multimesh.set_instance_transform(i,group.transforms[i]*transform)\n\t\t\t\t\trecorded_uploads.append(group.transforms[i]*transform)")
	source=source.replace("node.add_child(item)","item.set_meta(\"test_upload_transforms\",recorded_uploads)\n\t\t\t\tnode.add_child(item)")
	var script:=GDScript.new();script.source_code=source
	return script if script.reload()==OK else null

func native_rows(view:Node3D)->Dictionary:
	var result:Dictionary={}
	for key:String in view._ecology:
		for item:MultiMeshInstance3D in view._ecology[key].get_children():
			var mm:MultiMesh=item.multimesh;var mesh:Mesh=mm.mesh
			for i:int in mm.instance_count:
				var transform:Transform3D=item.get_meta("test_upload_transforms")[i]
				for s:int in mesh.get_surface_count():
					var material:Material=mesh.surface_get_material(s)
					var a:Array=mesh.surface_get_arrays(s)
					var origin:Vector3=transform.origin.snapped(Vector3.ONE*0.001)
					var id:String=str([key,origin,material.resource_name,a[Mesh.ARRAY_VERTEX].size()])
					var vertices:=PackedVector3Array();var normals:=PackedVector3Array()
					for v:Vector3 in a[Mesh.ARRAY_VERTEX]:vertices.append(transform*v)
					for n:Vector3 in a[Mesh.ARRAY_NORMAL]:normals.append((transform.basis*n).normalized())
					if not result.has(id):result[id]=[]
					result[id].append({"vertices":vertices,"normals":normals,"uv":a[Mesh.ARRAY_TEX_UV],"indices":a[Mesh.ARRAY_INDEX],"alpha":material.transparency,"cull":material.cull_mode,"threshold":material.alpha_scissor_threshold,"shadow":item.cast_shadow,"filter":material.texture_filter})
	return result

func compare(a:Dictionary,b:Dictionary)->Dictionary:
	var max_error:float=0.0;var vertices:int=0
	if a.size()!=b.size():return {"ok":false,"reason":"native group identity count","before":a.size(),"after":b.size()}
	for key:String in a:
		if not b.has(key) or a[key].size()!=b[key].size():return {"ok":false,"reason":"native surface identity","key":key}
		var used:Dictionary={}
		for row:Dictionary in a[key]:
			var found:bool=false
			var diagnostic:Array=[]
			for i:int in b[key].size():
				if used.has(i):continue
				var next:Dictionary=b[key][i];var error:float=0.0;var same:bool=true
				for field:String in ["uv","indices","alpha","cull","threshold","shadow","filter"]:same=same and row[field]==next[field]
				if not same or row.normals.size()!=next.normals.size():
					var fields:Array=[]
					for field:String in ["uv","indices","alpha","cull","threshold","shadow","filter"]:
						if row[field]!=next[field]:fields.append(field)
					diagnostic.append({"fields":fields});continue
				for v:int in row.vertices.size():error=maxf(error,row.vertices[v].distance_to(next.vertices[v]))
				for n:int in row.normals.size():error=maxf(error,row.normals[n].distance_to(next.normals[n]))
				if error>0.00002:diagnostic.append({"error":error});continue
				max_error=maxf(max_error,error);vertices+=row.vertices.size();used[i]=true;found=true;break
			if not found:return {"ok":false,"reason":"native geometry/UV/material differed","key":key,"diagnostic":diagnostic}
	return {"ok":true,"vertices":vertices,"max_error_m":max_error}

func rebuild(view:Node3D)->float:
	view._ecology_signatures.clear()
	var start:int=Time.get_ticks_usec();view._sync_ecology(view._derived_entities,[],true)
	return (Time.get_ticks_usec()-start)/1000.0

func run()->void:
	var args:Array=OS.get_cmdline_user_args()
	if args.size()<2:check("explicit frozen previous production source required",false);return finish()
	var previous:GDScript=observed_script(FileAccess.get_file_as_string(str(args[1])))
	var current:GDScript=observed_script(FileAccess.get_file_as_string("res://scripts/environment/environment_view.gd"))
	check("both actual sources compile with identical upload observation",previous!=null and current!=null)
	if previous==null or current==null:return finish()
	var profiles:Array=Catalog.profiles()
	for content:int in [2,3]:
		var policy:Dictionary=Contract.fresh(profiles,content)
		var world:=State.new();var loaded:Dictionary=world.load_snapshot(Factory.generate(713,profiles,policy.contract))
		check("same actual content world loads for before after "+str(content),loaded.ok)
		if not loaded.ok:return finish()
		var facts:Dictionary=world.snapshot();var old:Node3D=previous.new();var next:Node3D=current.new()
		root.add_child(old);root.add_child(next)
		old.configure({"world":world});next.configure({"world":world,"materials":old.materials})
		var before:Dictionary=old.statistics();var after:Dictionary=next.statistics()
		var geometry:Dictionary=compare(native_rows(old),native_rows(next))
		check("every submitted world vertex UV material alpha and shadow remain equivalent "+str(content),geometry.ok,geometry)
		check("actual batch count drops without omitting a persistent patch or root "+str(content),after.ecology_multimeshes<before.ecology_multimeshes and after.ecology_patches==before.ecology_patches and after.tree_roots==before.tree_roots and old._ecology_patch_index==next._ecology_patch_index,{"before":before,"after":after})
		var before_ms:Array=[];var after_ms:Array=[]
		# Warm both real model/mesh caches, then alternate ordering to reduce bias.
		rebuild(old);rebuild(next);await process_frame
		for i:int in 9:
			if i%2==0:before_ms.append(rebuild(old));after_ms.append(rebuild(next))
			else:after_ms.append(rebuild(next));before_ms.append(rebuild(old))
			await process_frame
		before_ms.sort();after_ms.sort()
		check("derived batching never mutates sole world facts "+str(content),Data.json_equal(facts,world.snapshot()))
		costs[str(content)]={"before_multimeshes":before.ecology_multimeshes,"after_multimeshes":after.ecology_multimeshes,"patches":after.ecology_patches,"equivalence":geometry,"before_ms":before_ms,"after_ms":after_ms,"before_median_ms":before_ms[4],"after_median_ms":after_ms[4]}
		old.free();next.free()
	costs.scope="same real cells/plans/frozen previous source; identical test-only observation of actual native upload arguments because headless transform readback is dummy. Geometry and warm rebuild CPU only, not GPU/FPS/RSS/VA or A integration"
	finish()
