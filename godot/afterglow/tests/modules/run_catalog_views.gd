extends "res://tests/modules/run_stock_layout.gd"
## Built-in read-only containers guard shared process metadata; public copies
## remain writable. Real owner validators still reject capacity/version edits.
func frozen(value:Variant)->bool:
	if value is Dictionary:
		if not value.is_read_only():return false
		for child:Variant in value.values():
			if not frozen(child):return false
	elif value is Array:
		if not value.is_read_only():return false
		for child:Variant in value:
			if not frozen(child):return false
	return true

func run()->void:
	var timings:Array=[]
	for d:Dictionary in Catalog.definitions():
		var shared:Dictionary=Catalog.definition_view(d.id)
		check("all nested definition containers are read only "+d.id,not shared.is_empty() and frozen(shared) and Data.json_equal(shared,d))
		var mutable:Dictionary=Catalog.definition(d.id);mutable.name="caller changed";mutable.ports.clear();mutable.buffer_specs[0].limits.clear()
		check("public editable copies cannot poison shared catalog "+d.id,Data.json_equal(shared,Catalog.definition(d.id)) and not shared.ports.is_empty())
	var id:String="r34.module.woodshop_long_v2";var checksum:int=0
	var expected:int=Catalog.definition(id).buffer_specs.size()*10000*2*5
	for pass_index:int in 5:
		var start:int=Time.get_ticks_usec()
		for i:int in 10000:checksum+=int(Catalog.definition(id).buffer_specs.size())
		var copy_usec:int=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
		for i:int in 10000:checksum+=int(Catalog.definition_view(id).buffer_specs.size())
		timings.append({"pass":pass_index,"copies_10000_usec":copy_usec,"immutable_reads_10000_usec":Time.get_ticks_usec()-start})
	check("both native metadata paths read identical definitions",checksum==expected and Catalog.statistics().file_reads==1,{"checksum":checksum,"expected":expected,"catalog":Catalog.statistics()})
	var lock:=Contract.fresh(Catalog.profiles(),3);var made:Dictionary=Assembly.prepare(Generator.generate(713,Catalog.profiles(),lock.contract))
	var host:=Native.new();var built:Dictionary=host._assemble(made.capture) if made.ok else made;host.free()
	check("real normal world configures with immutable internal readers",built.ok,built.get("reason"))
	if built.ok:
		var modules:RefCounted=built.services.modules;var facts:Dictionary=built.runtime.facts()
		var original:Dictionary=built.runtime.capture_checkpoint();var valid:Dictionary=modules.validate_extensions(facts)
		check("same full original module validation remains required",valid.ok,valid)
		var extension:Dictionary=modules.state();var m:Dictionary=extension.instances[0]
		var oversized:Dictionary=facts.duplicate(true);var stock:Dictionary=Draft.find(oversized.stocks,str(m.stock_refs.values()[0]));stock.items[Catalog.definition_view(m.definition_id).buffer_specs[0].limits.keys()[0]]=99999
		check("capacity overflow remains rejected after metadata reuse",modules.validate_extensions(oversized).get("code")=="MODULE_BUFFER_CAPACITY")
		var bad_geometry:Dictionary=extension.duplicate(true);bad_geometry.instances[0].geometry_version="forged"
		check("pinned version mismatch remains rejected",modules.validate_extensions(facts,{Modules.KEY:bad_geometry}).get("code")=="MODULE_GEOMETRY_VERSION_MISMATCH")
		check("all observations and rejected proposals preserve authority",Data.json_equal(original,built.runtime.capture_checkpoint()))
	var ok:bool=checks.all(func(c:Dictionary)->bool:return c.ok)
	print(JSON.stringify({"ok":ok,"checks":checks,"timings":timings,"scope":"same process catalog read/copy cost plus real unchanged validators; not FPS or package acceptance"}));quit(0 if ok else 1)
