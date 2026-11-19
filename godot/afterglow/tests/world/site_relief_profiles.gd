extends "res://tests/world/site_relief_candidate.gd"
const Old=preload("res://scripts/world/local_relief.gd")
func run()->void:
	var args:=OS.get_cmdline_user_args();var rows:Array=[]
	for seed:int in [12,713]:
		var old_source:Dictionary=FileAccess.open(args[1]+"/seed%d-v7-source.var"%seed,FileAccess.READ).get_var()
		var new_source:Dictionary=FileAccess.open(args[2]+"/seed%d-v8-source.var"%seed,FileAccess.READ).get_var()
		var old:=State.new();var world:=State.new();old.load_snapshot(old_source);world.load_snapshot(new_source)
		var noise:=Generator._noise(seed);var row:Dictionary={"seed":seed,"profiles":[],"parcels":[]}
		for id:String in ["RH-HOME","RH-VILLAGE"]:
			var a:Dictionary=old.extension("generation:"+id);var b:Dictionary=world.extension("generation:"+id)
			check("exact unchanged underlying natural features "+str(seed)+id,Data.json_equal(a.height.natural_surface.relief_features,b.height.natural_surface.relief_features))
			var aligned:=true;var pads:Array=[]
			for i in a.parcels.size():
				var p:Dictionary=a.parcels[i];var q:Dictionary=b.parcels[i];var delta:float=q.pad.height-p.pad.height
				aligned=aligned and Data.json_equal(p.pad.xz,q.pad.xz) and q.origin.y==p.origin.y+delta
				for j in p.entrance_ports.size():aligned=aligned and q.entrance_ports[j].position.y==p.entrance_ports[j].position.y+delta
				for j in p.use_reservations.size():
					aligned=aligned and q.use_reservations[j].bounds.min.y==p.use_reservations[j].bounds.min.y+delta and q.use_reservations[j].bounds.max.y==p.use_reservations[j].bounds.max.y+delta
				pads.append({"parcel":p.id,"before_y":p.pad.height,"after_y":q.pad.height,"edge_low":Relief._edge_low(noise,q.pad.xz),"xz":q.pad.xz})
			row.parcels.append_array(pads)
			check("whole footprints ports and use reservations shift together "+str(seed)+id,aligned,pads)
			for land:Dictionary in b.landforms:
				if land.use!="dry-ditch":continue
				var max_cut:=0.0;var finite_support:=true;var matching_material:=true
				var features:Array=b.height.natural_surface.relief_features
				for zi in range(floori(land.xz[1]*2)-4,ceili(land.xz[3]*2)+5):
					for xi in range(floori(land.xz[0]*2)-8,ceili(land.xz[2]*2)+9):
						var x:float=xi*0.5;var z:float=zi*0.5;var weight:float=Relief.channel_weight(noise,land,x,z)
						max_cut=maxf(max_cut,Old._base_from(noise,x,z,features)-Relief._desired(noise,x,z,[land],features))
						if z<=land.xz[1] or z>=land.xz[3]:finite_support=finite_support and weight==0.0
						matching_material=matching_material and Relief.material_contains(noise,land,x,z)==(weight>=0.5)
				check("closed relative half-metre channel and matching material "+str(seed)+id,max_cut<=0.5 and max_cut>0.4 and finite_support and matching_material,{"max_prequantized_cut_m":max_cut,"ends_zero":finite_support,"material_agrees":matching_material})
		for section:Dictionary in [{"name":"ditch-cross","axis":"x","fixed":45.75,"from":30.25,"count":37},{"name":"ditch-closed-end","axis":"x","fixed":59.75,"from":30.25,"count":37},{"name":"repair-apron","axis":"z","fixed":49.75,"from":-34.25,"count":33},{"name":"field-store-coupling","axis":"x","fixed":-16.75,"from":17.25,"count":25}]:
			var pairs:Array=[]
			for i in int(section.count):
				var v:float=section["from"]+i*0.5;var x:float=v if section.axis=="x" else float(section.fixed);var z:float=v if section.axis=="z" else float(section.fixed)
				pairs.append({"x":x,"z":z,"before_y":old.surface_height(x,z),"after_y":world.surface_height(x,z)})
			row.profiles.append({"section":section,"half_metre_samples":pairs})
		var unchanged:=true
		for zi in range(93,111):
			for xi in range(61,66):unchanged=unchanged and old.surface_height((xi+0.5)*0.5,(zi+0.5)*0.5)==world.surface_height((xi+0.5)*0.5,(zi+0.5)*0.5)
		check("identified x32 natural hollow is preserved "+str(seed),unchanged)
		var repair:Dictionary=world.extension("generation:RH-VILLAGE").parcels.filter(func(p:Dictionary)->bool:return p.site_id=="repair")[0]
		check("measured high repair platform fill reduced with full footprint retained "+str(seed),repair.pad.height==1.0 and world.surface_height(49.75,-26.25)==0.5,{"pad":repair.pad,"measured_apron_y":world.surface_height(49.75,-26.25)})
		rows.append(row)
	costs.rows=rows;costs.scope="Actual saved-source coordinates and same v7 natural features. New v8 site controls only; continuous channel depth is before shared quantization and safety. Profiles are not image/OS/VA qualification."
	finish()
