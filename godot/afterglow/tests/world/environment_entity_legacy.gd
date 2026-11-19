extends "res://tests/world/environment_entity_refresh.gd"
## Affected legacy tree geometry branch only, explicit C transaction fixtures.
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1:quit(2);return
	world=State.new();var loaded:Dictionary=world.load_snapshot(Rural.generate())
	check("unchanged rural1 source remains valid",loaded.ok)
	var a:=Baseline.new();var b:=EnvironmentView.new();root.add_child(a);root.add_child(b)
	a.configure({"world":world});b.configure({"world":world,"materials":a.materials})
	compare(a,b,"legacy initial non-atlas-model tree branch")
	var e:Dictionary=world.entity(str(b._roots.keys()[0]));var original:Dictionary=e.duplicate(true);var initial:String=signature(b)
	check("legacy fixture really exercises tree without appearance model",not e.data.has("appearance"))
	e.data.harvest.phase="stump";e.data.solid=false
	replace_entity(e,a,b,"legacy actual entity tree stump fixture")
	check("legacy stump retires full standing crown and body",signature(b)!=initial)
	replace_entity(original,a,b,"legacy standing original fact restoration")
	check("legacy restore keeps exact original geometry UV material and collider",signature(b)==initial)
	var region:String=original.regionId
	var cold:Dictionary=world.prepare_region_residency(region,false,world.get_revision())
	commit_pair(cold.world_changes,a,b,"legacy compressed cold")
	e=world.entity(original.id);e.data.harvest.phase="stump";e.data.solid=false
	replace_entity(e,a,b,"legacy stump edit while cold")
	var warm:Dictionary=world.prepare_region_residency(region,true,world.get_revision())
	commit_pair(warm.world_changes,a,b,"legacy edited warm revisit")
	check("legacy cold edited stump ID remains current",b._roots.has(e.id) and world.entity(e.id).data.harvest.phase=="stump")
	a.free();b.free();costs.scope="affected legacy C geometry and residency fixture only; no old whole-matrix/OS/VA/normal harvesting claim";finish(args[0])
