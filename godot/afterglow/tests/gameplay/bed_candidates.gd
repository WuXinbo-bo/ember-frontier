extends "res://tests/gameplay/generated_cooperation.gd"
## Remote bed candidates consume A's public policy, including the current
## staged claimant; a candidate is not permission to rest without contact.

func run()->void:
	output_dir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output_dir)
	evidence_kind="real-generated-bed-candidate-public-policy-with-explicit-prepared-ownership-fixtures"
	host=Client.new()
	var built:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	if not built.ok or not mount(built.capture):check("bed candidate assembly",false);finish();return
	var id:String="RH-VILLAGE:neighbor:sleeping-place"
	var bed:Dictionary=runtime.world.entity(id)
	check("bed is actual generated sleeping object",not bed.is_empty() and bed.get("data",{}).get("sleeping",false),bed)
	if bed.is_empty():finish();return
	var fixture:Dictionary=runtime.capture_checkpoint()
	fixture.world.entities[id].data.prepared=true
	if not mount(fixture):finish();return
	var residents:RefCounted=runtime._services.residents
	var tx:=preload("res://scripts/actions/domain_draft.gd").new(residents.context)
	var actor:Dictionary=tx.actor("village-resident")
	actor.intent=null
	bed=runtime.world.entity(id)
	var before:Dictionary=runtime.capture_checkpoint()
	check("E remote candidate agrees with A same owner policy",residents._bed_usable(actor,bed,tx)==runtime.bed_availability(actor,id,tx.staged,false).ok)
	check("far candidate never grants immediate no-contact rest",not runtime.life_availability({"kind":"rest","actor_id":actor.id,"target_id":id},actor,tx.staged).ok)
	var claimant:Dictionary=tx.actor("repair-resident")
	claimant.intent={"owner":"runtime","kind":"rest","id":"E:bed:staged-claim","target_id":id,"elapsed":0.0,"duration":12.0}
	check("same-tick claimant blocks E candidate via A policy",not residents._bed_usable(actor,bed,tx))
	claimant.hp=0.0
	check("dead claimant releases candidate without second occupancy cache",residents._bed_usable(actor,bed,tx))
	claimant.hp=100.0;claimant.intent=null
	actor.intent={"owner":"residents","kind":"walk","id":"E:bed:own-walk","steps":[],"step":0,"resident_goal":{"kind":"bed","target_id":id}}
	check("own E bed route does not occupy against itself",residents._bed_usable(actor,bed,tx))
	check("remote candidate pure queries preserve world clock and facts",Data.json_equal(before,runtime.capture_checkpoint()))
	for owner:Variant in [null,"home-residents","unrelated:owner"]:
		var snapshot:Dictionary=fixture.duplicate(true);snapshot.world.entities[id].data.owner=owner
		if not mount(snapshot):continue
		residents=runtime._services.residents
		tx=preload("res://scripts/actions/domain_draft.gd").new(residents.context)
		actor=tx.actor("village-resident");actor.intent=null;actor.householdId="home-residents"
		for consent:bool in [false,true]:
			actor.relationship={"member":true,"consent":consent}
			var expected:bool=owner==null or (owner=="home-residents" and consent)
			check("public/E candidate owner="+str(owner)+" consent="+str(consent),residents._bed_usable(actor,runtime.world.entity(id),tx)==expected and runtime.bed_availability(actor,id,tx.staged,false).ok==expected)
	finish()
