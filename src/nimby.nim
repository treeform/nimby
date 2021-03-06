# Nimby helps manage a large collection of nimble packages in development.
import httpclient, json, os, osproc, parsecfg, parseopt, strutils, terminal

let githubUser = execProcess("git config --get user.email")
let minDir = getCurrentDir()

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
    * checks for .nimble
    * checks for git changes
    * checks for nimble status
    * checks for tag being installed on github
  nimby develop           - make sure all packages are linked with nimble
  nimby pull              - pull all updates to packages from with git
  nimby tag               - create a git tag for all pacakges if needed
"""

type Package = ref object
  name: string
  url: string
  `method`: string
  tags: seq[string]
  description: string
  license: string
  #web: string

#let packagesJson = parseJson readFile(getHomeDir() / ".nimble/packages_official.json")
let packagesJson = parseJson readFile("/p/packages/packages.json")
proc findPackage(name: string): Package =
  for p in packagesJson:
    if p["name"].getStr() == name:
      return p.to(Package)

var
  list = false
  develop = false
  tag = false
  pull = false
  showVersion = false

proc walkAll() =
  for dirKind, dir in walkDir("."):
    if dirKind != pcDir:
      continue
    echo "* ", dir[2..^1]
    setCurrentDir(minDir / dir)

    if dirExists(".git"):
      cmd "git status --short"

    var nimbleFile = ""
    for pc, file in walkDir("."):
      if pc == pcFile and file.endsWith(".nimble"):
        nimbleFile = file
        break

    if nimbleFile != "" and existsFile(nimbleFile):
      if pull:
        cmd "git pull"

      var author, version: string
      for line in readFile(nimbleFile).split("\n"):
        if "version" in line:
          version = line.split("=")[^1].strip()[1..^2]
        if "author" in line:
          author = line.split("=")[^1].strip()[1..^2]
      if showVersion:
        echo "   ", version
      if author != githubUser:
        continue

      let pkgName = nimbleFile[2..^8]
      if pkgName != dir[2..^1]:
        echo "!!! Nimble name does not match dir name: ",
            nimbleFile[2..^1], " != ", dir[2..^1]

      cmd "nimble check"

      if develop:
        if nimbleFile != "":
          cmd "nimble develop -y"

      let package = findPackage(pkgName)
      if package == nil:
        error "   NOT ON NIMBLE!!!"
      else:
        echo "   ", package.url
        let releaseUrl = package.url & "/releases/tag/v" & version
        let packageUser = package.url.split("/")[^2]
        try:
          var client = newHttpClient()
          let good = client.getContent(releaseUrl)
        except HttpRequestError:
          error "   NO RELEASE!!!"
          echo "   ", releaseUrl
          if packageUser != githubUser:
            echo "   ", "not your package, not your problem."
          else:

            if tag:
              echo "going to tag!"
              cmd "git tag v" & version
              cmd "git push origin --tags"

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
  of "":
    # No filename has been given, so we show the help:
    writeHelp()
  of "list":
    list = true
    walkAll()
  of "develop":
    develop = true
    walkAll()
  of "pull":
    pull = true
    walkAll()
  of "tag":
    tag = true
    walkAll()
