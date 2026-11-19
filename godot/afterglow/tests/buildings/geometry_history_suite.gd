extends "res://tests/buildings/legacy_suite.gd"
## Archived geometry and actual CAS/codec boundaries, no save-slot mutation.
const Store=preload("res://scripts/storage/native_store.gd")
const Client=preload("res://scripts/runtime/native_client.gd")

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var raw:=FileAccess.get_file_as_string(args[0]);var decoded:=Codec.decode_checkpoint(raw)
	expect("preserved actual city source decodes",decoded.ok)
	if not decoded.ok:quit(1);return
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var w:=World.new();expect("preserved city world loads",w.load_snapshot(imported.world).ok)
	var b:=Building.new();var r:=Runtime.new()
	expect("actual runtime and schema configure",r.configure({"world":w,"facts":imported.facts,"services":{"buildings":b,"actions":Actions.new(),"production":Production.new()}}).ok)
	var before:=r.capture_checkpoint();var catalog:=b.source_catalog.duplicate(true)
	var baseline:=Geometry.new();baseline.configure(catalog)
	var altered:=catalog.duplicate(true)
	for d:Dictionary in altered.structure_definitions.values():
		d.kind="forged-kind";d.size={"x":50,"y":50,"z":50};d.solids=[];d.sight=[]
		d.surfaceY=100;d.support="unsupported";d.usePoints=[{"x":999,"y":999,"z":999}]
		d.door={};d.stairs={};d.roof_profile={"rise":999}
	var pinned:=Geometry.new();pinned.configure(altered)
	var mismatches:Array=[]
	for id:String in baseline.definitions:
		for key:String in Geometry.GEOMETRY_KEYS:
			if baseline.definitions[id].get(key)!=pinned.definitions[id].get(key):mismatches.append([id,key])
	expect("all archived geometry/use/support fields ignore same-ID catalog rewrite",mismatches.is_empty(),mismatches)
	var old:Dictionary=b.structures().instances[0]
	var explicit:=old.duplicate(true);explicit.geometryVersion=1
	expect("legacy absent version and explicit v1 resolve exactly",baseline.bounds(old)==pinned.bounds(explicit) and baseline.boxes(old)==pinned.boxes(explicit) and baseline.entity(old).bounds==pinned.entity(explicit).bounds)
	var retired:=catalog.duplicate(true);retired.structure_definitions.erase(old.definitionId)
	pinned.configure(retired)
	expect("retired catalog ID still resolves historic geometry",pinned.bounds(old)==baseline.bounds(old) and not pinned.definition(old).is_empty())
	var aesthetic:=catalog.duplicate(true);aesthetic.structure_definitions[old.definitionId].materials={"top":"mint-paint"}
	pinned.configure(aesthetic)
	expect("pure material replacement stays live without changing physics",pinned.definition(old).materials=={"top":"mint-paint"} and pinned.boxes(old)==baseline.boxes(old))
	var added:=catalog.duplicate(true);added.structure_definitions["unused-new-prop"]=catalog.structure_definitions[old.definitionId].duplicate(true)
	pinned.configure(added)
	expect("unused content addition cannot lock or alter existing houses",pinned.boxes(old)==baseline.boxes(old) and pinned.definitions.size()==baseline.definitions.size())
	var unarchived:=old.duplicate(true);unarchived.definitionId="unused-new-prop"
	expect("unarchived structural definition cannot become mutable saved geometry",pinned.definition(unarchived).is_empty())
	var made:=b.make_instance(old.definitionId,"fixture:new-geometry",Geometry.location(old))
	expect("new structures explicitly pin geometry v1",made.geometryVersion==1 and Geometry.supported_version(made.geometryVersion))
	for version:Variant in [0,-1,2,"1",null,true,1.5]:
		var data:=b.structures();var bad:=old.duplicate(true);bad.geometryVersion=version
		for i in data.instances.size():
			if data.instances[i].id==old.id:data.instances[i]=bad
		var prior:=w.entity(old.id);var after:=prior.duplicate(true);after.data.structure=bad
		var rejected:=r._commit({"ok":true,"world_changes":[b.extension_change(Building.EXTENSION,data),{"op":"entity.put","id":old.id,"before_exists":true,"before":prior,"after":after}],"fact_changes":[]})
		expect("unsupported geometry rejected atomically "+str(version),not rejected.ok and r.capture_checkpoint()==before,rejected.get("code"))
	var data:=b.structures()
	for i in data.instances.size():
		if data.instances[i].id==old.id:data.instances[i]=explicit
	var prior:=w.entity(old.id);var after:=prior.duplicate(true);after.data.structure=explicit
	expect("explicit v1 adopts through actual atomic runtime",r._commit({"ok":true,"world_changes":[b.extension_change(Building.EXTENSION,data),{"op":"entity.put","id":old.id,"before_exists":true,"before":prior,"after":after}],"fact_changes":[]}).ok)
	var capture:=r.capture_checkpoint();var encoded:=Store.encode(capture);var restored:=Store.decode(encoded.get("text",""))
	expect("actual native codec accepts explicit and legacy mixture",encoded.ok and restored.ok)
	var host:=Client.new();var assembly:Dictionary=host._assemble(restored.capture) if restored.ok else {"ok":false}
	expect("formal assembler restores mixed geometry versions",assembly.ok,assembly.get("reason"))
	if assembly.ok:
		var actual:Dictionary=assembly.services.buildings.instance(old.id)
		expect("restored geometry metadata and physical bounds preserved",actual.get("geometryVersion")==1 and assembly.services.buildings.geometry.bounds(actual)==baseline.bounds(old))
		expect("restored other legacy instances remain unmodified",assembly.services.buildings.structures().instances[1].has("geometryVersion")==before.world.extensions[Building.EXTENSION].instances[1].has("geometryVersion"))
	host.free()
	expect("all pure geometry queries preserve authoritative facts",r.facts()==before.facts)
	expect("source v5 never rewritten",FileAccess.get_file_as_string(args[0])==raw)
	print(JSON.stringify({"ok":not failed,"checks":checks,"scope":"BBB geometry history/CAS/native codec source checks; not packed app or VA acceptance"}))
	quit(1 if failed else 0)
