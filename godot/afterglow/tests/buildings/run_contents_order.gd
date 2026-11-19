extends "res://tests/buildings/run_view_mount.gd"
## Exact candidate20 reference, actual services, and explicit rendering fixtures.
const Reference=preload("res://tests/buildings/contents_order_reference/building_view.gd")
const World=preload("res://scripts/world/world_state.gd")
const Generator=preload("res://scripts/world/rural_generator.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Gameplay=preload("res://scripts/runtime/rural_gameplay.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
var observations:Dictionary={}
var output:String

func sample(label:String,capture:Dictionary)->Dictionary:
	var host:=Native.new();var built:Dictionary=host._assemble(capture);host.free()
	check(label+" real Native assembly",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return {}
	var runtime:RefCounted=built.runtime;var service:RefCounted=built.services.buildings
	var authority:Dictionary=runtime.capture_checkpoint()
	var old:=Reference.new();old.configure({"runtime":runtime,"service":service})
	var current:Node3D=service.create_view({"runtime":runtime})
	var original:=view_state(old);var actual:=view_state(current)
	var counts:Dictionary={};var valid_count:=true;var private_leaks:Array=[]
	for stock:Dictionary in runtime.facts().stocks:
		var node:MeshInstance3D=current.content_nodes.get(stock.id)
		if not stock.get("searched",false) and node!=null:private_leaks.append(stock.id)
		if node==null:continue
		var boxes:int=0
		for i:int in node.mesh.get_surface_count():boxes+=node.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX].size()/24
		var available:int=0
		for amount:Variant in stock.items.values():available+=mini(3,int(amount))
		counts[stock.id]=boxes
		valid_count=valid_count and boxes==mini(8,available)
	check(label+" original per-item3/total8 visual cap and privacy remain",valid_count and private_leaks.is_empty(),{"counts":counts,"private_leaks":private_leaks})
	var before_ids:Dictionary={}
	for id:String in current.content_nodes:before_ids[id]=current.content_nodes[id].get_instance_id()
	current.rebuild();var same_nodes:=true
	for id:String in before_ids:same_nodes=same_nodes and current.content_nodes.has(id) and before_ids[id]==current.content_nodes[id].get_instance_id()
	check(label+" identical refresh retains every actual content node",same_nodes and before_ids.size()==current.content_nodes.size())
	check(label+" warm rebuild exact complete current output",Data.json_equal(actual,view_state(current)))
	check(label+" neither view writes stocks/actors/clock/world/receipts",Data.json_equal(authority,runtime.capture_checkpoint()))
	var result:Dictionary={"old":original.contents,"current":actual.contents}
	observations[label]={"old_contents_sha256":JSON.stringify(original.contents,"",true,true).sha256_text(),"current_contents_sha256":JSON.stringify(actual.contents,"",true,true).sha256_text(),"all_view_equal":Data.json_equal(original,actual),"counts":counts}
	FileAccess.open(output+"/"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
	result.capture=authority
	old.free();current.free();runtime.retire();return result

func finish_results()->void:
	var report:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"observations":observations,"scope":"Post20 B-only stable contents presentation. Exact20 frozen reference witnesses original first-codec/key-order red; explicit fresh-rural fixture plus unchanged actual24. Numeric Codec DTO tail difference is excluded from this contents-only assertion and remains unresolved; no visual/OS/FPS acceptance."}
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify(report,"",false,true));quit(1 if report.failed else 0)

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2:quit(2);return
	output=args[0];DirAccess.make_dir_recursive_absolute(output)
	# Explicit retained fresh-rural fixture preserves the known first-codec
	# counterexample. No donated materials, NPC route or natural combat claim.
	var world:=World.new();var service:=Building.new();var seed_host:=Runtime.new()
	check("original rural fixture generates",world.load_snapshot(Generator.generate(713)).ok)
	service.configure({"world":world,"runtime":seed_host});var seeded:=service.seed_rural(world)
	check("original rural fixture prepares",seeded.get("ok",false))
	if not seeded.get("ok",false):finish_results();return
	var changes:Array=seeded.world_changes.duplicate(true)
	changes.append_array([service.extension_change(Production.KEY,Initial.production(seeded)),service.extension_change(Gameplay.KEY,Gameplay.initial()),service.extension_change("r3:structure-orders",{"version":1,"orders":[]})])
	var draft:=world.prepare_changes(changes,world.get_revision())
	check("original fixture commits original C CAS",draft.ok and world.commit_prepared(draft.capability).ok)
	if not draft.ok:finish_results();return
	var capture:Dictionary={"world":world.snapshot(),"facts":Initial.facts(seeded),"source":{"test":"explicit B retained rural inventory rendering fixture"}}
	var fresh:=sample("fresh",capture)
	var encoded:=Store.encode(fresh.capture);var decoded:=Store.decode(encoded.get("text","")) if encoded.get("ok",false) else encoded
	check("original real codec roundtrip",decoded.get("ok",false),decoded.get("reason"))
	if not decoded.get("ok",false):finish_results();return
	var cold:=sample("codec-cold",decoded.capture)
	check("candidate20 exact reference independently reproduces first-codec display red",not Data.json_equal(fresh.old,cold.old))
	check("current contents preserve every exact mesh/material/transform/stock value through first codec",Data.json_equal(fresh.current,cold.current))
	var reversed:Dictionary=fresh.capture.duplicate(true)
	for stock:Dictionary in reversed.facts.stocks:
		var keys:Array=stock.items.keys();keys.reverse();var items:Dictionary={}
		for id:String in keys:items[id]=stock.items[id]
		stock.items=items
	check("key-order fixture keeps all original authoritative values",Data.json_equal(fresh.capture,reversed))
	var reverse_state:=sample("reversed-keys",reversed)
	check("candidate20 reference independently exposes key-order presentation dependency",not Data.json_equal(fresh.old,reverse_state.old))
	check("current key order cannot move or substitute displayed material/quantity",Data.json_equal(fresh.current,reverse_state.current))
	var input:String=args[1];var input_sha:=FileAccess.get_sha256(input)
	var real:=Store.decode(FileAccess.get_file_as_string(input))
	check("actual24 exact original input decodes",input_sha=="ef226d9ddcc26834acb691bfec09623fbb32c7408804a1575ce9887a2f26ae48" and real.get("ok",false))
	if real.get("ok",false):
		sample("actual24",real.capture)
		check("existing actual24 already-canonical complete view is unchanged",observations.actual24.all_view_equal)
	check("actual source bytes protected",FileAccess.get_sha256(input)==input_sha)
	finish_results()
