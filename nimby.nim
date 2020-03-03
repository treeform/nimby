# Nimby - helps manage large colletion of nimble packadges in development.
import parseopt, os, json, strformat, strutils, sequtils, httpclient, json, print, terminal


let githubUser = "treeform"
let minDir = getCurrentDir()

proc cmd(command: string) =
  discard execShellCmd command

proc error(msg: string) =
  styledWriteLine(stderr, fgRed, msg, resetStyle)

proc writeVersion() =
  ## Writes the version of the nimby tool
  echo "0.1.0"

proc writeHelp() =
  ## Write the help message for the nimby tool
  echo """
nimby - helps manage large collection of nimble packages in development.
  - list       list all packages currently in the folder
  - develop    make sure all packages are linked with nimble
  - pull       pull all updates to packages from with git
  - tag        make sure all packages have a proper tag
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

var list = false
var develop = false
var tag = false
var pull = false

proc walkAll() =
  for _, dir in walkDir("."):
    if not existsDir(dir):
      continue
    echo "* ", dir[2..^1]
    setCurrentDir(dir)
    cmd "git status --porcelain=v2"
    var nimbleFile = ""
    for pc, file in walkDir("."):
      if pc == pcFile and file.endsWith(".nimble"):
        nimbleFile = file
        break

    if nimbleFile != "":
      if pull:
        cmd "git pull"

      let pkgName = nimbleFile[2..^8]
      if pkgName != dir[2..^1]:
        echo "!!! Nimble name does not match dir name: ", nimbleFile[2..^1], " != ", dir[2..^1]

      cmd "nimble check"

      if develop:
        cmd "git status --porcelain=v2"
        var nimbleFile = ""
        for pc, file in walkDir("."):
          if pc == pcFile and file.endsWith(".nimble"):
            nimbleFile = file
            break

        if nimbleFile != "":
          cmd "nimble develop -y"

      var author, version: string
      for line in readFile(nimbleFile).split("\n"):
        if "version" in line:
          version = line.split("=")[^1].strip()[1..^2]
        if "author" in line:
          author = line.split("=")[^1].strip()[1..^2]
      echo "   ", version

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
          try:
            let releaseUrl = package.url & "/releases/tag/" & version
            var client = newHttpClient()
            let good = client.getContent(releaseUrl)
          except HttpRequestError:
            error "   NO RELEASE!!!"
            echo "   ", releaseUrl
            if packageUser != githubUser:
              echo "   ", "not your package, not your problem."
            else:

              if tag:
                print "going to tag!"
                cmd "git tag v" & version
                cmd "git push origin --tags"

    setCurrentDir(minDir)





var subcommand = ""
var url = ""
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
    # no filename has been given, so we show the help:
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
  else:
    echo "command ", subcommand, " not supported."