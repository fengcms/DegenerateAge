class_name FlatTileMesh
extends RefCounted
## Batch convex quads into one 2D draw surface, preserving insertion order.

var _vertices := PackedVector3Array()
var _indices := PackedInt32Array()
var _quads := 0

func _init(capacity: int = 0) -> void:
	_vertices.resize(capacity * 4)
	_indices.resize(capacity * 6)

func add_quad(points: PackedVector2Array) -> void:
	assert(points.size() == 4)
	var vertex := _quads * 4
	var index := _quads * 6
	if _vertices.size() < vertex + 4:
		_vertices.resize(vertex + 4)
		_indices.resize(index + 6)
	for i in range(4):
		_vertices[vertex + i] = Vector3(points[i].x, points[i].y, 0)
	_indices[index] = vertex
	_indices[index + 1] = vertex + 1
	_indices[index + 2] = vertex + 2
	_indices[index + 3] = vertex
	_indices[index + 4] = vertex + 2
	_indices[index + 5] = vertex + 3
	_quads += 1

func build() -> ArrayMesh:
	if _quads == 0:
		return null
	_vertices.resize(_quads * 4)
	_indices.resize(_quads * 6)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
