extends RefCounted
## Test-only, exact indexed observations approved by A; never used by authority.
const EVIDENCE="res://tests/world/fixtures/factory4-coordinate-roundtrip-observed.json"
static var _observed:Dictionary={}

static func differences(a:Variant,b:Variant,path:String="plan")->Array:
	var result:Array=[]
	if (a is int or a is float) and (b is int or b is float):
		if a!=b:
			var before_bits:PackedByteArray=PackedFloat64Array([float(a)]).to_byte_array()
			var after_bits:PackedByteArray=PackedFloat64Array([float(b)]).to_byte_array()
			result.append({"path":path,"before":a,"after":b,"before_type":typeof(a),"after_type":typeof(b),"before_bits_le":before_bits.hex_encode(),"after_bits_le":after_bits.hex_encode(),"abs":absf(float(a)-float(b)),"ulp":absi(before_bits.decode_s64(0)-after_bits.decode_s64(0)) if signf(float(a))==signf(float(b)) else 9223372036854775807,"vector2_components_exact":Vector2(float(a),0)==Vector2(float(b),0),"vector3_components_exact":Vector3(float(a),0,0)==Vector3(float(b),0,0)})
	elif a is Dictionary and b is Dictionary:
		for key:Variant in a:
			if not b.has(key):result.append({"path":path+"."+str(key),"reason":"missing restored key"});continue
			result.append_array(differences(a[key],b[key],path+"."+str(key)))
		for key:Variant in b:
			if not a.has(key):result.append({"path":path+"."+str(key),"reason":"unexpected restored key"})
	elif a is Array and b is Array:
		if a.size()!=b.size():result.append({"path":path,"reason":"array count changed","before_size":a.size(),"after_size":b.size()});return result
		for i:int in a.size():result.append_array(differences(a[i],b[i],path+"["+str(i)+"]"))
	elif a!=b:result.append({"path":path,"reason":"non-numeric difference","before":a,"after":b,"before_type":typeof(a),"after_type":typeof(b)})
	return result

static func key(seed:int,region:String,path:String)->String:return str(seed)+"|"+region+"|"+path

static func approved(seed:int,region:String,leaf:Dictionary)->bool:
	if _observed.is_empty():
		var input:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE))
		for row:Dictionary in input.rows:_observed[key(int(row.seed),row.region,row.path)]=row
	var row:Dictionary=_observed.get(key(seed,region,str(leaf.get("path",""))),{})
	return not row.is_empty() and not leaf.has("reason") and leaf.before_type==TYPE_FLOAT and leaf.after_type==TYPE_FLOAT and leaf.before_bits_le==row.before_bits_le and leaf.after_bits_le==row.after_bits_le and leaf.abs<1e-12 and leaf.ulp<=1 and leaf.vector2_components_exact and leaf.vector3_components_exact

static func compare(seed:int,region:String,before:Dictionary,after:Dictionary,root:String="plan")->Dictionary:
	var leaves:Array=differences(before,after,root)
	var rejected:Array=[]
	for leaf:Dictionary in leaves:
		if not approved(seed,region,leaf):rejected.append(leaf)
	return {"ok":rejected.is_empty(),"differences":leaves,"rejected":rejected}
