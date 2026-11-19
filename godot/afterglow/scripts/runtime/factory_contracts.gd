extends RefCounted
## Shared protocol vocabulary, never a second simulation or production owner.
const VERSION := 1
const SCHEMA := "afterglow-factory-display-v1"
const SCENARIO := "factory-settlement-r34"
const ROUTES := {"module.":"modules", "factory.":"production", "logistics.":"production", "workforce.":"workforce", "settlement.":"workforce", "alerts.":"display", "handbook.":"display", "zone.":"zones", "zonework.":"zonework"}
const EXTENSION_OWNERS := {"r34:modules":"modules", "r34:production":"production", "r34:logistics":"production", "r34:workforce":"workforce", "r34:gameplay":"workforce", "r34:display":"display", "r34:zones":"zones", "r34:ecology":"ecology", "r34:zonework":"zonework"}
const STATE_PRIORITY := ["ruined", "invalid", "damaged", "paused", "maintenance", "region_paused", "unconfigured", "output_fault", "missing_input", "missing_energy", "missing_operator", "running", "target_met", "idle"]
const INTENT_OWNERS := ["runtime", "actions", "terrain", "gameplay", "residents", "modules", "production", "workforce", "zonework"]

static func service_for(kind:String)->String:
	for prefix:String in ROUTES:
		if kind.begins_with(prefix):return ROUTES[prefix]
	return ""

static func valid_command_kind(kind:String)->bool:
	for prefix:String in ROUTES:
		if kind.begins_with(prefix):return kind.length()>prefix.length()
	return true

static func empty_snapshot(world_id:String,world_revision:int,runtime_revision:int)->Dictionary:
	return {"schema":SCHEMA,"version":VERSION,"available":false,"world_id":world_id,"world_revision":world_revision,"runtime_revision":runtime_revision,
		"modules":{"available":false,"instances":[],"projects":[],"definitions":[]},
		"production":{"available":false,"orders":[],"batches":[]},
		"logistics":{"available":false,"tasks":[],"reservations":[]},
		"workforce":{"available":false,"assignments":[],"members":[]},
		"water":{"available":false,"sources":[],"projects":[]},
		"alerts":[],"definitions":{},"capabilities":{},"errors":[]}

static func primary_state(codes:Array,mode:String="")->String:
	# Owners supply the real current blockers. Never infer missing next-batch
	# material from a running batch, or require an operator for a machine.
	for code:String in STATE_PRIORITY:
		if code=="missing_operator" and mode=="machine":continue
		if codes.has(code):return code
	return "idle"
