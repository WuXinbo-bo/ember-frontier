extends "res://tests/buildings/domain_suite.gd"
## Exact frozen pre-housing recipes, including stable IDs and finite contents.
const Before=preload("res://tests/buildings/housing_reference.gd")
const Current=preload("res://scripts/buildings/building_families.gd")
const Baseline=preload("res://scripts/world/generation_contract.gd")

func output(script:GDScript,profile:Dictionary,quarter:int)->Dictionary:
	var family:RefCounted=script.new()
	family.service=building;family.profile=profile.duplicate(true)
	family.parcel={"origin":{"x":-20.0,"y":2.5,"z":31.0},"quarter_turn":quarter}
	family.region_id="retained-region";family.building_id="retained-home";family.floor_id="retained-home:ground"
	family.shell();family.contents();family.courtyard()
	var result:Dictionary={}
	for key:String in ["instances","storeys","stocks","records","tools","extra","entrances","anchors"]:result[key]=family.get(key).duplicate(true)
	return result

func run()->void:
	var started:=Time.get_ticks_msec()
	building.configure({"world":world,"runtime":runtime})
	var profiles:Array=Baseline.baseline(Building.generation_profiles())
	expect("exact retained six recipes selected explicitly",profiles.size()==6)
	for profile:Dictionary in profiles:
		for quarter:int in 4:
			var before:=output(Before,profile,quarter)
			var current:=output(Current,profile,quarter)
			expect("original six full recipe DTOs unchanged "+str(profile.id)+" q"+str(quarter),before==current,{"structures":current.instances.size(),"stocks":current.stocks.size(),"tools":current.tools.size()})
	finish(started)
