extends "res://tests/planning/zone_supply.gd"
## Every existing finite prerequisite/permission/reservation fixture runs through
## both fresh original admission reads and the scoped batched observation.
const CandidateContext=preload("res://scripts/planning/zone_candidate_context.gd")
func rows(tx:RefCounted,requirements:Dictionary=req,design:Dictionary=zone,target:Dictionary=job)->Array:
	var expected:Array=Supply.candidates(zonework,tx,tx.actor("player"),design,target,requirements)
	var observer:=CandidateContext.new(zonework,tx)
	var actual:Array=Supply.candidates(observer,tx,tx.actor("player"),design,target,requirements)
	check("batched offers exactly equal original fresh supply checks",Data.json_equal(expected,actual))
	for work_id:String in ["candidate:another-cell","A:other-work"]:
		var next:Dictionary=target.duplicate(true);next.id="another-cell";next.work_id=work_id
		var original:Array=Supply.candidates(zonework,tx,tx.actor("player"),design,next,requirements)
		var batched:Array=Supply.candidates(observer,tx,tx.actor("player"),design,next,requirements)
		check("shared prerequisite preserves job identity and real excluded holds "+work_id,Data.json_equal(original,batched))
	return actual
