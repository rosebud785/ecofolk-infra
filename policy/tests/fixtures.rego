# Fixture builder. Produces the exact shape `conftest test --parser hcl2 --combine` gives one .tf file:
# [{path, contents: {resource: {<type>: {<name>: [<body>]}}}}]. The path matters: it picks dev or prod
# limits and the local-only/ exemption.
package main

tf(path, rtype, body) := [{"path": path, "contents": {"resource": {rtype: {"fixture": [body]}}}}]

denied_with(msgs, fragment) if {
	some m in msgs
	contains(m, fragment)
}
