# Nimby helps manage a large collection of nimble packages in development.
import os, osproc, parsecfg, parseopt, strutils, terminal,
    strutils, strformat, puppy, tables, strformat

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
  discard execCmd command

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
  nimby fix-remote         - fix remote http links to git links.
  nimby fix-readme         - Make sure readme follows correct format.
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

const
  readmeSection = """

`nimble install $lib`

![Github Actions](https://github.com/$author/$lib/workflows/Github%20Actions/badge.svg)

[API reference](https://nimdocs.com/$author/$lib)

"""

  buildYaml = """
name: Github Actions
on: [push, pull_request]
jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest]

    runs-on: ${{ matrix.os }}

    steps:
    - uses: actions/checkout@v3
    - uses: jiro4989/setup-nim-action@v1
      with:
        repo-token: ${{ secrets.GITHUB_TOKEN }}
    - run: nimble test -y
    - run: nimble test --gc:orc -y
"""

  docsYaml = """
name: docs
on:
  push:
    branches:
      - master
env:
  nim-version: 'stable'
  nim-src: src/${{ github.event.repository.name }}.nim
  deploy-dir: .gh-pages
jobs:
  docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: jiro4989/setup-nim-action@v1
        with:
          nim-version: ${{ env.nim-version }}
      - run: nimble install -Y
      - run: nimble doc --index:on --project --git.url:https://github.com/${{ github.repository }} --git.commit:master  --out:${{ env.deploy-dir }} ${{ env.nim-src }}
      - name: "Copy to index.html"
        run: cp ${{ env.deploy-dir }}/${{ github.event.repository.name }}.html ${{ env.deploy-dir }}/index.html
      - name: Deploy documents
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ${{ env.deploy-dir }}
"""

proc libName(): string =
  let remoteOut = execProcess("git remote -v")
  result = getCurrentDir().splitPath.tail
  if "Not a git repository" notin remoteOut:
    let remoteArr = remoteOut.split()
    if remoteArr.len > 1:
      let remoteUrl = parseUrl(remoteArr[1])
      let remoteLibName = remoteUrl.paths[0].rmSuffix(".git")
      if result != remoteLibName:
        error &"path {result}/ does not match git name {remoteLibName}"

proc authorName(): string =
  let remoteArr = execProcess("git remote -v").split()
  if remoteArr.len > 1:
    let remoteUrl = parseUrl(remoteArr[1])
    result = remoteUrl.port

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

  let lib = libName()

  var
    author = authorName()
    authorReal = authorRealName()
  echo "* ", lib, " by ", author, " (" & authorReal & ")"

  if not fileExists("LICENSE"):
    error &"No {lib}/LICENSE file! "
    return

  if not fileExists(lib & ".nimble"):
    error &"No {lib}/{lib}.nimble file! "
    return

  var
    readmeSec = readmeSection.replace("$lib", lib).replace("$author", author)
    nimble = readFile(lib & ".nimble")
    license = readFile("LICENSE")

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
          arr = line.strip().split()
          libRequired = arr[1][1..^1]
          versionRequired = arr[3][0..^2]
          versionInstalled = mostRecentVersion(libRequired)
        if libRequired != "nim" and versionInstalled != "" and versionRequired != versionInstalled:
          error &"nimble update dep: {libRequired} {versionRequired} -> {versionInstalled}"

  for line in license.split("\n"):
    if line.startsWith("Copyright") and authorRealName() notin line:
      error "update to? " & authorRealName()
      error "LICENSE: " & line

  if libs.len == 0:
    readmeSec.add "This library has no dependencies other than the Nim standard library.\n\n"

  let readme = readFile("README.md")
  if "nimble install" in readme and readmeSec notin readme:
    error readmeSec

  if dirExists(".github/workflows"):
    # make sure build.yml and docs.yml same
    if not fileExists(".github/workflows/build.yml"):
      error "missing .github/workflows/build.yml"
    elif readFile(".github/workflows/build.yml") != buildYaml:
      error "different .github/workflows/build.yml"

    if not fileExists(".github/workflows/docs.yml"):
      error "missing .github/workflows/docs.yml"
    elif readFile(".github/workflows/docs.yml") != docsYaml:
      error "different .github/workflows/docs.yml"

proc fixRemote() =
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

proc fixCi() =
  if dirExists(".github/workflows"):
    # make sure build.yml is correct
    if not fileExists(".github/workflows/build.yml"):
      error "missing .github/workflows/build.yml"
      writeFile(".github/workflows/build.yml", buildYaml)
    elif readFile(".github/workflows/build.yml") != buildYaml:
      error "different .github/workflows/build.yml"
      writeFile(".github/workflows/build.yml", buildYaml)

proc fixDocs() =
  if dirExists(".github/workflows"):
    # Add github actions doc builder.
    cmd &"git add -f .github/workflows/docs.yml"
    # make sure docs.yml is correct
    if not fileExists(".github/workflows/docs.yml"):
      error "missing .github/workflows/docs.yml"
      writeFile(".github/workflows/docs.yml", docsYaml)
    elif readFile(".github/workflows/docs.yml") != docsYaml:
      error "different .github/workflows/docs.yml"
      writeFile(".github/workflows/docs.yml", docsYaml)

proc pull() =
  cmd "git pull"

proc develop() =
  cmd "nimble develop -y"

proc test() =
  cmd "nimble test"

proc actionBoard() =
  if not validNimPackage():
    return

  let lib = libName()

  var
    author = authorName()
    authorReal = authorRealName()

  echo "* ", lib, " by ", author, " (" & authorReal & ")"
  echo "![Github Actions](https://github.com/" & author & "/" & lib & "/workflows/Github%20Actions/badge.svg"


proc walkAll(operation: proc()) =
  for dirKind, dir in walkDir("."):
    if dirKind != pcDir:
      continue
    setCurrentDir(minDir / dir)
    #echo "------ ", minDir / dir, " ------"
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
  of "fix-remote": walkAll(fixRemote)
  of "fix-ci": walkAll(fixCi)
  of "fix-docs": walkAll(fixDocs)
  of "develop": walkAll(develop)
  of "pull": walkAll(pull)
  of "test": walkAll(test)
  of "action-board": walkAll(actionBoard)
  else:
    echo "invalid command"
