extends "res://tests/modules/factory_boundary_fixture.gd"
## Exercises actual machine state transitions, not validator-only capacities
## or renderer DTOs. argv[0], when present, is an OUTPUT DIRECTORY.
func machine_state(rt:RefCounted)->Dictionary:return rt.world.extension(Factory.KEY)
func order(rt:RefCounted)->Dictionary:return machine_state(rt).orders[0]
func outputs(rt:RefCounted,m:Dictionary)->float:return float(rt.stock(m.stock_refs.output).items.get("timber",0))
func run()->void:
	var fixture:=machine_fixture()
	if fixture.is_empty():finish();return
	var capture:Dictionary=fixture.capture;var m:Dictionary=fixture.module
	Draft.find(capture.facts.stocks,m.stock_refs.input).items={"log":4}
	Draft.find(capture.facts.stocks,m.stock_refs.fuel).items={"log":1}
	Draft.find(capture.facts.stocks,m.stock_refs.output).items={"timber":64}
	put_actor(capture,port(m,"board-output"))
	var mounted:=mount(capture,"full output boundary")
	if not mounted.ok:finish();return
	var rt:RefCounted=mounted.runtime
	check("full machine accepts one real configured order",command(rt,"factory.configure",m.id,{"batches":3}).ok)
	var before:Dictionary=rt.capture_checkpoint();tick(rt,20)
	check("actual full-output tick stops before creating WIP or spending fuel",order(rt).state_code=="output_full" and machine_state(rt).batches.is_empty() and rt.stock(m.stock_refs.input).items.log==4 and rt.stock(m.stock_refs.fuel).items.log==1 and order(rt).energy_seconds==0 and outputs(rt,m)==64,order(rt))
	check("blocked machine still advances only the original runtime clock",is_equal_approx(rt.clock()-float(before.facts.time),2.0))
	check("real near-port take frees exactly one batch of room",command(rt,"take",m.stock_refs.output,{"items":{"timber":4}}).ok and outputs(rt,m)==60 and rt.actor("player").pack.timber==4)
	tick(rt,100)
	check("freeing output resumes original order and settles one batch once",order(rt).completed==1 and machine_state(rt).settlements.size()==1 and outputs(rt,m)==64 and rt.stock(m.stock_refs.input).items.log==3 and rt.stock(m.stock_refs.fuel).items.log==0 and is_equal_approx(order(rt).energy_seconds,10.0),order(rt))
	var energy:float=order(rt).energy_seconds;tick(rt,20)
	check("subsequent full output preserves remaining real energy and no second WIP",order(rt).state_code=="output_full" and machine_state(rt).batches.size()==1 and order(rt).energy_seconds==energy and rt.stock(m.stock_refs.input).items.log==3)
	check("second actual take frees same finite output",command(rt,"take",m.stock_refs.output,{"items":{"timber":8}}).ok and outputs(rt,m)==56)
	tick(rt,100)
	check("second batch consumes only existing stored energy",order(rt).completed==2 and machine_state(rt).settlements.size()==2 and outputs(rt,m)==60 and rt.stock(m.stock_refs.input).items.log==2 and rt.stock(m.stock_refs.fuel).items.log==0 and is_zero_approx(order(rt).energy_seconds))
	tick(rt,25)
	check("actual zero-fuel zero-stored-energy state cannot start next WIP",order(rt).state_code=="missing_energy" and machine_state(rt).batches.size()==2 and order(rt).completed==2 and rt.stock(m.stock_refs.input).items.log==2 and outputs(rt,m)==60 and order(rt).energy_seconds==0,order(rt))
	var frozen:Dictionary=rt.capture_checkpoint();var restored:=mount(frozen,"real fuel-starved checkpoint")
	if not restored.ok:finish();return
	rt=restored.runtime;tick(rt,10)
	check("cold restore cannot refill fuel energy or replay completed outputs",order(rt).state_code=="missing_energy" and outputs(rt,m)==60 and order(rt).completed==2 and machine_state(rt).settlements.size()==2 and rt.stock(m.stock_refs.fuel).items.log==0)
	mounted=relocate(rt,port(m,"fuel-input"),"fuel-port fixture preserves prior authoritative starvation")
	if not mounted.ok:finish();return
	rt=mounted.runtime
	check("actual deposit pays one original carried log into fuel",command(rt,"deposit",m.stock_refs.fuel,{"items":{"log":1}}).ok and rt.actor("player").pack.log==3 and rt.stock(m.stock_refs.fuel).items.log==1)
	tick(rt,100)
	check("refueling resumes same order without reconfigure and emits third batch only",order(rt).completed==3 and order(rt).remaining==0 and machine_state(rt).settlements.size()==3 and machine_state(rt).batches.size()==3 and outputs(rt,m)==64 and rt.stock(m.stock_refs.input).items.log==1 and rt.stock(m.stock_refs.fuel).items.log==0 and is_equal_approx(order(rt).energy_seconds,10.0),order(rt))
	tick(rt,20)
	check("target completion cannot consume extra stock energy or emit duplicates",outputs(rt,m)==64 and rt.stock(m.stock_refs.input).items.log==1 and machine_state(rt).settlements.size()==3 and is_equal_approx(order(rt).energy_seconds,10.0))
	check("autonomous machine never starts a player labor intent",rt.actor("player").intent==null and not rt._services.production.actor_work_projection("player").get("effective_work",false))
	evidence.append({"module_id":m.id,"state":machine_state(rt),"input":rt.stock(m.stock_refs.input).items,"output":rt.stock(m.stock_refs.output).items,"fuel":rt.stock(m.stock_refs.fuel).items,"player_pack":rt.actor("player").pack})
	finish()
