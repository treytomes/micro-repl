# micro-repl

The prompt loop for MiniScript 2, and none of what a session is about. Read a line, dispatch it
when it names a command, hand anything else back to whoever owns the text. A session that keeps
its data in files describes them, and the prompt answers `/save-<name>` and `/load-<name>` for
each, writing through a temporary file and a swap, so a save that fails part way through cannot
truncate the copy that was already there.

One module, `repl.ms`, importing nothing: every piece it uses is the interpreter's own.

## Requirements

A MiniScript 2 interpreter. Command-line builds for Windows, macOS and Linux are on the
[MiniScript 2 releases page](https://github.com/JoeStrout/miniscript2/releases); the Windows
archive unpacks to a folder holding `miniscript.exe`.

## Setup

### As a submodule at `src/repl`

```
> git submodule add https://github.com/treytomes/micro-repl.git src/repl
```

`import` names the resulting map after the path it was given, so the import is `"repl/repl"`
and the caller aliases it back to a plain name:

```miniscript
import "repl/repl"

repl = globals["repl/repl"]
```

A module that imports this one reads it back out of `globals` the same way, because a
two-segment import inside a module binds no name.

### As a single file beside your script

Copy `repl.ms` next to your entry script and `import "repl"` works as it reads.

## Quick start

A session of notes: every line becomes one, `/count` is the host's own command, and the notes
are a component, which is what gives the session `/save-notes` and `/load-notes`.

```miniscript
import "repl"

repl = globals["repl"]

// What a line means, which is the host's business: a line that is not a command is a note.
noted = function(session, line)
	session.notes.push(line)
	repl.say(session, "added", "  noted: " + line)
end function

// The component: the notes as plain lines, read back as plain lines.
notesLines = function(session)
	return session.notes
end function

notesRead = function(session, path)
	session.notes = file.readLines(path)
	return session.notes
end function

// A name typed at the prompt is the host's to turn into a path: .txt for a bare name.
notesPath = function(session, name)
	if file.name(name).indexOf(".") == null then return name + ".txt"
	return name
end function

session = {"notes": ["a first note"], "paths": {}}
session.io = {
	"read": function(question)
		return input(question)
	end function,
	"say": function(line)
		print line
	end function,
}
session.fallback = @noted
session.components = [{"name": "notes", "singular": "note",
	"write": @notesLines, "read": @notesRead}]
session.pathFor = @notesPath

repl.run(session)
```

Console:

```
? hello
  noted: hello
? /help
  /exit  leave the session
  /help [NAME]  list these commands
  /save-notes [FILE]  write the notes to their file, or to one named
  /load-notes [FILE]  replace the notes with a file's
? /save-notes notes.txt
  wrote 2 notes to notes.txt
? /exit
```

The two commands of the library's own come first in `/help`, then the host's, then one save and
one load per component, in the order the table was assembled.

## The session record

A session is a map the host fills in. Two pieces are required — how to talk, and where a
component's file is — and the loop asks for them before it reads a line, naming whatever is
missing in a sentence rather than failing inside this module on a line the host has never seen.

| Key | Meaning |
| --- | --- |
| `io` | `read(question)` asks for a line and answers `null` to end the session; `say(line)` prints one. Required |
| `fallback` | `(session, line)` gets every line that is not a command. Left out, the library says it has nothing to do with the line and carries on |
| `paint` | `(session, role, text)` answers the text as it should be shown. Left out, text is shown as it is |
| `commands` | The host's own command records |
| `components` | One record per file the session keeps; `/save-<name>` and `/load-<name>` are built from these |
| `paths` | Where each component's file is, by name. Required once there is a component |
| `pathFor` | `(session, name)` turns a name typed at the prompt into a path. Left out, a typed name is used as it stands |
| `resolvePath` | `(session, path)` finds a file for a path the program was handed rather than one typed. Left out, nothing is looked for |
| `promptText` | The text the prompt shows; `"? "` by default |
| `exitWords` | Words that leave besides `/exit`; `q` and `quit` by default |

## Commands

| Command | What it does |
| --- | --- |
| `/exit` | Leaves the session |
| `/help` | Prints the whole table, one command per line |
| `/help NAME` | Prints that one command's line; the slash is optional |
| `/save-<name> [FILE]` | Writes a component, to its own file or to one named |
| `/load-<name> [FILE]` | Replaces a component with a file's lines |

A command is a record of `name`, `note`, `run` and, when it takes any, `parameters`. `note` is
what `/help` prints beside the name and is optional: a command without one is listed by its
name alone. `run` is called with the session, the command's own record and whatever followed
the name, and answers whether the session should end.

The table is assembled once and can grow while the loop runs: `addCommand(session, command)`
is an ordinary call a command can make on the session it was handed, and the next line can
use what it added. A name the table already answers is not a second entry — the command given
takes that one's place where it sits, so `/help` keeps its order and one name means one
command.

## Parameters

A command may declare `parameters` as `{"name": "file", "optional": 1}` records, and that one
declaration does two things:

- `/help` renders it as usage, a required name in capitals and an optional one bracketed:
  `/save-facts [FILE]`, `/greet WHO [MOOD]`.
- The loop hands the command the line split into words, with a quoted run kept as one word, so
  a path with a space in it is one parameter. A line with fewer words than the declaration
  requires, or more than it takes, is refused with the usage instead of being run.

A command that declares nothing is its name and nothing else, and is handed the rest of the
line as it was typed.

## Components

A component is a description, and the library writes no name twice: `{"name": "facts",
"singular": "fact", "write": @factsLines, "read": @factsRead}`, plus `possessive` for the
wording of a message (`its` by default).

- `write(session)` answers the lines to write, or a piece of text saying why there is nothing
  to save. An empty list is not that: it is a file with no lines in it, which is how a session
  empties one.
- `read(session, path)` answers the lines it read, or an error.

A save writes a temporary file and swaps it in, so the file already there is only replaced
once the new one is whole, and the old copy is put back if the swap fails. It remembers the
file it wrote, so a bare `/save-facts` goes there again; a component the session started with
a path for is written where it is, with no extension added, while a name typed at the prompt
goes through the host's own `pathFor`.

## Painting

`paint` is asked for four roles, and each is the host's to colour or ignore: `prompt` for the
text the loop asks with, `note` for what it says, `file` for what a save or a load reports,
and `warning` for a refusal or a failure. `say(session, role, text)` is the library's own way
in, so a host that paints gets every line painted once.

## Exports

| Name | What it is |
| --- | --- |
| `run(session)` | The loop, until `/exit`, an exit word, or a reader that answers `null` |
| `runCommand(session, line)` | One line, dispatched if it names a command |
| `say`, `ask`, `paint` | The three ways the library talks to a session |
| `addCommand(session, command)` | Adds a command, or replaces the one already answering that name |
| `countText(count, singular)` | `1 rule` or `2 rules`, for a message of the host's own |
| `writeLines(path, lines)` | Writes through a temporary file and a swap, as a save does |

## Tests

```
> miniscript.exe test/run.ms
52 passed, 0 failed
```

The checks cover the loop and its prompt, the command table and `/help` both whole and by
name, dispatch and an unknown command, a table that grows and one that replaces, declared
parameters and the usage a bad line is refused with, the pieces a host may leave out, painting,
and the components: what a save writes, the file it remembers, the path a session started with
against one typed at the prompt, an empty list against nothing to save, what a load hands back,
and a path with a space in it surviving as one parameter.

The saves write real files, so each case works under the system temp directory and clears its
`micro-repl-*` files away afterwards. `micro-expert` imports these same cases from its own
suite, so a change here is caught there too, run from `src/repl` by the same interpreter.

One caveat, because it changes how you read a failed run: in this interpreter an uncaught
runtime error still exits `0`, so the `N passed, M failed` line is the real signal. The
runner exits non-zero on a failure it catches.

## License

MIT — see [LICENSE](LICENSE). Copyright © 2026 Trey Tomes.
