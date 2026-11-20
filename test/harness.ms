// Test harness: counts checks and decides the exit status.
//
// A check prints a line for a person and, with --json, a line for a test runner:
//
//   PASS  a command is called with its own record and the rest of the line
//   ##TEST {"name":"a command is called with its own record and the rest of the line","status":"pass","file":"repl.ms","line":12}
//
// and the run closes with its totals:
//
//   ##END {"passed":52,"failed":0,"skipped":0}
//
// ##END arriving is the signal that the suite reached the end. An uncaught runtime
// error stops the program and still exits 0, so a runner cannot go by the exit code.
//
// options.filters and options.files narrow what runs, so a runner can ask for part of
// the suite: a check runs when its name holds any filter given and it sits in any file
// given. A check that is filtered out is counted as skipped and prints nothing.

import "json"

tally = {"passed": 0, "failed": 0, "skipped": 0}
options = {"json": 0, "filters": [], "files": []}

// The case module named by one stackTrace frame, and the line in it.
caller = function(frame)
	if frame == null then return {"file": "", "line": 0}
	at = frame.indexOf(" line ")
	if at == null then return {"file": frame, "line": 0}
	return {"file": frame[:at], "line": val(frame[at + 6:])}
end function

// Whether a value holds any of the wanted substrings; an empty list wants everything.
matches = function(wanted, value)
	if wanted.len == 0 then return true
	for item in wanted
		if value.indexOf(item) != null then return true
	end for
	return false
end function

selected = function(name, file)
	return matches(options.filters, name) and matches(options.files, file)
end function

record = function(name, status, where)
	if options.json == 0 then return
	entry = {"name": name, "status": status, "file": where.file, "line": where.line}
	print "##TEST " + json.toJSON(entry, true)
end function

check = function(name, ok)
	"Records one expectation, printing it so a failure names itself."
	// stackTrace[0] is this check, so the case module that called it is one step up.
	where = caller(stackTrace[1])
	if not selected(name, where.file) then
		tally.skipped = tally.skipped + 1
		return
	end if
	if ok then
		tally.passed = tally.passed + 1
		print "PASS  " + name
		record(name, "pass", where)
	else
		tally.failed = tally.failed + 1
		print "FAIL  " + name
		record(name, "fail", where)
	end if
end function

summary = function()
	"Prints the totals and exits non-zero when anything failed."
	print ""
	line = tally.passed + " passed, " + tally.failed + " failed"
	if tally.skipped > 0 then line = line + ", " + tally.skipped + " skipped"
	print line
	if options.json != 0 then
		totals = {"passed": tally.passed, "failed": tally.failed, "skipped": tally.skipped}
		print "##END " + json.toJSON(totals, true)
	end if
	if tally.failed > 0 then exit 1
	exit 0
end function
