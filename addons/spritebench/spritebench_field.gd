@tool
class_name SpriteBenchField
extends Resource

## One named art slot every record in a collection has, like `front` or `roof`.

@export var key: StringName = &""
## An ordered list of images instead of one.
@export var as_array: bool = false
