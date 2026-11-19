extends RefCounted
## Existing delivered rigs and one unchanged body. No new actor simulation.
const BODY_ID:="human-default-v1"
const HUMAN:Array=["r1_resident_commuter","r1_resident_neighbor","r1_resident_shopkeeper"]
const INFECTED:="infected_walker"
const OPENING14:="res://data/gameplay/actors/opening_v14.json"
const NEW_HUMAN:Array=["village_linxia_v14","village_chentuo_v14"]

static func opening_definitions()->Dictionary:
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(OPENING14))
	return parsed.get("actors",{}) if parsed is Dictionary else {}

static func apply_opening(actors:Array,layout:Dictionary)->void:
	if int(layout.get("content_version",0)) not in [14,15,16,17,18,19,20,21]:return
	var definitions:Dictionary=opening_definitions()
	for actor:Dictionary in actors:
		var spec:Dictionary=definitions.get(str(actor.get("id","")),{})
		if not spec.is_empty():actor.merge(spec.duplicate(true),true)

static func model_profile(profile:String)->String:
	return HUMAN[0] if profile in NEW_HUMAN else profile

static func for_new_actor(id:String)->String:
	if id=="player":return HUMAN[0]
	if id=="village-resident":return HUMAN[1]
	if id=="repair-resident":return HUMAN[2]
	return HUMAN[posmod(id.hash(),HUMAN.size())]

static func normalize_legacy(actors:Array)->Array:
	var result:Array=actors.duplicate(true)
	for i:int in result.size():
		var actor:Dictionary=result[i]
		# Preserve the previous display mapping exactly once, before any sorting.
		if not actor.has("appearance_id"):actor.appearance_id=INFECTED if actor.get("faction")=="infected" else HUMAN[i%HUMAN.size()]
		if not actor.has("body_profile_id"):actor.body_profile_id=BODY_ID
	return result

static func valid(actor:Dictionary)->bool:
	return actor.get("appearance_id") in HUMAN+NEW_HUMAN+[INFECTED] and actor.get("body_profile_id")==BODY_ID
