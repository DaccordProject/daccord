class_name AccordError
extends RefCounted

## Represents an error returned by the Accord/Discord API. The code field
## contains the machine-readable error identifier, message is the
## human-readable description, and details holds any additional structured
## information the server provided.

var code: String = ""
var message: String = ""
var details: Dictionary = {}


static func from_dict(d: Dictionary) -> AccordError:
	var e := AccordError.new()
	e.code = str(d.get("code", ""))
	e.message = d.get("message", "")
	e.details = d.get("details", {})
	return e
