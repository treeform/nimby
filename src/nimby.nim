# Nimby helps manage a large collection of nimble packages in development.
import httpclient, jsony, os, osproc, parsecfg, parseopt, strutils, terminal,
    strutils, strformat

let author = "treeform"
let authorRealName = "Andre von Houck"
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
  web: string


let
  packageData = readFile(getHomeDir() / ".nimble/packages_official.json")
  packageList = fromJson(packageData, seq[Package])

#let packagesJson = parseJson readFile("/p/packages/packages.json")
proc findPackage(name: string): Package =
  for p in packageList:
    if p.name == name:
      return p

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


proc cloneAll() =
  for p in packageList:
    if p.url.contains "/" & author & "/":
      if dirExists(p.name):
        echo " * ", p.name
      else:
        echo " . ", p.name
        cmd "git clone " & p.url


const readmeSection = """

`nimble install $lib`

![Github Actions](https://github.com/$author/$lib/workflows/Github%20Actions/badge.svg)

[API reference](https://nimdocs.com/$author/$lib)

"""

proc readme() =
  ## Checks to see if readme is up to current standard

  if not validNimPackage():
    return

  var
    lib = getCurrentDir().splitPath.tail
    readmeSec = readmeSection.replace("$lib", lib).replace("$author", author)
    nimble = readFile(lib & ".nimble")
    license = readFile("LICENSE")

  echo "* ", lib

  var libs: seq[string]
  for line in nimble.split("\n"):
    if line.startsWith("requires"):
      let lib = line.replace("requires \"", "").split(" ")[0]
      if lib != "nim":
        libs.add(lib)
    if line.startsWith("author") and authorRealName notin line:
      echo "nimble: ", line
  for line in license.split("\n"):
    if line.startsWith("Copyright") and authorRealName notin line:
      echo "LICENSE: ", line

  if libs.len == 0:
    readmeSec.add "This library has no dependencies other than the Nim standard libarary.\n\n"

  readmeSec.add "## About\n"

  if readmeSec notin readFile("README.md"):
    echo "=".repeat(80)
    echo readmeSec
    echo "=".repeat(80)

proc fixremote() =
  var
    lib = getCurrentDir().splitPath.tail
    output = execProcess("git remote -v")

  if "https://" in output and author in output:
    cmd &"git remote remove origin"
    cmd &"git remote add origin git@github.com:{author}/{lib}.git"

proc pull() =
  cmd "git pull"

proc walkAll(operation: proc()) =
  for dirKind, dir in walkDir("."):
    if dirKind != pcDir:
      continue
    setCurrentDir(minDir / dir)
    operation()


    # if nimbleFile != "" and existsFile(nimbleFile):
    #   if pull:
    #     cmd "git pull"

    #   var author, version: string
    #   for line in readFile(nimbleFile).split("\n"):
    #     if "version" in line:
    #       version = line.split("=")[^1].strip()[1..^2]
    #     if "author" in line:
    #       author = line.split("=")[^1].strip()[1..^2]
    #   if showVersion:
    #     echo "   ", version
    #   if author != githubUser:
    #     continue

    #   let pkgName = nimbleFile[2..^8]
    #   if pkgName != dir[2..^1]:
    #     echo "!!! Nimble name does not match dir name: ",
    #         nimbleFile[2..^1], " != ", dir[2..^1]

    #   cmd "nimble check"

    #   if develop:
    #     if nimbleFile != "":
    #       cmd "nimble develop -y"

    #   let package = findPackage(pkgName)
    #   if package == nil:
    #     error "   NOT ON NIMBLE!!!"
    #   else:
    #     echo "   ", package.url
    #     let releaseUrl = package.url & "/releases/tag/v" & version
    #     let packageUser = package.url.split("/")[^2]
    #     try:
    #       var client = newHttpClient()
    #       let good = client.getContent(releaseUrl)
    #     except HttpRequestError:
    #       error "   NO RELEASE!!!"
    #       echo "   ", releaseUrl
    #       if packageUser != githubUser:
    #         echo "   ", "not your package, not your problem."
    #       else:

    #         if tag:
    #           echo "going to tag!"
    #           cmd "git tag v" & version
    #           cmd "git push origin --tags"

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
  of "clone": cloneAll()
  of "readme": walkAll(readme)
  of "fixremote": walkAll(fixremote)

  # of "develop":
  #   walkAll(develop)
  of "pull": walkAll(pull)
  # of "tag":
  #   walkAll(tag)
