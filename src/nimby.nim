# Nimby helps manage a large collection of nimble packages in development.
import os, osproc, parsecfg, parseopt, strutils, terminal,
    strutils, strformat, urlly, puppy, tables

let minDir = getCurrentDir()

proc cutBetween(str, a, b: string): string =
  let
    cutA = str.find(a)
  if cutA == -1:
    return ""
  let
    cutB = str.find(b, cutA)
  if cutB == -1:
    return ""
  return str[cutA + a.len..<cutB]

proc rmSuffix(s, suffix: string): string =
  if s.endsWith(suffix):
    return s[0 .. s.len - suffix.len - 1]
  return s

proc cmd(command: string) =
  discard execShellCmd command

proc error(msg: string) =
  styledWriteLine(stderr, fgRed, msg, resetStyle)

proc writeVersion() =
  ## Writes the version of the nimby tool.
  echo loadConfig("./nimby.nimble").getSectionValue("", "version")

proc writeHelp() =
  ## Write the help message for the nimby tool.
  echo """
nimby - manage a large collection of nimble packages in development
  nimby list              - lists all nim packages in the current directory
  nimby develop           - make sure all packages are linked with nimble
  nimby pull              - pull all updates to packages from with git
  nimby test              - run tests on all of the packages
  nimby fixremote         - fix remote http links to git links.
  nimby fixreadme         - Make sure readme follows correct format.
"""

proc validNimPackage(): bool =
  # list nimble status
  let lib = getCurrentDir().splitPath.tail
  existsFile(lib & ".nimble")

proc list() =
  ## Lists current info about package
  # list git status
  let lib = getCurrentDir().splitPath.tail
  echo "* ", lib

  if dirExists(".git"):
    cmd "git status --short"

proc urls() =
  ## Lists current info about package
  # list git status
  let lib = getCurrentDir().splitPath.tail
  echo " https://github.com/treeform/", lib

proc commit() =
  ## Lists current info about package

  if not validNimPackage():
    return

  let lib = getCurrentDir().splitPath.tail
  echo "* ", lib

  cmd "git commit -am 'Update readme.'"
  cmd "git push --set-upstream origin master"

const readmeSection = """

`nimble install $lib`

![Github Actions](https://github.com/$author/$lib/workflows/Github%20Actions/badge.svg)

[API reference](https://nimdocs.com/$author/$lib)

"""

proc libName(): string =
  let remoteArr = execProcess("git remote -v").split()
  if remoteArr.len > 1:
    let remoteUrl = parseUrl(remoteArr[1])
    return remoteUrl.paths[0].rmSuffix(".git")
  return getCurrentDir().splitPath.tail

proc authorName(): string =
  let remoteArr = execProcess("git remote -v").split()
  if remoteArr.len > 1:
    let remoteUrl = parseUrl(remoteArr[1])
    return remoteUrl.port

var authorRealNameCache: Table[string, string]
proc authorRealName(): string =
  let name = authorName()
  if name notin authorRealNameCache:
    let
      githubUrl = "https://github.com/" & name
      res = fetch(githubUrl)
      realName = res.cutBetween("itemprop=\"name\">", "</span>").strip()
    authorRealNameCache[name] = realName
  return authorRealNameCache[name]

proc mostRecentVersion(libName: string): string =
  let nimblePath = &"../{libName}/{libName}.nimble"
  if fileExists(nimblePath):
    for line in readFile(nimblePath).split("\n"):
      if line.startsWith("version"):
        return line.splitWhitespace()[^1][1..^2]

proc check() =
  ## Checks to see if readme/licnese/nimble are up to current standard

  if not validNimPackage():
    return

  var
    lib = libName()
    author = authorName()
    authorReal = authorRealName()
    readmeSec = readmeSection.replace("$lib", lib).replace("$author", author)
    nimble = readFile(lib & ".nimble")
    license = readFile("LICENSE")

  echo "* ", lib, " by ", author, " (" & authorReal & ")"

  var libs: seq[string]
  for line in nimble.split("\n"):
    if line.startsWith("requires"):
      let lib = line.replace("requires \"", "").split(" ")[0]
      if lib != "nim":
        libs.add(lib)
    if line.startsWith("author") and authorRealName() notin line:
      error "nimble: " & line
    if "requires" in line:
      if ">=" notin line:
        error "nimble: " & line
      else:
        let
          arr = line.split()
          libRequired = arr[1][1..^1]
          versionRequired = arr[3][0..^2]
          versionInstalled = mostRecentVersion(libRequired)
        if versionInstalled != "" and versionRequired != versionInstalled:
          error &"nimble update dep: {libRequired} {versionRequired} -> {versionInstalled}"


  for line in license.split("\n"):
    if line.startsWith("Copyright") and authorRealName() notin line:
      error "update to? " & authorRealName()
      error "LICENSE: " & line

  if libs.len == 0:
    readmeSec.add "This library has no dependencies other than the Nim standard library.\n\n"

  if readmeSec notin readFile("README.md"):
    error readmeSec

proc fixremote() =
  var
    remoteArr = execProcess("git remote -v").split()
  if remoteArr.len > 1:
    let remoteUrl = remoteArr[1]
    if "https://github.com/" in remoteUrl:
      let gitUrl = remoteUrl.replace("https://github.com/", "git@github.com:")
      echo remoteUrl, " -> ", gitUrl
      cmd &"git remote remove origin"
      cmd &"git remote add origin {gitUrl}"
      cmd &"git pull origin master"

proc pull() =
  cmd "git pull"

proc develop() =
  cmd "nimble develop -y"

proc test() =
  cmd "nimble test"

proc walkAll(operation: proc()) =
  for dirKind, dir in walkDir("."):
    if dirKind != pcDir:
      continue
    setCurrentDir(minDir / dir)
    operation()
    setCurrentDir(minDir)

var subcommand, url: string
var p = initOptParser()
for kind, key, val in p.getopt():
  case kind
  of cmdArgument:
    if subcommand == "":
      subcommand = key
    else:
      url = key
  of cmdLongOption, cmdShortOption:
    case key
    of "help", "h": writeHelp()
    of "version", "v": writeVersion()
  of cmdEnd: assert(false) # cannot happen

case subcommand
  of "": writeHelp()
  of "list": walkAll(list)
  of "urls": walkAll(urls)
  of "commit": walkAll(commit)
  of "check": walkAll(check)
  of "fixremote": walkAll(fixremote)
  of "develop": walkAll(develop)
  of "pull": walkAll(pull)
  of "test": walkAll(test)
  else:
    echo "invalid command"
