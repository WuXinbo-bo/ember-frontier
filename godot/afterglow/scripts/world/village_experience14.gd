extends RefCounted
## Version14-only physical resource profiles, persisted with the tree entity.
## Older contracts never pass through this policy, including unexplored areas.
static func apply(draft:Dictionary,content_version:int=14)->Dictionary:
	if not draft.get("ok",false):return draft
	var trees:Array=[]
	for tree:Dictionary in draft.get("entities",{}).values():
		if tree.get("kind")=="tree":trees.append(tree)
	var home:bool=draft.get("region",{}).get("id")=="RH-HOME"
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		var da:float=Vector2(float(a.position.x)-22.0,float(a.position.z)-30.0).length_squared()
		var db:float=Vector2(float(b.position.x)-22.0,float(b.position.z)-30.0).length_squared()
		return str(a.id)<str(b.id) if is_equal_approx(da,db) else da<db)
	for index:int in trees.size():
		var tree:Dictionary=trees[index]
		var small:bool=home and index<4
		var height:float=float(tree.data.get("appearance",{}).get("height",4.0))
		var seconds:float=6.0 if small else 10.0 if height<=4.0 else 14.0
		tree.data.harvest={"phase":"standing","work":0.0,"seconds":seconds*0.5 if content_version in [16,17,18,19,20,21] else seconds,"toolWear":3.0 if small else 6.0,"yield":{"log":3},"profile":"half-duration-v16" if content_version in [16,17,18,19,20,21] else "village-experience-v14","size":"small" if small else "ordinary" if height<=4.0 else "large"}
		if small and tree.data.get("appearance") is Dictionary:
			tree.data.appearance.height=height*0.72
			tree.bounds.max.y=float(tree.position.y)+height*0.72
	return draft
