extends "res://tests/presentation/factory_repair_port_contact_suite.gd"
## Same finite real module/owner/rig fixture; physically walk from its declared
## port to B's actual closest supported craft hint before starting real work.
func run()->void:
	approach_from_real_hints=true
	super.run()
