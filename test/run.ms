// The micro-repl test suite.
//
// Run: miniscript.exe test/run.ms
// Exit code 0 means every check passed.
//
// A test runner asks for part of the suite instead:
//
//   miniscript.exe test/run.ms --json --filter "a command is called with its own record" --file repl.ms
//
// --filter takes a substring of a check's name, --file the name of a case module, and
// --json adds the ##TEST/##END records a runner reads. See harness.ms.
//
// The library is imported once, here: a module that imports another gets its own copy of
// it, and the case module runs its sessions through this copy rather than importing one
// itself. The import binds the path it was given as the global name, so it is aliased
// below.

import "../repl"
import "harness"
import "repl"

// shellArgs[0] is this script, so the options start at index 1.
wanted = {"json": 0, "filters": [], "files": []}
at = 1
while at < shellArgs.len
	arg = shellArgs[at]
	if arg == "--filter" or arg == "--file" then
		if at + 1 >= shellArgs.len then
			print "error: " + arg + " needs a value"
			exit 1
		end if
		if arg == "--filter" then
			wanted.filters.push(shellArgs[at + 1])
		else
			wanted.files.push(shellArgs[at + 1])
		end if
		at = at + 2
	else if arg == "--json" then
		wanted.json = 1
		at = at + 1
	else
		print "error: unknown argument " + arg + " (--filter NAME, --file MODULE, --json)"
		exit 1
	end if
end while

harness.options.json = wanted.json
harness.options.filters = wanted.filters
harness.options.files = wanted.files

replSource = globals["../repl"]
replCases = globals["repl"]

// A partly loaded module would otherwise surface as a puzzling error inside one case, so
// check the surface the suite relies on up front. It is the same list the host in
// micro-expert pins, so a piece either program reaches for is checked in both places.
for name in ["run", "runCommand", "say", "ask", "trimSpace", "writeLines", "saveCommand",
	"loadCommand", "componentCommands"]
	if replSource.hasIndex(name) == 0 then
		print "error: ../repl loaded without " + name
		exit 1
	end if
end for

replCases.run(replSource, harness)

harness.summary()
