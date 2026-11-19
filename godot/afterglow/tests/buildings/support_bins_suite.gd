extends "res://tests/buildings/legacy_suite.gd"
## Independent frozen broad phase, including ordered EPS/bin-boundary results.
const OriginalSpace=preload("res://tests/buildings/cold_reference/building_space.gd")
const CurrentSpace=preload("res://scripts/buildings/building_space.gd")
func ordered_ids(values:Array)->Array:
	var ids:Array=[]
	for v:Dictionary in values:ids.append(v.id)
	return ids

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var decoded:=Codec.decode_checkpoint(FileAccess.get_file_as_string(args[0]))
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var w:=World.new();w.load_snapshot(imported.world)
	var b:=Building.new();var r:=Runtime.new()
	expect("complete original world and facts configure",r.configure({"world":w,"facts":imported.facts,"services":{"buildings":b}}).ok)
	var before:=w.snapshot();var count:=0
	for dy:float in [-0.000001,0,0.000001,0.014999,0.015001,0.799999,0.800001]:
		var data:Dictionary=b.structures()
		for v:Dictionary in data.instances:v.position.y=float(v.position.y)+dy
		var oq:=OriginalSpace.new();oq.configure(w,data,b.geometry,b.permission)
		var nq:=CurrentSpace.new();nq.configure(w,data,b.geometry,b.permission)
		var mismatches:Array=[]
		for v:Dictionary in data.instances:
			var original:Dictionary=oq.support_neighbors(v);var current:Dictionary=nq.support_neighbors(v);count+=1
			if ordered_ids(original.wall)!=ordered_ids(current.wall) or ordered_ids(original.slab)!=ordered_ids(current.slab):
				if mismatches.size()<10:mismatches.append({"id":v.id,"before_wall":ordered_ids(original.wall),"after_wall":ordered_ids(current.wall),"before_slab":ordered_ids(original.slab),"after_slab":ordered_ids(current.slab)})
		expect("exact ordered support candidates at vertical offset "+str(dy),mismatches.is_empty(),mismatches)
	expect("all 6797 cold support projections checked",count==6797,count)
	expect("height fixtures never modify preserved city or actual actors",w.snapshot()==before and r.facts()==imported.facts)
	print(JSON.stringify({"ok":not failed,"checks":checks,"scope":"ordered broad-phase oracle on all 971 source pieces across exact EPS and 2m vertical-bin boundaries; translated copies only, not regenerated/modified authoritative world"}))
	quit(1 if failed else 0)
