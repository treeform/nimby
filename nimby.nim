import parseopt, os, json, strformat, strutils, sequtils


type
  RequiredLib = object
    ## A reqruied lib object
    name: string
    url: string
    version: string

  NimbyFile = object
    ## A niby file itself
    name: string
    version: string
    author: string
    url: string
    requires: seq[RequiredLib]

var
  currentDir = getCurrentDir() # which direcotry is the .nimby file is in


proc writeVersion() =
  ## Writes the version of the nimby tool
  echo "0.0.1"

proc writeHelp() =
  ## Write the help message for the nimby tool
  echo """
nimby is a tiny package manager for nim.

  nimby install              - installs all entries in .nimby file.
  nimby install gitUrl       - install package via git url.
  nimby remove packadgeName  - remove package via its name or git url.
  """


proc readNimbyFile(): NimbyFile =
  ## Finds and read the .nimby file
  ## Also sets the currentDir variable
  while not existsFile(currentDir / ".nimby"):
    if currentDir.isRootDir():
      break
    currentDir = currentDir.parentDir()
  if existsFile(currentDir / ".nimby"):
    var nimby = readFile(currentDir / ".nimby")
    return parseJson(nimby).to(NimbyFile)
  else:
    quit(".nimby file not found")


proc addCfgPath(path: string) =
  ## Add a path to the nim.cfg file.
  var nimCfg = ""
  if existsFile(currentDir / "nim.cfg"):
    nimCfg = readFile(currentDir / "nim.cfg")
  let
    unixPath = path.replace("\\", "/")
    pathLine = &"--path:\"{unixPath}\""
  for line in nimCfg.splitLines:
    if line == pathLine:
      return
  if not nimCfg.endsWith("\n"):
    nimCfg.add("\n")
  nimCfg.add(pathLine)
  nimCfg.add("\n")
  writeFile(currentDir / "nim.cfg", nimCfg)


proc removeCfgPath(path: string) =
  ## Removes a path from the nim.cfg file.
  var nimCfg = ""
  if existsFile(currentDir / "nim.cfg"):
    nimCfg = readFile(currentDir / "nim.cfg")
  else:
    return
  let
    unixPath = path.replace("\\", "/")
    pathLine = &"--path:\"{unixPath}\""
  writeFile(currentDir / "nim.cfg", nimCfg.replace(pathLine, ""))


proc gitSubmoduleText(name, url: string): string =
  return &"""[submodule "libs/{name}"]
    path = libs/{name}
    url = {url}

"""

proc addGitSubmodule(name, url: string) =
  ## Ads a library to the .gitmodules file (if it exists)
  let entry = gitSubmoduleText(name, url)

  if existsFile(currentDir / ".gitmodules"):
    var gitModules = readFile(currentDir / ".gitmodules")
    if entry notin gitModules:
      if not gitModules.endsWith("\n"):
        gitModules.add("\n")
      gitModules.add(entry)
      writeFile(currentDir / ".gitmodules", gitModules)


proc removeGitSubmodule(name, url: string) =
  ## Ads a library to the .gitmodules file (if it exists)
  let entry = gitSubmoduleText(name, url)
  if existsFile(currentDir / ".gitmodules"):
    var gitModules = readFile(currentDir / ".gitmodules")
    writeFile(currentDir / ".gitmodules", gitModules.replace(entry, ""))


proc installRequriement(name, url: string) =
  ## Install a spesific requirement
  if not existsDir(currentDir / "libs"):
    createDir(currentDir / "libs")
  var cmd = &"git clone {url} libs/{name}"
  if not existsDir(currentDir / "libs" / name):
    if execShellCmd(cmd) != 0:
      quit(&"Failed to clone {name} form {url}")
  if existsDir(currentDir / "libs" / name / "src"):
    addCfgPath("libs" / name / "src")
  else:
    addCfgPath("libs" / name)
  addGitSubmodule(name, url)


proc installRequriements(nimby: NimbyFile) =
  ## Install all requirements in the nimby file
  for lib in nimby.requires:
    installRequriement(lib.name, lib.url)


proc updateRequriement(name, url: string) =
  ## Install a spesific requirement
  if not existsDir(currentDir / "libs"):
    createDir(currentDir / "libs")
  if not existsDir(currentDir / "libs" / name):
    var cmd = &"git clone {url} libs/{name}"
    if execShellCmd(cmd) != 0:
      quit(&"Failed to clone {name} form {url}")
  else:
    var cmd = &"cd libs/{name}; git pull"
    if execShellCmd(cmd) != 0:
      quit(&"Failed to update {name} form {url}")
  if existsDir(currentDir / "libs" / name / "src"):
    addCfgPath("libs" / name / "src")
  else:
    addCfgPath("libs" / name)
  addGitSubmodule(name, url)


proc updateRequriements(nimby: NimbyFile) =
  ## Install all requirements in the nimby file
  for lib in nimby.requires:
    updateRequriement(lib.name, lib.url)


proc removeGitDir(path: string) =
  removeDir(path)


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
  of "update":
    var nimbyFile = readNimbyFile()
    var name = url
    if url != "":
      var found = false
      for lib in nimbyFile.requires:
        if lib.name == name:
          updateRequriement(lib.name, lib.url)
          found = true
      if not found:
        quit(&"Library with same name \"{name}\" not found")
    else:
      nimbyFile.updateRequriements()
      writeFile(currentDir / ".nimby", pretty %nimbyFile)

  of "install":
    var nimbyFile = readNimbyFile()

    if url != "":
      # add new requirement and install
      var lib = RequiredLib()
      lib.url = url
      var (_, name, _) = url.splitFile()
      lib.name = name
      for lib in nimbyFile.requires:
        if lib.name == name:
          if lib.url == url:
            quit(&"Library at {url} already installed.")
          else:
            quit(&"Library with same name \"{name}\" already exists with different ({url}) url.")

      nimbyFile.requires.add(lib)

    nimbyFile.installRequriements()
    writeFile(currentDir / ".nimby", pretty %nimbyFile)

  of "remove":
    var nimbyFile = readNimbyFile()

    if url == "":
      quit("Missing library argument to remove")

    var lib = RequiredLib()
    lib.url = url
    var (_, name, _) = url.splitFile()
    lib.name = name
    for i, lib in nimbyFile.requires:
        if lib.name == name:
          nimbyFile.requires.delete(i)
          removeCfgPath("libs" / lib.name)
          removeGitDir("libs" / lib.name)
          removeGitSubmodule(lib.name, lib.url)
          break

    writeFile(currentDir / ".nimby", pretty %nimbyFile)