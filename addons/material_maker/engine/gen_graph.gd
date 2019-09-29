tool
extends MMGenBase
class_name MMGenGraph

var label : String = "Graph"
var connections = []

func get_type():
	return "graph"

func get_type_name():
	return label

func get_parameter_defs():
	if has_node("gen_parameters"):
		return get_node("gen_parameters").get_parameter_defs()
	return []

func set_parameter(p, v):
	if has_node("gen_parameters"):
		return get_node("gen_parameters").set_parameter(p, v)

func get_input_defs():
	if has_node("gen_inputs"):
		return get_node("gen_inputs").get_input_defs()
	return []

func get_output_defs():
	if has_node("gen_outputs"):
		return get_node("gen_outputs").get_output_defs()
	return []

func source_changed(input_index : int):
	if has_node("gen_inputs"):
		return get_node("gen_inputs").source_changed(input_index)

func get_port_source(gen_name: String, input_index: int) -> OutputPort:
	if gen_name == "gen_inputs":
		var parent = get_parent()
		if parent != null and parent.get_script() == get_script():
			return parent.get_port_source(name, input_index)
	else:
		for c in connections:
			if c.to == gen_name and c.to_port == input_index:
				var src_gen = get_node(c.from)
				if src_gen != null:
					if src_gen.get_script() == get_script():
						return src_gen.get_port_source("gen_outputs", c.from_port)
					return OutputPort.new(src_gen, c.from_port)
	return null

func get_port_targets(gen_name: String, output_index: int) -> InputPort:
	var rv = []
	for c in connections:
		if c.from == gen_name and c.from_port == output_index:
			var tgt_gen = get_node(c.to)
			if tgt_gen != null:
				rv.push_back(InputPort.new(tgt_gen, c.to_port))
	return rv

func add_generator(generator : MMGenBase):
	var name = generator.name
	var index = 1
	while has_node(name):
		index += 1
		name = generator.name + "_" + str(index)
	generator.name = name
	add_child(generator)

func remove_generator(generator : MMGenBase):
	var new_connections = []
	for c in connections:
		if c.from != generator.name and c.to != generator.name:
			new_connections.append(c)
	connections = new_connections
	generator.queue_free()
	
func replace_generator(old : MMGenBase, new : MMGenBase):
	new.name = old.name
	new.position = old.position
	remove_child(old)
	old.free()
	add_child(new)

func connect_children(from, from_port : int, to, to_port : int):
	# disconnect target
	while true:
		var remove = -1
		for i in connections.size():
			if connections[i].to == to.name and connections[i].to_port == to_port:
				remove = i
				break
		if remove == -1:
			break
		connections.remove(remove)
	# create new connection
	connections.append({from=from.name, from_port=from_port, to=to.name, to_port=to_port})
	return true

func disconnect_children(from, from_port : int, to, to_port : int):
	while true:
		var remove = -1
		for i in connections.size():
			if connections[i].from == from.name and connections[i].from_port == from_port and connections[i].to == to.name and connections[i].to_port == to_port:
				remove = i
				break
		if remove == -1:
			break
		connections.remove(remove)
	return true

func _get_shader_code(uv : String, output_index : int, context : MMGenContext):
	var outputs = get_node("gen_outputs")
	if outputs != null:
		var rv = outputs._get_shader_code(uv, output_index, context)
		while rv is GDScriptFunctionState:
			rv = yield(rv, "completed")
		return rv
	return { globals=[], defs="", code="", textures={} }

func _serialize(data):
	data.label = label
	data.nodes = []
	for c in get_children():
		data.nodes.append(c.serialize())
	data.connections = connections
	return data

func edit(node):
	node.get_parent().call_deferred("update_view", self)

func create_subgraph(generators):
	var new_graph = get_script().new()
	new_graph.name = "graph"
	add_child(new_graph)
	var names : Array = []
	for g in generators:
		names.push_back(g.name)
		remove_child(g)
		new_graph.add_generator(g)
	var new_graph_connections = []
	var my_new_connections = []
	var inputs = null
	var outputs = null
	for c in connections:
		if names.find(c.from) != -1 and names.find(c.to) != -1:
			new_graph_connections.push_back(c)
		elif names.find(c.from) != -1:
			if outputs == null:
				outputs = MMGenIOs.new()
				outputs.name = "gen_outputs"
				new_graph.add_generator(outputs)
			var port_index = outputs.ports.size()
			outputs.ports.push_back( { name="port"+str(port_index), type="rgba" } )
			my_new_connections.push_back( { from=new_graph.name, from_port=port_index, to=c.to, to_port=c.to_port } )
			new_graph_connections.push_back( { from=c.from, from_port=c.from_port, to="gen_outputs", to_port=port_index } )
		elif names.find(c.to) != -1:
			print("3: "+str(c))
		else:
			my_new_connections.push_back(c)
	connections = my_new_connections
	new_graph.connections = new_graph_connections
	for g in generators:
		if g is MMGenRemote:
			g.name = "gen_parameters"
			break
