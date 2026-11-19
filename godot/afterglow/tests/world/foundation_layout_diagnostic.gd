extends SceneTree
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const Contract=preload("res://scripts/world/generation_contract.gd")
const Layout=preload("res://scripts/world/bounded_layout.gd")
const Generator=preload("res://scripts/world/settlement_generator.gd")
func _initialize()->void:
 var profiles:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/generation_profiles.json")).profiles
 var input:Dictionary=Contract.fresh(profiles).contract;input.layout_policy=Layout.POLICY.duplicate()
 var result:Dictionary=Landscape.plan_region(0,Vector2i.ZERO,profiles,input)
 var policy:Dictionary=input.residential_selection.duplicate(true);policy.layout_policy=input.layout_policy
 var parcels:Array=Generator._parcels(0,Vector2i.ZERO,Generator._noise(0),profiles,policy)
 print(JSON.stringify({"result":result if not result.ok else {"ok":true},"parcels":parcels}))
 quit()
