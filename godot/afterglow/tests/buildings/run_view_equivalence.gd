extends "res://tests/buildings/run_view_mount.gd"
## Frozen preimage versus actual formal consumer, without rendering or import.
const Reference=preload("res://tests/buildings/view_mount_reference/building_view.gd")
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
const World=preload("res://scripts/world/world_state.gd")
const Generator=preload("res://scripts/world/rural_generator.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Gameplay=preload("res://scripts/runtime/rural_gameplay.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
var rows:Array=[]
var inherited_cold_differences:Array=[]
var output:String

func except_contents(value:Dictionary)->Dictionary:
	var result:=value.duplicate(false);result.erase("contents");return result

func compare(label:String,old:Node3D,current:Node3D)->Dictionary:
	var a:=view_state(old);var b:=view_state(current)
	var full_equal:bool=Data.json_equal(a,b)
	# Post20 intentionally fixes the already recorded first-save content
	# order. Only this explicit fresh fixture's initial contents differ from
	# the historical reference. Their EXACT expected pixels/geometry are
	# checked against that reference's actual cold-codec output in pair().
	var correction:bool=label in ["retained-rural-interiors initial","retained-rural-interiors warm rebuild"]
	var same:bool=Data.json_equal(except_contents(a),except_contents(b)) if correction else full_equal
	check(label+(" exact non-content state; contents gated by exact frozen cold below" if correction else " exact nodes/mesh arrays/UV/material pixels/transforms/state/visibility"),same)
	var row:Dictionary={"label":label,"same":same,"full_output_equal":full_equal,"contents_correction_checked_against_frozen_cold":correction,"preimage_sha256":JSON.stringify(a,"",true,true).sha256_text(),"new_sha256":JSON.stringify(b,"",true,true).sha256_text(),"preimage_statistics":a.statistics,"new_statistics":b.statistics}
	rows.append(row)
	if not full_equal:
		FileAccess.open(output+"/"+label.validate_filename()+"-old.json",FileAccess.WRITE).store_string(JSON.stringify(a,"\t",true,true))
		FileAccess.open(output+"/"+label.validate_filename()+"-new.json",FileAccess.WRITE).store_string(JSON.stringify(b,"\t",true,true))
	return b

func pair(label:String,capture:Dictionary,city:bool=false)->void:
	var host:=Native.new();var built:Dictionary=host._assemble(capture);host.free()
	check(label+" original Native assembler succeeds",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return
	var runtime:RefCounted=built.runtime;var service:RefCounted=built.services.buildings
	var before:Dictionary=runtime.capture_checkpoint()
	var old:=Reference.new();old.configure({"runtime":runtime,"service":service})
	var current:Node3D=service.create_view({"runtime":runtime})
	var state:=compare(label+" initial",old,current)
	var baseline_initial:=view_state(old)
	old.rebuild();current.rebuild();compare(label+" warm rebuild",old,current)
	var q:RefCounted=service.current_space();var floors:Dictionary={};var stations:Array=[]
	for storey:Dictionary in q.state.storeys:
		if not floors.has(storey.buildingId):floors[storey.buildingId]=[]
		floors[storey.buildingId].append(storey)
	var multilevel:int=0
	for group:Array in floors.values():
		if group.size()<2:continue
		multilevel+=1
		if not stations.is_empty():continue
		for storey:Dictionary in group:
			for piece:Dictionary in q.pieces:
				if piece.get("storeyId")==storey.id:
					var p:=Geometry.location(piece);p.y=storey.elevation;stations.append(p);break
	if city:check(label+" retains actual old city multiple floors and real doors",multilevel>0 and state.statistics.doors>0,{"multilevel_buildings":multilevel,"doors":state.statistics.doors,"stations":stations})
	# View-only policy observations at actual stored floors, never teleporting
	# or changing the authority. Each policy is independent and same-input.
	for i:int in stations.size():
		var p0:=Policy.new();var p1:=Policy.new();p0.configure(q);p1.configure(q)
		p0.sample(stations[i],0);p1.sample(stations[i],0)
		old.set_view_policy(p0);current.set_view_policy(p1)
		compare(label+" floor policy "+str(i),old,current)
	check(label+" both view implementations preserve entire authority",Data.json_equal(before,runtime.capture_checkpoint()))
	old.free();current.free()
	var encoded:Dictionary=Store.encode(before);var decoded:Dictionary=Store.decode(encoded.get("text","")) if encoded.get("ok",false) else encoded
	host=Native.new();var cold:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded;host.free()
	check(label+" real codec cold assembler succeeds",cold.get("ok",false),cold.get("reason"))
	if cold.get("ok",false):
		old=Reference.new();old.configure({"runtime":cold.runtime,"service":cold.services.buildings})
		current=cold.services.buildings.create_view({"runtime":cold.runtime})
		var restored:=compare(label+" codec cold",old,current)
		if label=="retained-rural-interiors":
			var exact_canonical_contents:Dictionary=view_state(old).contents
			check(label+" corrected initial contents equal exact frozen post-codec mesh/materials and stay stable",Data.json_equal(state.contents,exact_canonical_contents) and Data.json_equal(restored.contents,exact_canonical_contents))
		if not Data.json_equal(state,restored):
			FileAccess.open(output+"/"+label+"-before-cold.json",FileAccess.WRITE).store_string(JSON.stringify(state,"\t",true,true))
			FileAccess.open(output+"/"+label+"-after-cold.json",FileAccess.WRITE).store_string(JSON.stringify(restored,"\t",true,true))
			var baseline_restored:=view_state(old)
			FileAccess.open(output+"/"+label+"-frozen-before-cold.json",FileAccess.WRITE).store_string(JSON.stringify(baseline_initial,"\t",true,true))
			FileAccess.open(output+"/"+label+"-frozen-after-cold.json",FileAccess.WRITE).store_string(JSON.stringify(baseline_restored,"\t",true,true))
			# Preserve and expose the original failure: the synthetic fresh rural
			# fixture has unsorted stock keys / float DTOs before its first codec.
			# Preserve numeric DTO red without a tolerance or changed Codec.
			# Post20 contents correction has its independent exact cold gate.
			var inherited:bool=Data.json_equal(except_contents(state),except_contents(baseline_initial)) and Data.json_equal(restored,baseline_restored) and not Data.json_equal(except_contents(baseline_initial),except_contents(baseline_restored))
			check(label+" remaining non-content cold difference exactly reproduces frozen numeric DTO red",inherited)
			inherited_cold_differences.append({"label":label,"exact_preimage_witness":inherited,"original_pre_cold_sha256":JSON.stringify(baseline_initial,"",true,true).sha256_text(),"original_post_cold_sha256":JSON.stringify(baseline_restored,"",true,true).sha256_text(),"unresolved_numeric_DTO":true,"contents_order_corrected_separate_exact_gate":label=="retained-rural-interiors"})
			if label!="retained-rural-interiors":check(label+" actual input cold output remains identical",false)
		else:check(label+" cold output equals original complete derived output",true)
		old.free();current.free();cold.runtime.retire()
	runtime.retire()

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:quit(2);return
	output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var inputs:Array=[]
	for spec:Dictionary in [{"label":"actual24","path":args[1],"sha":"ef226d9ddcc26834acb691bfec09623fbb32c7408804a1575ce9887a2f26ae48"},{"label":"old-city-v5","path":args[2],"sha":"fa93373bfc86868ff949834b6e5744ba077dee52c8801b848ed822640913ad43"}]:
		var sha:=FileAccess.get_sha256(spec.path);var decoded:=Store.decode(FileAccess.get_file_as_string(spec.path))
		check(spec.label+" unchanged actual input identity and decode",sha==spec.sha and decoded.get("ok",false))
		if decoded.get("ok",false):pair(spec.label,decoded.capture,spec.label=="old-city-v5")
		check(spec.label+" original file bytes protected",FileAccess.get_sha256(spec.path)==sha)
		inputs.append({"path":spec.path,"sha256":sha})
	# Explicit retained rural fixture for special interiors and furnishings;
	# not a natural R3.4 player journey or a new world-generation claim.
	var world:=World.new();var service:=Building.new();var seed_host:=Runtime.new()
	check("retained rural fixture world loads",world.load_snapshot(Generator.generate(713)).ok)
	# Seed preparation needs the existing weak host bindings even though it
	# does not execute actors. Real assembly below configures the full facts.
	service.configure({"world":world,"runtime":seed_host});var seeded:Dictionary=service.seed_rural(world)
	if seeded.get("ok",false):
		var changes:Array=seeded.world_changes.duplicate(true)
		changes.append_array([service.extension_change(Production.KEY,Initial.production(seeded)),service.extension_change(Gameplay.KEY,Gameplay.initial()),service.extension_change("r3:structure-orders",{"version":1,"orders":[]})])
		var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
		check("explicit rural fixture uses original world CAS",draft.ok and world.commit_prepared(draft.capability).ok)
		if draft.ok:pair("retained-rural-interiors",{"world":world.snapshot(),"facts":Initial.facts(seeded),"source":{"test":"explicit retained rural rendering fixture"}})
	else:check("retained rural fixture seeds",false,seeded)
	var report:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"inputs":inputs,"pairs":rows,"inherited_cold_differences":inherited_cold_differences,"scope":"Frozen preimage/current exact derived mesh/material pixels/state, actual24 and actual old-city-v5 plus explicit retained rural interior fixture. Post20 initial rural contents intentionally corrected to EXACT frozen post-codec output by separate gate; remaining numeric DTO first-codec red preserved without tolerance. Synchronous cold/warm/codec/policy comparison; no renderer, GPU, FPS, OS or VA."}
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify(report,"",false,true));quit(1 if report.failed else 0)
