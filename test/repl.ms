// Cases for the repl library on its own: the loop, the command table, and the text it hands
// back to the host. Nothing here knows what a fact is, which is the point - the only
// things in these sessions are lines and the functions they are given to.

run = function(library, h)
	"Checks the loop, the command dispatch, the handoff and the components, against scripted sessions."
	said = function(lines, text)
		"Whether a transcript holds this line exactly."
		return lines.indexOf(text) != null
	end function

	// A session over a script of typed lines, recording what it printed, asked, and what the
	// host's fallback was given. options say whether this session has commands of its own and
	// whether it paints at all; the library has to work with neither.
	scripted = function(module, script, options)
		seen = {"lines": [], "asked": [], "handled": [], "at": 0}
		reader = function(question)
			seen.asked.push(question)
			// Running out of script is what a reader returning null means.
			if seen.at >= script.len then return null
			seen.at = seen.at + 1
			return script[seen.at - 1]
		end function
		writer = function(line)
			seen.lines.push(line)
		end function
		// No `prompt` field: the library is run directly here, and nothing in it asks the session
		// which module it is.
		session = {"io": {"read": @reader, "say": @writer}}
		if options.hasIndex("commands") then
			// A command takes the session, its own record and the rest of the line, and
			// answers whether the session should end. Which command it is, it reads from
			// the record, so one function could serve several.
			// A declared command is given words and an undeclared one the rest of the line, so the
			// transcript says which shape arrived: [a|b] for words, the text itself otherwise.
			echo = function(given, command, argument)
				if argument isa list then
					seen.lines.push("  " + command.name + " [" + argument.join("|") + "]")
				else
					seen.lines.push("  " + command.name + " " + argument)
				end if
				return false
			end function
			stop = function(given, command, argument)
				return true
			end function
			// The other reading of /echo, for a registration that takes an existing name's place.
			shout = function(given, command, argument)
				seen.lines.push("  shout " + argument)
				return false
			end function
			// A note is the host's to add: /stop has none, and is listed by its name alone.
			session.commands = [
				{"name": "/echo", "note": "say the line back", "run": @echo},
				{"name": "/stop", "run": @stop}]
			// A command that adds one while the loop is running: registration is an ordinary
			// call on the session the command was handed, so the next line can name it.
			grow = function(given, command, argument)
				if options.hasIndex("replace") then
					module.addCommand(given, {"name": "/echo", "note": "the echo, replaced",
						"run": @shout})
				else
					module.addCommand(given, {"name": "/grown", "note": "added while running",
						"run": @echo})
				end if
				return false
			end function
			if options.hasIndex("grow") then
				session.commands.push({"name": "/grow", "note": "add a command while running",
					"run": @grow})
			end if
			// One required parameter and one optional, so /help has a declaration to render.
			if options.hasIndex("usage") then
				session.commands.push({"name": "/greet", "note": "greet someone",
					"parameters": [{"name": "who"}, {"name": "mood", "optional": 1}],
					"run": @echo})
			end if
		end if
		if options.hasIndex("paint") then
			session.paint = function(given, role, text)
				return role + ":" + text
			end function
		end if
		if options.hasIndex("components") then
			// Two described files: one written from what the session holds, and one that
			// holds nothing and so has nothing to save. Their lines are plain words, since
			// the library is meant not to know a format.
			session.things = ["alpha", "beta"]
			if not options.hasIndex("nopaths") then session.paths = {}
			if options.hasIndex("path") then session.paths["things"] = options.path
			session.pathFor = function(given, name)
				// The host's own rule, kept tiny: a name without a dot gets .kb.
				if file.name(name).indexOf(".") == null then return name + ".kb"
				return name
			end function
			lines = function(given)
				return given.things
			end function
			missing = function(given)
				// The other answer a write can give: text saying why there is nothing to save.
				return "no empties to save"
			end function
			blank = function(given)
				// And a list with no lines in it, which is a file rather than nothing to save.
				return []
			end function
			read = function(given, path)
				given.things = ["one", "two", "three"]
				return given.things
			end function
			session.components = [
				{"name": "things", "singular": "thing", "write": @lines, "read": @read},
				{"name": "empties", "singular": "empty", "possessive": "its",
					"write": @missing, "read": @read},
				{"name": "blanks", "singular": "blank", "write": @blank, "read": @read},
			]
		end if
		// The one thing the host must supply: what to do with a line that is not a command.
		if not options.hasIndex("nofallback") then
			session.fallback = function(given, line)
				seen.handled.push(line)
			end function
		end if
		if options.hasIndex("promptText") then session.promptText = options.promptText
		if options.hasIndex("exitWords") then session.exitWords = options.exitWords
		module.run(session)
		return seen
	end function

	// ── A line that is not a command ─────────────────────────────────────────

	plain = scripted(library, ["hello", "  spaced  ", "", "q"], {})
	h.check("a line that is not a command goes to the host's fallback",
		plain.handled == ["hello", "spaced"])
	h.check("the host is given the line trimmed, not as typed", plain.handled[1] == "spaced")
	h.check("a blank line is skipped rather than handed over",
		plain.handled.len == 2 and plain.asked.len == 4)
	h.check("the loop asks with the prompt it was given", plain.asked[0] == "? ")
	h.check("q leaves before the next line is read", plain.asked.len == 4)
	short = scripted(library, ["only"], {})
	h.check("a reader that runs out ends the session", short.handled == ["only"] and
		short.asked.len == 2)

	// ── The command table ────────────────────────────────────────────────────

	echoed = scripted(library, ["/echo hi there", "q"], {"commands": 1})
	h.check("a command is called with its own record and the rest of the line",
		echoed.lines == ["  /echo hi there"] and echoed.handled.len == 0)
	h.check("a command's name is matched whatever its case",
		scripted(library, ["/ECHO Hi", "q"], {"commands": 1}).lines == ["  /echo Hi"])
	stopped = scripted(library, ["/stop", "never"], {"commands": 1})
	h.check("a command that answers true ends the session", stopped.asked.len == 1 and
		stopped.handled.len == 0)
	helped = scripted(library, ["/help", "q"], {"commands": 1})
	h.check("/help lists the library's commands first",
		helped.lines[0] == "  /exit  leave the session" and
			helped.lines[1] == "  /help [NAME]  list these commands")
	h.check("/help lists the host's commands after them, in the table's order",
		helped.lines[2] == "  /echo  say the line back" and helped.lines[3] == "  /stop")
	h.check("/help says nothing else", helped.lines.len == 4)

	// A session that holds no commands is still a session: /exit and /help are the
	// library's, so a host with nothing of its own to answer need not build a table.
	alone = scripted(library, ["/help", "q"], {})
	h.check("a session with no commands still answers /help", alone.lines.len == 2 and
		alone.lines[0] == "  /exit  leave the session")
	unknown = scripted(library, ["/nope", "after"], {})
	h.check("an unknown command is refused", unknown.lines ==
		["  no such command: /nope (/help lists them)"])
	h.check("and the loop carries on with the next line", unknown.handled == ["after"])

	// ── One command's line, and a table that grows ──────────────────────────
	// /help with a name prints the line it would print in the whole list, and a session can add
	// to its table from inside a line it is already running.

	named = scripted(library, ["/help /echo", "/help echo", "/help /stop", "/help /nope", "q"],
		{"commands": 1})
	h.check("/help with a name prints that command's line",
		named.lines[0] == "  /echo  say the line back")
	h.check("the name may be typed without its slash",
		named.lines[1] == "  /echo  say the line back")
	h.check("a command with no note is its name alone", named.lines[2] == "  /stop")
	h.check("a name no command has is refused",
		named.lines[3] == "  no such command: /nope (/help lists them)")

	growing = scripted(library, ["/grow", "/grown now", "/help", "q"],
		{"commands": 1, "grow": 1})
	h.check("a command may add a command while the loop is running",
		growing.lines[0] == "  /grown now")
	h.check("and /help lists the one just added",
		said(growing.lines, "  /grown  added while running"))

	// A registration that names a command the table already answers replaces it where it sits
	// rather than adding a second one, so /help keeps its order and one name means one command.
	replacing = scripted(library, ["/grow", "/help", "/echo hi", "q"],
		{"commands": 1, "grow": 1, "replace": 1})
	h.check("a name the table already answers is replaced where it sits",
		replacing.lines.len == 6 and replacing.lines[2] == "  /echo  the echo, replaced")
	h.check("and the loop runs the command that replaced it", replacing.lines[5] == "  shout hi")

	// ── Parameters a command declares ──────────────────────────────────────
	// A declaration is what /help renders and what decides the shape of the argument: capitals
	// for the placeholder, brackets for the optional one, and words for the command. One that
	// declares nothing is handed the rest of the line as it was typed.

	declared = scripted(library, ["/help /greet", "/greet ann", "q"], {"commands": 1, "usage": 1})
	h.check("/help renders a declaration as the command's usage",
		declared.lines[0] == "  /greet WHO [MOOD]  greet someone")
	h.check("and the command is given the line as words, not as text",
		declared.lines[1] == "  /greet [ann]")

	// A quoted run is one word, because a file name with a space in it has to be one parameter.
	// Both quote marks work, since a reader will reach for either.
	spoken = scripted(library, ["/greet 'ann lee' happy",
		"/greet " + char(34) + "ann lee" + char(34) + " happy", "/greet", "/greet a b c", "q"],
		{"commands": 1, "usage": 1})
	h.check("a quoted run is one word", spoken.lines[0] == "  /greet [ann lee|happy]")
	h.check("and the other quote mark does the same", spoken.lines[1] == "  /greet [ann lee|happy]")
	h.check("a required word the line does not give is refused with the usage",
		spoken.lines[2] == "  usage: /greet WHO [MOOD]")
	h.check("and a line with more words than the declaration takes is refused too",
		spoken.lines[3] == "  usage: /greet WHO [MOOD]")

	// ── What a host may change, and what it must supply ──────────────────────
	// The loop asks for the pieces it needs before it reads a line, so a forgotten one is
	// a sentence rather than a failure on a line the host has never seen.

	askedText = scripted(library, ["/help", "q"], {"promptText": "notes> "})
	h.check("a host chooses the text its prompt shows", askedText.asked[0] == "notes> ")
	mine = scripted(library, ["q", "done"], {"exitWords": ["done"]})
	h.check("a host chooses the words that leave, so q is then just a line",
		mine.handled == ["q"] and mine.asked.len == 2)

	unheard = scripted(library, ["a line", "another"], {"nofallback": 1})
	h.check("a session with no fallback still starts, and the loop carries on",
		unheard.asked.len == 3 and unheard.handled.len == 0)
	h.check("and the library says it has nothing to do with the line",
		unheard.lines == ["  nothing to do with: a line", "  nothing to do with: another"])
	pathless = scripted(library, ["a line"], {"components": 1, "nopaths": 1})
	h.check("a session with components and no paths says which piece is missing",
		said(pathless.lines, "  the session cannot start without a paths map, which is where each component's file is kept"))

	// ── Painting, once the host says how ─────────────────────────────────────

	painted = scripted(library, ["/help", "/echo x", "q"], {"commands": 1, "paint": 1})
	h.check("the prompt is painted when the session paints", painted.asked[0] == "prompt:? ")
	h.check("and so is every line the library says", painted.lines[0] == "note:  /exit  leave the session" and
		painted.lines[4] == "  /echo x")

	// ── Components ───────────────────────────────────────────────────────────
	// A component is a description, and the library builds the commands from it: no name is
	// written anywhere else, and one save serves every component.

	temp = "."
	if env.hasIndex("TEMP") then temp = env["TEMP"]
	if env.hasIndex("TMP") then temp = env["TMP"]
	scratch = function(name)
		return file.child(temp, "micro-repl-" + name)
	end function
	quoted = function(path)
		"A path as a command line holds it: quoted, so a temp folder with a space in it is one word."
		return "'" + path + "'"
	end function

	thingsPath = scratch("things.kb")
	leftover = file.delete(thingsPath)
	saved = scripted(library, ["/save-things " + quoted(thingsPath), "q"], {"components": 1})
	back = file.readLines(thingsPath)
	leftover = file.delete(thingsPath)
	h.check("a save writes the lines the component gives", back == ["alpha", "beta"])
	h.check("a save says how many it wrote", said(saved.lines, "  wrote 2 things to " + thingsPath))

	// The name typed at the prompt is the host's to read, so .kb is added by its rule, not
	// the library's, and the path reported back is the one that was written.
	bare = scratch("bare")
	bareFile = bare + ".kb"
	leftover = file.delete(bareFile)
	namedSave = scripted(library, ["/save-things " + quoted(bare), "q"], {"components": 1})
	named = file.exists(bareFile)
	leftover = file.delete(bareFile)
	h.check("a bare name is left to the session's own path rule", named == 1)
	h.check("and the path it was written to is the one reported",
		said(namedSave.lines, "  wrote 2 things to " + bareFile))

	thingsPath = scratch("again.kb")
	leftover = file.delete(thingsPath)
	remembered = scripted(library, ["/save-things " + quoted(thingsPath), "/save-things", "q"],
		{"components": 1})
	leftover = file.delete(thingsPath)
	h.check("a save remembers its file, so a bare save goes there again",
		remembered.lines.len == 2 and remembered.lines[1] == "  wrote 2 things to " + thingsPath)

	// A file the session started with is a path it already holds, not a name typed at the
	// prompt: an extensionless one is written where it is, rather than gaining .kb and
	// landing beside itself. This session says nothing about finding a path either.
	extensionless = scratch("named-without-extension")
	leftover = file.delete(extensionless)
	leftover = file.delete(extensionless + ".kb")
	plainSave = scripted(library, ["/save-things", "q"], {"components": 1, "path": extensionless})
	inPlace = file.exists(extensionless)
	beside = file.exists(extensionless + ".kb")
	leftover = file.delete(extensionless)
	leftover = file.delete(extensionless + ".kb")
	h.check("a component's own file is used as it is, with no extension added",
		inPlace == 1 and beside == 0)
	h.check("and the save says it wrote there",
		said(plainSave.lines, "  wrote 2 things to " + extensionless))

	unnamed = scripted(library, ["/save-things", "q"], {"components": 1})
	h.check("a component with no file to fall back on says how to name one",
		said(unnamed.lines, "  no things file to use: name one, as /save-things FILE"))
	emptySave = scripted(library, ["/save-empties " + quoted(scratch("empties.kb")), "q"],
		{"components": 1})
	h.check("a component that says it has nothing to save says so in its own words",
		said(emptySave.lines, "  no empties to save"))

	// An empty list is not "nothing to save": it is a file with no lines in it, which is how a
	// session empties a file it no longer holds anything for.
	blankPath = scratch("blank.kb")
	leftover = file.delete(blankPath)
	blankSave = scripted(library, ["/save-blanks " + quoted(blankPath), "q"], {"components": 1})
	blankLines = file.readLines(blankPath)
	leftover = file.delete(blankPath)
	h.check("a component that answers no lines writes an empty file",
		blankLines.len == 0 and said(blankSave.lines, "  wrote 0 blanks to " + blankPath))

	thingsPath = scratch("load.kb")
	leftover = file.delete(thingsPath)
	loadedThing = scripted(library, ["/load-things " + quoted(thingsPath), "/save-things", "q"],
		{"components": 1})
	leftover = file.delete(thingsPath)
	h.check("a load hands the file to the component's read and says how many",
		said(loadedThing.lines, "  loaded 3 things from " + thingsPath))
	h.check("and what it loaded is what the next save writes",
		loadedThing.lines.len == 2 and
			loadedThing.lines[1] == "  wrote 3 things to " + thingsPath)

	// A save is about a file rather than an addition, and arrives in the role that says so:
	// the vocabulary is the library's, and the colors are the host's own.
	paintedPath = scratch("painted.kb")
	leftover = file.delete(paintedPath)
	paintedSave = scripted(library, ["/save-things " + quoted(paintedPath), "q"],
		{"components": 1, "paint": 1})
	leftover = file.delete(paintedPath)
	h.check("a save is painted as a file, not as an addition",
		said(paintedSave.lines, "file:  wrote 2 things to " + paintedPath))

	// ── A quoted path ───────────────────────────────────────────────────────
	// A path with a space in it is one parameter because it is quoted, which is what the words
	// a declared command is given have to hold together for. The library splits the line, so a
	// file lands where the path says rather than beside it.
	spacedPath = file.child(temp, "micro-repl spaced.kb")
	leftover = file.delete(spacedPath)
	spacedSave = scripted(library, ["/save-things " + quoted(spacedPath), "q"], {"components": 1})
	spacedLines = file.readLines(spacedPath)
	leftover = file.delete(spacedPath)
	h.check("a quoted path with a space in it is one parameter",
		spacedLines == ["alpha", "beta"] and
			said(spacedSave.lines, "  wrote 2 things to " + spacedPath))

	helpedComponents = scripted(library, ["/help", "q"], {"components": 1})
	h.check("/help lists a save and a load per component, after the host's own",
		said(helpedComponents.lines, "  /save-things [FILE]  write the things to their file, or to one named") and
			said(helpedComponents.lines, "  /save-empties [FILE]  write the empties to its file, or to one named") and
			said(helpedComponents.lines, "  /load-empties [FILE]  replace the empties with a file's"))

	// The whole block, to the character and in the order the table is assembled: this is the
	// transcript the module printed before the library moved out of the program, so it is what says
	// the move changed nothing a reader sees. Every line is either a note a host supplied or one the
	// library builds from a component's description, and the pin holds all ten of them.
	captured = scripted(library, ["/help", "q"], {"commands": 1, "components": 1})
	h.check("/help prints the whole block exactly as it always has", captured.lines == [
		"  /exit  leave the session",
		"  /help [NAME]  list these commands",
		"  /echo  say the line back",
		"  /stop",
		"  /save-things [FILE]  write the things to their file, or to one named",
		"  /load-things [FILE]  replace the things with a file's",
		"  /save-empties [FILE]  write the empties to its file, or to one named",
		"  /load-empties [FILE]  replace the empties with a file's",
		"  /save-blanks [FILE]  write the blanks to their file, or to one named",
		"  /load-blanks [FILE]  replace the blanks with a file's",
	])
end function
