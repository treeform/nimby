import std/[osproc, strformat, strutils]

let lines = readFile("README.md").splitLines()
var i = 0

proc compareText(s: string): string =
  for line in s.replace("\r\n", "\n").splitLines():
    if line != "" and not line.startsWith("Nimby ") and not line.startsWith("Took: "):
      result.add line & "\n"

while i < lines.len:
  if lines[i] == "```sh skip":
    while i < lines.len and lines[i] != "```": inc i
    inc i
  elif lines[i] == "```sh":
    let line = i + 1
    var command = ""
    inc i
    while i < lines.len and lines[i] != "```":
      command.add lines[i] & "\n"
      inc i
    inc i

    var expected = ""
    while i < lines.len and lines[i] == "": inc i
    if i < lines.len and lines[i] == "```output":
      inc i
      while i < lines.len and lines[i] != "```":
        expected.add lines[i] & "\n"
        inc i
      inc i

    echo &"readme:{line}: > {command.strip()}"
    let (actual, code) = execCmdEx("sh", input = "set -e\n" & command)
    if actual != "":
      echo actual.indent(4)
    if code != 0:
      quit &"Command failed at line {line} with exit code {code}:\n{actual}"
    if actual.compareText() != expected.compareText():
      quit &"Output mismatch at line {line}\nExpected:\n{expected}\nActual:\n{actual}"
  else:
    inc i
