// repl.ms — the session at the prompt, and none of what a session is about.
//
// A prompt is a loop over one record: read a line, dispatch it when it names a command, and
// hand anything else back to whoever owns the text. A session made of data files can describe
// them too, and the prompt answers /save-<name> and /load-<name> for each, writing the file
// through a swap that keeps the old copy whole. Nothing here knows what a fact is.
//
//   import "repl/repl"
//   session = {"io": {"read": @readLine, "say": @printLine},
//       "fallback": @readOneLine,                  // may be left out: the library says it has none
//       "paint": @paintOneLine,                    // may be left out
//       "commands": [{"name": "/facts", "note": "list the facts", "run": @listFacts}],
//       "components": [{"name": "facts", "singular": "fact",
//           "write": @factsLines, "read": @factsRead}],    // may be left out
//       "paths": {"facts": "data/facts.kb"},       // where each component's file is
//       "pathFor": @pathOf,                        // a name typed at the prompt, as a path
//       "resolvePath": @findPath,                  // may be left out: for one that needs finding
//       "promptText": "notes> ",                   // may be left out: '? '
//       "exitWords": ["done"]}                    // may be left out: q and quit
//   repl.run(session)
//
// Everything the prompt calls is a pointer, never a name it would have to know: fallback takes
// the session and every line that is not a command, so parsing stays with the host; paint takes
// the session, a role and a piece of text; commands is the host's own table; and a component's
// write and read are what put its data in a file and take it back out. A session that gives no
// fallback still runs: the library answers those lines itself, saying it has nothing to do with
// one, so the piece can be left out rather than the session being refused for it.
//
// A command is a record of the name typed at the prompt, the note /help prints beside it, and
// run, the function the prompt calls with the session, the record itself, and whatever followed
// the name. The record comes along so one function can serve several commands - every save is
// the same function, reading the component off its own command. run answers whether the session
// should end, so /exit returns true and every other command returns false. A note is the host's
// to supply and is not required: a command without one is listed by its name alone.
//
// The table is assembled once, from the library's two, the host's own and one save and load per
// component, and addCommand grows it while the session runs: a command handed the session can
// register another, and the loop dispatches it from the next line on. A name the table already
// answers is not a second entry - the command given takes that one's place, so /help keeps its
// order and the last registration of a name is the one the loop runs. /help prints the table, or
// one command's line when it is named - /help /facts, or /help facts, since a name is typed with
// its slash at the prompt.
//
// A command may declare the parameters it takes, as {"name": "file", "optional": 1} records, and
// that one record does two things. /help renders it as usage - /save-facts [FILE], or
// /greet WHO [MOOD] - and the loop hands the command the line split into words. A name is written
// in capitals because that is how a placeholder reads, and an entry carrying optional is bracketed
// because it may be left out. A line with fewer words than the declaration requires, or more than
// it takes, is refused with the usage rather than run. A command that declares nothing is its name
// and nothing else, and it is handed the rest of the line as it stands: the declaration is what
// decides which of the two a command gets.
//
// The loop asks the session for the pieces it needs before it reads anything, so a host that
// has left one out is told which one in a sentence, rather than meeting a failure inside this
// module on a line it has never seen. promptText and exitWords are the two it may change: the
// text the prompt shows, and the words that leave besides /exit.
//
// session.ms imports this module rather than being handed it: nothing here holds a class, so the
// one-copy rule the solver needs does not apply, and the loop is the same loop whoever loaded it.
// A host of its own imports it the same way - examples/notes.ms does - and calls run(session).

// ── Talking to the reader ────────────────────────────────────────────────────
// The session holds how to read and how to write; this module decides only what to say, and
// asks paint to color it, so a prompt can be colored without the library knowing what a
// color is.

say = function(session, role, text)
	"Prints one line in a role's color through the session's output."
	session.io.say(paint(session, role, text))
end function

ask = function(session, question)
	"Shows a prompt and reads what is typed after it."
	return session.io.read(paint(session, "prompt", question))
end function

paint = function(session, role, text)
	"One piece of text in its role's color, or as it is when the session paints nothing."
	if not session.hasIndex("paint") then return text
	return session.paint(session, role, text)
end function

// What a painter is asked for, and all of it: a line from this module is doing one of four
// things, so there are four roles. A host may have more of its own - session.ms colors the facts
// and answers it says itself - but these are the ones that arrive from here, and a palette that
// does not know a role is expected to print it as it stands rather than take it for a fault.
//
//   prompt    the text the loop waits at, while a line is being typed
//   note      a line it lists: the commands /help prints
//   warning   what it could not do, or will not
//   file      a data file it wrote or read

// ── Commands ─────────────────────────────────────────────────────────────────
// A line that starts with / is aimed at the prompt rather than at the program. The table is
// what knows the commands: a name, the note /help prints, and the function to call. The
// library's own two come first and the host's after them, with one save and load per component
// last, so /help lists a session's commands without the loop knowing one of them.

leaveCommand = function(session, command, argument)
	"Says the session should end; the loop reads the answer."
	return true
end function

helpCommand = function(session, command, parameters)
	"Prints one command's line, or every command the session answers, in the order the table holds them."
	if parameters.len > 0 then
		// A name is typed with its slash at the prompt, so /help takes it with or without one.
		name = parameters[0].lower
		if name[0] != "/" then name = "/" + name
		named = commandNamed(session, name)
		if named == null then
			say(session, "warning", "  no such command: " + name + " (/help lists them)")
			return false
		end if
		say(session, "note", commandLine(named))
		return false
	end if
	for command in allCommands(session)
		// The note is the host's to add, so a command without one is its name and nothing else.
		say(session, "note", commandLine(command))
	end for
	return false
end function

ownCommands = [
	{"name": "/exit", "note": "leave the session", "run": @leaveCommand},
	{"name": "/help", "note": "list these commands",
		"parameters": [{"name": "name", "optional": 1}], "run": @helpCommand},
]

// The table is built once, because it can be added to while the loop is running: a session
// that registered a command from inside one line would lose it if every dispatch rebuilt the
// list from the seeds the host set before the loop started.

prepare = function(session)
	"Builds a session's command table from what it describes, or answers the one it already has."
	if session.hasIndex("table") then return session.table
	commands = ownCommands
	if session.hasIndex("commands") then commands = commands + session.commands
	session.table = commands + componentCommands(session)
	return session.table
end function

allCommands = function(session)
	"Every command a session answers: the library's two, the host's, then one save and load per component."
	return prepare(session)
end function

addCommand = function(session, command)
	"Adds one command to a session already running, so the next line can name it; a name the table already answers is replaced where it sits. Answers the table."
	table = prepare(session)
	for at in range(0, table.len - 1)
		if table[at].name == command.name then
			// In place, so nothing moves in /help and one name stays one command.
			table[at] = command
			return table
		end if
	end for
	table.push(command)
	return table
end function

commandNamed = function(session, name)
	"The command a session answers by this name, or null when it answers none."
	for command in allCommands(session)
		if command.name == name then return command
	end for
	return null
end function

usage = function(command)
	"The command's name with the parameters it declares, as /help prints it."
	line = command.name
	if not command.hasIndex("parameters") then return line
	for parameter in command.parameters
		shown = parameter.name.upper
		// An entry marked optional is the part a reader may leave out, so it is bracketed.
		if parameter.hasIndex("optional") then shown = "[" + shown + "]"
		line = line + " " + shown
	end for
	return line
end function

commandLine = function(command)
	"The line /help prints for one command: its usage, and its note when the host gave one."
	line = "  " + usage(command)
	if command.hasIndex("note") then line = line + "  " + command.note
	return line
end function

// The rest of the line is split only for a command that declared something. A word is what a space
// or a tab separates, and a run inside '...' or "..." is one word whatever it holds, which is how
// a path with a space in it is typed. A quote is not escaped, since this interpreter has no escape
// to write one with.

words = function(text)
	"Splits a line into words on spaces and tabs, keeping a quoted run together."
	pieces = []
	current = ""
	quote = ""
	at = 0
	while at < text.len
		c = text[at]
		if quote != "" then
			if c == quote then
				quote = ""
			else
				current = current + c
			end if
		else if isSpace(c) then
			if current != "" then
				pieces.push(current)
				current = ""
			end if
		else if c == "'" or c == char(34) then
			quote = c
		else
			current = current + c
		end if
		at = at + 1
	end while
	// An unterminated quote takes the rest of the line, so what it holds is still one word.
	if current != "" then pieces.push(current)
	return pieces
end function

fitsParameters = function(command, parsed)
	"Says whether the words given fit what a command declared: none missing that it requires, and none beyond what it takes."
	required = 0
	for parameter in command.parameters
		if not parameter.hasIndex("optional") then required = required + 1
	end for
	return parsed.len >= required and parsed.len <= command.parameters.len
end function

runCommand = function(session, line)
	"Runs the command this line names, answering whether the session should end."
	name = line.split(" ")[0].lower
	// The name is one word, so what follows it is the argument, trimmed, and may be empty.
	argument = trimSpace(line[name.len:])
	for command in allCommands(session)
		if command.name == name then
			// What follows the name reaches a command in one of two shapes: words for a command
			// that declared parameters, and the trimmed rest of the line for one that did not.
			given = argument
			if command.hasIndex("parameters") then
				given = words(argument)
				if not fitsParameters(command, given) then
					say(session, "warning", "  usage: " + usage(command))
					return false
				end if
			end if
			// A command answers whether the session should end, and only /exit says so.
			return command.run(session, command, given)
		end if
	end for
	say(session, "warning", "  no such command: " + name + " (/help lists them)")
	return false
end function

// ── Components ───────────────────────────────────────────────────────────────
// A session is often a few data files, and each is described the same way: what the commands
// call it, one of them for the messages, and the two functions that write it out and read it
// back. /save-facts, /load-facts, /save-rules and the rest come from that list, so a host
// describes its files and answers no command for them.
//
//   name        what the commands are called: /save-facts, /load-facts
//   singular    one of them, for the message: 54 facts, 1 fact
//   possessive  whose file it is, for the help: their, unless the entry says its
//   write       function(session) -> [line] to write, which may be empty - an empty list
//               empties the file - or a line of text saying why there is nothing to save
//   read        function(session, path) -> the collection the session now holds, whose len is
//               the count a load reports, or an error
//
// The two answers a save can get are kept apart: a list is written as it stands, so a session
// with nothing left to hold writes a file with no lines in it; text is the component saying
// there is nothing to save at all, in its own words, and is said as a warning. A component that
// checks nothing and a component with nothing in it are different things, and the shape of the
// answer is what tells them apart.
//
// Where each file is stays in the session's paths map, keyed by the component's name: a save or
// a load moves it, so a bare /save-facts writes where the last one went.
//
// Only a name typed at the prompt goes through pathFor, which is the host's rule and not the
// prompt's - that a bare name should end in .kb is knowledge-base business. The file the session
// started with is a path it already holds, so it is used as it is: extending it would move a
// domain's own facts file beside itself, from data/family to data/family.kb. A session whose
// paths are written relative to where its data lives adds resolvePath and each is found that
// way; one that says nothing about it has said its paths mean what they say.

componentsOf = function(session)
	"The components a session describes, or none when it has no files of its own."
	if not session.hasIndex("components") then return []
	return session.components
end function

componentCommands = function(session)
	"One save and one load per component, in the order the session lists them."
	commands = []
	for component in componentsOf(session)
		whose = "their"
		if component.hasIndex("possessive") then whose = component.possessive
		commands.push({"name": "/save-" + component.name,
			"note": "write the " + component.name + " to " + whose + " file, or to one named",
			"parameters": [{"name": "file", "optional": 1}],
			"component": component, "run": @saveCommand})
		commands.push({"name": "/load-" + component.name,
			"note": "replace the " + component.name + " with a file's",
			"parameters": [{"name": "file", "optional": 1}],
			"component": component, "run": @loadCommand})
	end for
	return commands
end function

saveCommand = function(session, command, parameters)
	"Writes the component this command names, keeping the file it replaces whole."
	component = command.component
	lines = component.write(session)
	// Text is the component saying it has nothing to save, and the words are its own.
	if lines isa string then
		say(session, "warning", "  " + lines)
		return false
	end if
	path = componentTarget(session, component, parameters, command.name)
	if path == null then return false
	problem = writeLines(path, lines)
	if problem isa error then
		say(session, "warning", "  could not write " + path + ": " + problem.message)
		return false
	end if
	session.paths[component.name] = path
	say(session, "file", "  wrote " + countText(lines.len, component.singular) + " to " + path)
	return false
end function

loadCommand = function(session, command, parameters)
	"Replaces the component this command names with the file it names, or with its own."
	component = command.component
	path = componentTarget(session, component, parameters, command.name)
	if path == null then return false
	loaded = component.read(session, path)
	if loaded isa error then
		say(session, "warning", "  could not read " + path + ": " + loaded.message)
		return false
	end if
	// The file that answered becomes the one a bare command uses next.
	session.paths[component.name] = path
	say(session, "file", "  loaded " + countText(loaded.len, component.singular) + " from " + path)
	return false
end function

componentTarget = function(session, component, parameters, command)
	"Where a save or load goes: the file the line named, or the one this component came from."
	// A name typed at the prompt is the host's to complete; the path the session started with
	// is not a name, and is used as it is unless the session says how to find one.
	if parameters.len > 0 then return session.pathFor(session, parameters[0])
	path = null
	if session.paths.hasIndex(component.name) then path = session.paths[component.name]
	if path == null or path == "" then
		say(session, "warning", "  no " + component.name + " file to use: name one, as " +
			command + " FILE")
		return null
	end if
	if session.hasIndex("resolvePath") then return session.resolvePath(session, path)
	return path
end function

// ── The loop ─────────────────────────────────────────────────────────────────
// One line has one meaning: a command if it starts with /, otherwise whatever the host's
// fallback makes of it. q and quit leave as /exit does, since a session is closed by the same
// keystrokes whatever program it belongs to - and a host with other words for it, or another
// prompt, says so on the session and the loop uses those instead.

promptTextOf = function(session)
	"The text the loop shows while it waits: the session's own, or '? '."
	if session.hasIndex("promptText") then return session.promptText
	return "? "
end function

exitWordsOf = function(session)
	"The words that leave besides /exit: the session's own, or q and quit."
	if session.hasIndex("exitWords") then return session.exitWords
	return ["q", "quit"]
end function

// A session that gives no fallback is not a broken one. The library answers a line it was given
// no use for with a warning of its own, so the loop carries on and the gap is visible rather
// than fatal; a host with its own reading of the text overrides it by naming a fallback.

defaultFallback = function(session, line)
	"Says the session has no use for a line it was given no fallback for."
	say(session, "warning", "  nothing to do with: " + line)
end function

// A session is a record the host fills in, so a piece left out would surface as a failure
// inside this module, on a line the host has never seen. The loop asks first, says what is
// missing one line at a time, and leaves the session unstarted. Only the pieces nothing here
// can stand in for are asked about: how to talk, and where a component's file is. A fallback
// is not one of them, since a session without one can still say what it makes of a line.

ioHas = function(session, name)
	"Says whether the session can read or say: its io record holds the function named."
	return session.hasIndex("io") and session.io.hasIndex(name)
end function

seamProblems = function(session)
	"What a session is missing before the loop can start, as the phrases that follow 'cannot start without'; empty when it has everything."
	problems = []
	if not ioHas(session, "say") then
		problems.push("something to say through (io.say)")
	end if
	if not ioHas(session, "read") then
		problems.push("something to read through (io.read)")
	end if
	if componentsOf(session).len > 0 then
		if not session.hasIndex("paths") then
			problems.push("a paths map, which is where each component's file is kept")
		end if
		if not session.hasIndex("pathFor") then
			problems.push("pathFor, which turns a name typed at the prompt into a path")
		end if
	end if
	return problems
end function

run = function(session)
	"Reads lines until the session ends: commands here, every other line to the session's fallback."
	problems = seamProblems(session)
	if problems.len > 0 then
		// One line through io when there is io to say it with, and print when there is
		// not: a session that cannot speak must still say why it is not starting.
		for problem in problems
			line = "  the session cannot start without " + problem
			if ioHas(session, "say") then
				session.io.say(line)
			else
				print line
			end if
		end for
		return
	end if
	// The table is built here, from the seeds the host had finished setting, and addCommand
	// grows it from there.
	prepare(session)
	while true
		line = ask(session, promptTextOf(session))
		if line == null then break
		line = trimSpace(line)
		if line == "" then continue
		if exitWordsOf(session).indexOf(line) != null then break
		if line[0] == "/" then
			if runCommand(session, line) then break
			continue
		end if
		// A function held in a map is invoked the moment it is read as a value in this
		// interpreter, so the session's own fallback is called by name here rather than
		// fetched into a variable first: fetching it would call it with no line at all.
		if session.hasIndex("fallback") then
			session.fallback(session, line)
		else
			defaultFallback(session, line)
		end if
	end while
end function

// ── Counting ─────────────────────────────────────────────────────────────────

countText = function(count, singular)
	"Says '1 rule' or '2 rules'."
	if count == 1 then return "1 " + singular
	return str(count) + " " + singular + "s"
end function

// ── Writing a data file ──────────────────────────────────────────────────────
// A save writes a temp file and swaps it in, so the file that is already there is only
// replaced once the new one is whole: a save that fails part way through leaves the
// session's facts.kb as it was rather than truncated to nothing. Only a file the save
// wrote itself is ever removed, and a swap that cannot put the old copy back says where
// it was left.

writeLines = function(path, lines)
	"Replaces the file at path with these lines, or returns an error."
	temp = path + ".tmp"
	problem = writeFresh(temp, lines)
	if problem != null then return problem
	problem = swapIn(temp, path)
	// A temp file is swept up only once the save has finished writing it, which is what
	// makes it this save's own to remove: what went wrong with the save is already the
	// answer, so the sweep's own failure has nowhere to go. Nothing else is ever cleared,
	// so a folder called facts.kb.tmp outlives a save that could not start.
	if problem != null then leftover = file.delete(temp)
	return problem
end function

writeFresh = function(path, lines)
	"Writes the lines to a new file at path, or returns an error, taking away the part-written file it made."
	handle = file.open(path, "w")
	if handle isa error then return handle
	for line in lines
		problem = handle.writeLine(line)
		if problem isa error then
			handle.close
			// The open worked, so the file at path is this write's own and a part-written
			// temp file must not be left to be taken for a whole one later. An open that
			// failed returns above, leaving whatever is at path alone.
			leftover = file.delete(path)
			return problem
		end if
	end for
	handle.close
	return null
end function

swapIn = function(temp, path)
	"Puts the finished temp file where the old file was, moving the old one aside until the new one is there."
	if not file.exists(path) then return moveFile(temp, path)
	// Windows will not move a file onto one that exists, so the old file is moved aside
	// first and put back if the new one cannot take its place: at no point is there no
	// copy of what the session started with.
	old = path + ".old"
	// A copy left by an interrupted swap is cleared so the old file can go there, but
	// only a file is one of ours: a folder named facts.kb.old is left where it is, and
	// the move below then fails with nothing lost.
	if file.exists(old) and file.info(old).isDirectory == 0 then leftover = file.delete(old)
	problem = file.move(path, old)
	if problem isa error then return problem
	problem = moveFile(temp, path)
	if problem == null then
		leftover = file.delete(old)
		return null
	end if
	// The old file goes back where it was, so the session still has what it started with.
	// If even that cannot be done, path is empty and the copy is at old, so the error says
	// where to find it rather than only why the move failed.
	restored = file.move(old, path)
	if restored isa error then return err(problem.message + "; the copy it replaced is at " + old)
	return problem
end function

moveFile = function(from, to)
	"Moves a file, answering an error or null, since file.move does not answer null on success."
	problem = file.move(from, to)
	if problem isa error then return problem
	return null
end function

// ── Helpers ──────────────────────────────────────────────────────────────────
// The loop trims what it reads, so it needs the same few lines triples.ms and knowledge.ms
// keep. It is written out here rather than handed in, so that this module stands alone - it
// is the piece meant to travel.

trimSpace = function(text)
	"Trims leading and trailing spaces and tabs."
	start = 0
	while start < text.len
		if not isSpace(text[start]) then break
		start = start + 1
	end while
	last = text.len - 1
	while last >= start
		if not isSpace(text[last]) then break
		last = last - 1
	end while
	return text[start:last + 1]
end function

isSpace = function(c)
	return c == " " or c == char(9)
end function
