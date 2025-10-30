import std/[os, json, times, osproc, parseopt, strutils, strformat, streams, locks]

const
  WorkerCount = 10

var
  verbose: bool = false
  workspaceRoot: string
  timeStarted: float64

  jobLock: Lock
  jobQueue: array[100, string]
  jobQueueStart: int = 0
  jobQueueEnd: int = 0
  jobsInProgress: int

type
  NimbleFile* = object
    version*: string
    srcDir*: string
    deps*: seq[(string, string, string)]

proc parseNimbleFile*(fileName: string): NimbleFile =
  ## Parse the nimble file and return a NimbleFile object.
  let nimble = readFile(fileName)
  for line in nimble.splitLines():
    if line.startsWith("version"):
      result.version = line.split(" ")[^1].strip().replace("\"", "")
    elif line.startsWith("srcDir"):
      result.srcDir = line.split(" ")[^1].strip().replace("\"", "")
    elif line.startsWith("requires"):
      var i = 9
      var dep, op, version = ""
      while i < line.len and line[i] in [' ', '"']:
        inc i
      while i < line.len and line[i] notin ['=', '<', '>', '~', '^', ' ']:
        dep.add(line[i])
        inc i
      while i < line.len and line[i] in [' ']:
        inc i
      while i < line.len and line[i] in ['=', '<', '>', '~', '^']:
        op.add(line[i])
        inc i
      while i < line.len and line[i] in [' ']:
        inc i
      while i < line.len and line[i] notin ['"']:
        version.add(line[i])
        inc i
      result.deps.add((dep, op, version.strip()))
  return result

initLock(jobLock)

proc info(message: string) =
  ## Print information message if verbose is true.
  if verbose:
    echo message

proc cmd(command: string) =
  ## Run the command and print the output if it fails.
  let exeName = command.split(" ")[0]
  let args = command.split(" ")[1..^1]
  let p = startProcess(exeName, args=args, options={poUsePath})
  if p.waitForExit(-1) != 0:
    echo "> ", command
    echo p.peekableOutputStream().readAll()
    echo p.peekableErrorStream().readAll()
    quit("error code: " & $p.peekExitCode())
  p.close()

template withLock(lock: Lock, body: untyped) =
  acquire(lock)
  {.gcsafe.}:
    try:
      body
    finally:
      release(lock)

proc writeVersion() =
  ## Write the version of Nimby.
  echo "Nimby 0.1.0"

proc writeHelp() =
  ## Write the help message.
  echo "Usage: nimby <subcommand> [options]"
  echo "  ~ Minimal package manager for Nim. ~"
  echo "Subcommands:"
  echo "  install    install all Nim packages in the current directory"
  echo "  update     update all Nim packages in the current directory"
  echo "  uninstall  uninstall all Nim packages in the current directory"
  echo "  list       list all Nim packages in the current directory"
  echo "  tree       list all packages as a dependency tree"
  echo "  doctor     fix any linking issues with the packages"
  echo "  help       show this help message"

proc cutBetween(str, a, b: string): string =
  ## Cut a string by two substrings.
  let
    cutA = str.find(a)
  if cutA == -1:
    return ""
  let
    cutB = str.find(b, cutA)
  if cutB == -1:
    return ""
  return str[cutA + a.len..<cutB]

proc timeStart() =
  ## Start the timer.
  timeStarted = epochTime()

proc timeEnd() =
  ## Stop the timer and print the time taken.
  let timeEnded = epochTime()
  echo "Took: ", timeEnded - timeStarted, " seconds"

proc findWorkspaceRoot(): string =
  ## Finds the topmost nim.cfg file and returns the workspace root.
  ## If no nim.cfg file is found, returns the current directory.
  result = getCurrentDir()
  var currentDir = result
  # Find topmost nim.cfg file.
  while currentDir != "/" and currentDir != "":
    if fileExists(currentDir & "/nim.cfg"):
      result = currentDir
    currentDir = currentDir.parentDir

proc fetchPackage(argument: string, indent: string) {.gcsafe.}

proc enqueuePackage(packageName: string) =
  ## Add a package to the job queue.
  withLock(jobLock):
    jobQueue[jobQueueEnd] = packageName
    inc jobQueueEnd

proc popPackage(): string =
  ## Pop a package from the job queue or return empty string.
  withLock(jobLock):
    if jobQueueEnd > jobQueueStart:
      result = jobQueue[jobQueueStart]
      inc jobQueueStart
      inc jobsInProgress

proc readPackageSrcDir(packageName: string): string =
  ## Read the source directory of a package.
  if not fileExists(&"{packageName}/{packageName}.nimble"):
    return ""
  return parseNimbleFile(&"{packageName}/{packageName}.nimble").srcDir

proc readPackageDeps(packageName: string): seq[string] =
  ## Read the dependencies of a package.
  if not fileExists(&"{packageName}/{packageName}.nimble"):
    return @[]
  for dep in parseNimbleFile(&"{packageName}/{packageName}.nimble").deps:
    if dep[0] == "nim":
      continue
    result.add(dep[0])

proc readGitHash(packageName: string): string =
  ## Read the git hash of a package.
  let p = execCmdEx(&"git -C {packageName} rev-parse HEAD")
  if p.exitCode != 0:
    return ""
  return p.output.strip()

proc fetchDeps(packageName: string, indent: string) =
  let deps = readPackageDeps(packageName)
  for dep in deps:
    info &"Dependency: {dep}"
    enqueuePackage(dep)

proc worker(id: int) {.thread.} =
  ## Worker thread that processes packages from the queue.
  while true:
    let pkg = popPackage()
    if pkg.len == 0:
      var done: bool
      withLock(jobLock):
        done = (jobsInProgress == 0)
      if done:
        break
      sleep(20)
      continue

    if dirExists(pkg):
      withLock(jobLock):
        dec jobsInProgress
      continue

    fetchPackage(pkg, "")

    withLock(jobLock):
      dec jobsInProgress

proc addDirToNimCfg(path: string) =
  ## Add a directory to the nim.cfg file.
  withLock(jobLock):
    if not fileExists("nim.cfg"):
      writeFile("nim.cfg", "# Created by Nimby\n")
    var nimCfg = readFile("nim.cfg")
    if nimCfg.contains(&"--path:\"{path}\""):
      return
    nimCfg.add(&"--path:\"{path}\"\n")
    writeFile("nim.cfg", nimCfg)

proc addToNimCfg(packageName: string) =
  ## Add the package to the nim.cfg file.
  let path = parseNimbleFile(packageName & "/" & packageName & ".nimble").srcDir
  addDirToNimCfg(packageName & "/" & path)

proc removeFromNimCfg(name: string) =
  ## Remove the package from the nim.cfg file.
  withLock(jobLock):
    var nimCfg = readFile("nim.cfg")
    var lines = nimCfg.splitLines()
    for i, line in lines:
      if line.contains(&"--path:\"{name}/") or line.contains(&"--path:\"{name}\""):
        lines.delete(i)
        break
    nimCfg = lines.join("\n")
    writeFile("nim.cfg", lines.join("\n"))

proc fetchPackage(argument: string, indent: string) =
  ## Main recursive function to fetch a package and its dependencies.

  var packageName = argument
  var packageGitHash = ""
  var isLocal = false

  if packageName.endsWith(".nimble"):
    if not fileExists(packageName):
      quit(&"Local nimble file not found: {packageName}")
    else:
      info &"Using local nimble file: {packageName}"
    isLocal = true
    packageName = argument.extractFilename()
    packageName.removeSuffix(".nimble")
    let packageDir = argument.parentDir().replace("\\", "/") & "/" & parseNimbleFile(argument).srcDir
    addDirToNimCfg(packageDir)
    isLocal = true

  if packageName.contains("#"):
    let parts = packageName.split("#")
    packageName = parts[0]
    packageGitHash = parts[1]

  if isLocal:

    # Fetch dependencies from local nimble file.
    for dep in parseNimbleFile(argument).deps:
      let depName = dep[0]
      let depOp = dep[1]
      let depVersion = dep[2]
      if depName == "nim":
        continue
      enqueuePackage(depName)

  else:

    if dirExists(packageName):
      return

    let packages = readFile("packages/packages.json").parseJson()
    var package: JsonNode
    for p in packages:
      let name = p["name"].getStr()
      if name.toLowerAscii() == packageName.toLowerAscii():
        info &"Package found: {name}"
        package = p
        break

    if package == nil:
      quit &"Package `{packageName}` not found in global packages.json."

    let
      name = package["name"].getStr()
      methodKind = package["method"].getStr()
      url = package["url"].getStr()

    info &"Package: {name} {methodKind} {url}"
    case methodKind:
    of "git":
      echo &"Cloning package: {argument}"
      if packageGitHash.len > 0:
        if dirExists(name):
          return
        cmd(&"git clone --no-checkout --depth 1 {url} {name}")
        cmd(&"git -C {name} fetch --depth 1 origin {packageGitHash}")
        cmd(&"git -C {name} checkout {packageGitHash}")
      else:
        cmd(&"git clone --depth 1 {url} {name}")
      addToNimCfg(name)
      echo &"Installed package: {name}"
      fetchDeps(name, indent & "  ")
    else:
      quit &"Unknown method {methodKind} to fetch package {name}"

proc installPackage(argument: string) =
  ## Install a package.
  timeStart()
  echo &"Installing package: {argument}"

  if dirExists(argument):
    quit("Package already installed.")

  if not fileExists("packages/packages.json"):
    info "Packages not found, cloning..."
    cmd("git clone https://github.com/nim-lang/packages.git --depth 1 packages")

  # init job queue
  jobQueueStart = 0
  jobQueueEnd = 0
  jobsInProgress = 0

  # Ensure packages index is available before workers start
  # and enqueue the initial package
  enqueuePackage(argument)

  var threads: array[WorkerCount, Thread[int]]
  for i in 0..<WorkerCount:
    createThread(threads[i], worker, i)
  for i in 0..<WorkerCount:
    joinThread(threads[i])

  timeEnd()
  quit(0)

proc updatePackage(argument: string) =
  ## Update a package.
  info &"Updating package: {argument}"

proc removePackage(argument: string) =
  ## Remove a package.
  info &"Removing package: {argument}"
  removeFromNimCfg(argument)
  if not dirExists(argument):
    quit("Package not found.")
  removeDir(argument)

proc readPackageVersion(packageName: string): string =
  ## Read the version of a package.
  let fileName = &"{packageName}/{packageName}.nimble"
  if not fileExists(fileName):
    return ""
  return parseNimbleFile(fileName).version

proc listPackage(argument: string) =
  ## List all packages in the workspace.
  if argument != "":
    if not dirExists(argument):
      quit(&"Package `{argument}` not found.")
    let packageName = argument
    let packageVersion = readPackageVersion(packageName)
    let gitHash = readGitHash(packageName)
    echo &"{packageName} {packageVersion} {gitHash}"
  else:
    for kind, path in walkDir(workspaceRoot):
      if kind == pcDir:
        let packageName = path.extractFilename()
        let packageVersion = readPackageVersion(packageName)
        let gitHash = readGitHash(packageName)
        echo &"{packageName} {packageVersion} {gitHash}"

proc walkTreePackage(name, indent: string) =
  ## Walk the tree of a package.
  let packageName = name
  let packageVersion = readPackageVersion(packageName)
  let gitHash = readGitHash(packageName)
  echo &"{indent}{packageName} {packageVersion} {gitHash}"
  let deps = readPackageDeps(packageName)
  for dep in deps:
    walkTreePackage(dep, indent & "  ")

proc treePackage(argument: string) =
  ## Tree the package dependencies.
  if argument != "":
    if not dirExists(argument):
      quit(&"Package `{argument}` not found.")
    let packageName = argument
    walkTreePackage(packageName, "")
  else:
    for kind, path in walkDir(workspaceRoot):
      if kind == pcDir:
        let packageName = path.extractFilename()
        walkTreePackage(packageName, "")

proc checkPackage(packageName: string) =
  ## Check a package.
  if not fileExists(&"{packageName}/{packageName}.nimble"):
    return
  let deps = readPackageDeps(packageName)
  for dep in deps:
    if not dirExists(dep):
      echo &"Dependency `{dep}` not found for package `{packageName}`."
  if not fileExists(&"nim.cfg"):
    quit(&"Package `nim.cfg` not found.")
  let nimCfg = readFile("nim.cfg")
  if not nimCfg.contains(&"--path:\"{packageName}/") and not nimCfg.contains(&"--path:\"{packageName}\""):
    echo &"Package `{packageName}` not found in nim.cfg."

proc doctorPackage(argument: string) =
  ## Doctor the package.
  # Walk through all the packages:
  # Make sure they have nim.cfg entry
  # Make sure they have all deps installed.
  if argument != "":
    if not dirExists(argument):
      quit(&"Package `{argument}` not found.")
    let packageName = argument
    checkPackage(packageName)
  else:
    for kind, path in walkDir(workspaceRoot):
      if kind == pcDir:
        let packageName = path.extractFilename()
        checkPackage(packageName)

proc depsPackage(argument: string) =
  ## List the dependencies of a package.

  if not dirExists(argument):
    quit(&"Package `{argument}` not found.")
  let packageName = argument
  var listedDeps: seq[string]
  proc walkDeps(packageName: string) =
    for dep in readPackageDeps(packageName):
      if dep notin listedDeps:
        let depVersion = readPackageVersion(dep)
        let depGitHash = readGitHash(dep)
        echo &"{dep} {depVersion} {depGitHash}"
        listedDeps.add(dep)
        walkDeps(dep)
  walkDeps(packageName)

  for dep in readPackageDeps(packageName):
    if dep notin listedDeps:
      let depVersion = readPackageVersion(dep)
      let depGitHash = readGitHash(dep)
      echo &"{dep} {depVersion} {depGitHash}"
      listedDeps.add(dep)

proc syncPackage(path: string) =
  ## Sync the package.
  info &"Syncing lock file: {path}"
  timeStart()

  if not fileExists("packages/packages.json"):
    info "Packages not found, cloning..."
    cmd("git clone https://github.com/nim-lang/packages.git --depth 1 packages")

  let packages = readFile("packages/packages.json").parseJson()

  if not fileExists(path):
    quit(&"Package lock file `{path}` not found.")

  for line in readFile(path).splitLines():
    let parts = line.split(" ")
    if parts.len != 3:
      continue
    let packageName = parts[0]
    while dirExists(packageName):
      echo &"Removing existing package: {packageName}"
      moveDir(packageName, packageName & "_old")
      removeDir(packageName & "_old")

  for line in readFile(path).splitLines():
    let parts = line.split(" ")
    if parts.len != 3:
      continue
    let packageName = parts[0]
    let packageVersion = parts[1]
    let packageGitHash = parts[2]
    enqueuePackage(packageName & "#" & packageGitHash)

  var threads: array[WorkerCount, Thread[int]]
  for i in 0 ..< WorkerCount:
    createThread(threads[i], worker, i)
  for i in 0 ..< WorkerCount:
    joinThread(threads[i])

  timeEnd()
  quit(0)

when isMainModule:
  workspaceRoot = findWorkspaceRoot()
  setCurrentDir(workspaceRoot)

  var subcommand, argument: string
  var p = initOptParser()
  for kind, key, val in p.getopt():
    case kind
    of cmdArgument:
      if subcommand == "":
        subcommand = key
      else:
        argument = key
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h":
        writeHelp()
        quit(0)
      of "version", "v":
        writeVersion()
        quit(0)
      of "verbose", "V":
        verbose = true
    of cmdEnd: assert(false) # cannot happen

  case subcommand
    of "": writeHelp()
    of "install": installPackage(argument)
    of "sync": syncPackage(argument)
    of "update": updatePackage(argument)
    of "remove", "uninstall": removePackage(argument)
    of "list": listPackage(argument)
    of "tree": treePackage(argument)
    of "deps", "dependencies": depsPackage(argument)
    of "doctor": doctorPackage(argument)
    of "help": writeHelp()
    else:
      quit "invalid command"
