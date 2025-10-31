

# TO make nimby easy to install it only depends on system packages.
import std/[os, json, times, osproc, parseopt, strutils, strformat, streams,
  locks]

const
  WorkerCount = 32

type
  Dependency* = object
    name*: string
    op*: string
    version*: string

  NimbleFile* = ref object
    version*: string
    srcDir*: string
    installDir*: string
    nimDependency*: Dependency
    dependencies*: seq[Dependency]

var
  verbose: bool = false
  global: bool = false
  updatedGlobalPackages: bool = false
  timeStarted: float64

  jobLock: Lock
  jobQueue: array[100, string]
  jobQueueStart: int = 0
  jobQueueEnd: int = 0
  jobsInProgress: int

initLock(jobLock)

proc info(message: string) =
  ## Print information message if verbose is true.
  if verbose:
    echo message

proc cmd(command: string) =
  ## Run the command and print the output if it fails.
  let exeName = command.split(" ")[0]
  let args = command.split(" ")[1..^1]
  try:
    let p = startProcess(exeName, args=args, options={poUsePath})
    if verbose:
      echo "> ", command
    if p.waitForExit(-1) != 0:
      if not verbose:
        echo "> ", command
      echo p.peekableOutputStream().readAll()
      echo p.peekableErrorStream().readAll()
      quit("error code: " & $p.peekExitCode())
    p.close()
  except OSError:
    echo "> ", command
    quit("error: " & $getCurrentExceptionMsg())

template withLock(lock: Lock, body: untyped) =
  ## Acquire the lock and execute the body.
  acquire(lock)
  {.gcsafe.}:
    try:
      body
    finally:
      release(lock)

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

proc writeVersion() =
  ## Write the version of Nimby.
  echo "Nimby 0.1.0"

proc writeHelp() =
  ## Write the help message.
  echo "Usage: nimby <subcommand> [options]"
  echo "  ~ Minimal package manager for Nim. ~"
  echo "    -g, --global install the packages in the ~/.nimby/packages directory"
  echo "    -v, --version print the version of Nimby"
  echo "    -h, --help show this help message"
  echo "    -V, --verbose print verbose output"
  echo "Subcommands:"
  echo "  install    install all Nim packages in the current directory"
  echo "  update     update all Nim packages in the current directory"
  echo "  remove     remove all Nim packages in the current directory"
  echo "  list       list all Nim packages in the current directory"
  echo "  tree       tree all packages as a dependency tree"
  echo "  doctor     doctor all packages to fix any linking issues"
  echo "  lock       generate a lock file for a package"
  echo "  sync       sync a lock file for a package"
  echo "  help       show this help message"

proc getGlobalPackagesDir(): string =
  ## Get the global packages directory.
  "~/.nimby/pkgs".expandTilde()

proc parseNimbleFile*(fileName: string): NimbleFile =
  ## Parse the nimble file and return a NimbleFile object.
  let nimble = readFile(fileName)
  result = NimbleFile(installDir: fileName.parentDir())
  for line in nimble.splitLines():
    if line.startsWith("version"):
      result.version = line.split(" ")[^1].strip().replace("\"", "")
    elif line.startsWith("srcDir"):
      result.srcDir = line.split(" ")[^1].strip().replace("\"", "")
    elif line.startsWith("requires"):
      var i = 9
      var name, op, version = ""
      while i < line.len and line[i] in [' ', '"']:
        inc i
      while i < line.len and line[i] notin ['=', '<', '>', '~', '^', ' ']:
        name.add(line[i])
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
      let dep = Dependency(
        name: name,
        op: op,
        version: version
      )
      if name == "nim":
        result.nimDependency = dep
      else:
        result.dependencies.add(dep)
  return result

proc getNimbleFile(name: string): NimbleFile =
  ## Get the nimble file for a package.
  let
    localPath = &"{name}/{name}.nimble"
    globalPath = getGlobalPackagesDir() / name / name & ".nimble"
  if fileExists(localPath):
    return parseNimbleFile(localPath)
  if fileExists(globalPath):
    return parseNimbleFile(globalPath)

proc getGlobalPackages(): JsonNode =
  ## Update the packages.json file.
  let globalPackagesDir = getGlobalPackagesDir() / "packages"
  if not updatedGlobalPackages:
    if not fileExists(globalPackagesDir / "packages.json"):
      info "Packages.json not found, cloning..."
      cmd(&"git clone https://github.com/nim-lang/packages.git --depth 1 {globalPackagesDir}")
    else:
      info "Packages.json found, pulling..."
      cmd(&"git -C {globalPackagesDir} pull")
    updatedGlobalPackages = true
  return readFile(globalPackagesDir & "/packages.json").parseJson()

proc getGlobalPackage(packageName: string): JsonNode =
  ## Get a global package from the global packages.json file.
  let packages = getGlobalPackages()
  for p in packages:
    if p["name"].getStr() == packageName:
      return p

proc fetchPackage(argument: string) {.gcsafe.}

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

proc readGitHash(packageName: string): string =
  ## Read the git hash of a package.
  let globalPath = getGlobalPackagesDir() / packageName
  for path in [packageName, globalPath]:
    if dirExists(path):
      let p = execCmdEx(&"git -C {path} rev-parse HEAD")
      if p.exitCode == 0:
        return p.output.strip()
  return ""

proc readPackageUrl(packageName: string): string =
  ## Read the url of a package.
  let packages = getGlobalPackages()
  for p in packages:
    if p["name"].getStr() == packageName:
      return p["url"].getStr()

proc fetchDeps(packageName: string) =
  ## Fetch the dependencies of a package.
  let package = getNimbleFile(packageName)
  if package == nil:
    quit(&"Can't fetch deps for Nimble file not found: {packageName}")
  for dep in package.dependencies:
    info &"Dependency: {dep}"
    enqueuePackage(dep.name)

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

    fetchPackage(pkg)

    withLock(jobLock):
      dec jobsInProgress

proc addConfigDir(path: string) =
  ## Add a directory to the nim.cfg file.
  withLock(jobLock):
    let path = path.replace("\\", "/") # Always use linux style paths.
    if not fileExists("nim.cfg"):
      writeFile("nim.cfg", "# Created by Nimby\n")
    var nimCfg = readFile("nim.cfg")
    if nimCfg.contains(&"--path:\"{path}\""):
      return
    nimCfg.add(&"--path:\"{path}\"\n")
    writeFile("nim.cfg", nimCfg)

proc addConfigPackage(name: string) =
  ## Add a package to the nim.cfg file.
  let package = getNimbleFile(name)
  if package == nil:
    quit(&"Nimble file not found: {name}")
  addConfigDir(package.installDir / package.srcDir)

proc removeConfigDir(path: string) =
  ## Remove the package from the nim.cfg file.
  withLock(jobLock):
    var nimCfg = readFile("nim.cfg")
    var lines = nimCfg.splitLines()
    for i, line in lines:
      if line.contains(&"--path:\"{path}\""):
        lines.delete(i)
        break
    nimCfg = lines.join("\n")
    writeFile("nim.cfg", lines.join("\n"))

proc removeConfigPackage(name: string) =
  ## Remove the package from the nim.cfg file.
  let package = getNimbleFile(name)
  if package == nil:
    quit(&"Nimble file not found: {name}")
  removeConfigDir(package.installDir / package.srcDir)

proc fetchPackage(argument: string) =
  ## Main recursive function to fetch a package and its dependencies.

  if argument.endsWith(".nimble"):

    # Packaged form a nimble file.
    let nimblePath = argument
    if not fileExists(nimblePath):
      quit(&"Local nimble file not found: {nimblePath}")
    else:
      info &"Using local nimble file: {nimblePath}"
    let packageName = nimblePath.splitFile().name
    addConfigPackage(packageName)
    for dependency in getNimbleFile(packageName).dependencies:
      enqueuePackage(dependency.name)

  elif argument.contains(" "):

    # Install a locked package.
    let
      parts = argument.split(" ")
      packageName = parts[0]
      packageVersion = parts[1]
      packageUrl = parts[2]
      packageGitHash = parts[3]
      packagePath =
        if global:
          getGlobalPackagesDir() / packageName
        else:
          packageName

    if not dirExists(packagePath):
      # Clone the package from the url at given git hash.
      cmd(&"git clone --no-checkout --depth 1 {packageUrl} {packagePath}")
      cmd(&"git -C {packagePath} fetch --depth 1 origin {packageGitHash}")
      cmd(&"git -C {packagePath} checkout {packageGitHash}")
      echo &"Installed package: {packageName}"
    else:
      # Check to see if the package is at the given git hash.
      let gitHash = readGitHash(packageName)
      if gitHash != packageGitHash:
        cmd(&"git -C {packagePath} fetch --depth 1 origin {packageGitHash}")
        cmd(&"git -C {packagePath} checkout {packageGitHash}")
        echo &"Updated package: {packageName}"
      else:
        info &"Package {packageName} is correct hash."
    addConfigPackage(packageName)

  else:

    # Install a global or local package.
    let package = getGlobalPackage(argument)
    if package == nil:
      quit &"Package `{argument}` not found in global packages."
    let
      name = package["name"].getStr()
      methodKind = package["method"].getStr()
      url = package["url"].getStr()
    info &"Package: {name} {methodKind} {url}"
    case methodKind:
    of "git":
      let path =
        if global:
          getGlobalPackagesDir() / name
        else:
          name
      info &"Cloning package: {argument} to {path}"
      if dirExists(path):
        info &"Package already exists: {path}"
      else:
        cmd(&"git clone --depth 1 {url} {path}")
      addConfigPackage(name)
      echo &"Installed package: {name}"
      fetchDeps(name)
    else:
      quit &"Unknown method {methodKind} to fetch package {name}"

proc installPackage(argument: string) =
  ## Install a package.
  timeStart()
  echo &"Installing package: {argument}"

  if dirExists(argument):
    quit("Package already installed.")

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
  removeConfigPackage(argument)
  let package = getNimbleFile(argument)
  if package == nil:
    quit(&"Nimble file not found: {argument}")
  let packagePath = package.installDir
  if not dirExists(packagePath):
    quit(&"Package not found: {packagePath}")
  removeDir(packagePath)
  echo &"Removed package: {argument}"

proc listPackage(argument: string) =
  ## List a package.
  let nimbleFile = getNimbleFile(argument)
  if nimbleFile != nil:
    let packageName = argument
    let packageVersion = nimbleFile.version
    let gitUrl = readPackageUrl(packageName)
    let gitHash = readGitHash(packageName)
    echo &"{packageName} {packageVersion} {gitUrl} {gitHash}"

proc listPackages(argument: string) =
  ## List all packages in the workspace.
  if argument != "":
    listPackage(argument)
  else:
    for dir in [".", getGlobalPackagesDir()]:
      echo &"-------- Walking directory: {dir}"
      for kind, path in walkDir(dir):
        if kind == pcDir:
          listPackage(path.extractFilename())

proc treePackage(name, indent: string) =
  ## Walk the tree of a package.
  let nimbleFile = getNimbleFile(name)
  if nimbleFile != nil:
    let packageName = name
    let packageVersion = nimbleFile.version
    echo &"{indent}{packageName} {packageVersion}"
    for dependency in nimbleFile.dependencies:
      treePackage(dependency.name, indent & "  ")

proc treePackages(argument: string) =
  ## Tree the package dependencies.
  if argument != "":
    treePackage(argument, "")
  else:
    for dir in [".", getGlobalPackagesDir()]:
      echo &"-------- Walking directory: {dir}"
      for kind, path in walkDir(dir):
        if kind == pcDir:
          treePackage(path.extractFilename(), "")

proc checkPackage(packageName: string) =
  ## Check a package.
  for dependency in getNimbleFile(packageName).dependencies:
    if not dirExists(dependency.name):
      echo &"Dependency `{dependency.name}` not found for package `{packageName}`."
  if not fileExists(&"nim.cfg"):
    quit(&"Package `nim.cfg` not found.")
  let nimCfg = readFile("nim.cfg")
  if not nimCfg.contains(&"--path:\"{packageName}/") and not nimCfg.contains(&"--path:\"{packageName}\""):
    echo &"Package `{packageName}` not found in nim.cfg."

proc doctorPackage(argument: string) =
  ## Doctor the package.
  # Walk through all the packages:
  # Make workspace root has a nim.cfg entry.
  # Make sure they have all deps installed.
  if argument != "":
    if not dirExists(argument):
      quit(&"Package `{argument}` not found.")
    let packageName = argument
    checkPackage(packageName)
  else:
    for kind, path in walkDir("."):
      if kind == pcDir:
        let packageName = path.extractFilename()
        checkPackage(packageName)

proc lockPackage(argument: string) =
  ## Generate a lock file for a package.
  for packageName in [argument, getGlobalPackagesDir() / argument]:
    let nimbleFile = getNimbleFile(packageName)
    if nimbleFile == nil:
      continue
    var listedDeps: seq[string]
    proc walkDeps(packageName: string) =
      for dependency in getNimbleFile(packageName).dependencies:
        if dependency.name notin listedDeps:
          let url = readPackageUrl(dependency.name)
          let version = getNimbleFile(dependency.name).version
          let gitHash = readGitHash(dependency.name)
          echo &"{dependency.name} {version} {url} {gitHash}"
          listedDeps.add(dependency.name)
          walkDeps(dependency.name)
    walkDeps(packageName)
    break

proc syncPackage(path: string) =
  ## Sync the package.
  info &"Syncing lock file: {path}"
  timeStart()

  if not fileExists(path):
    quit(&"Package lock file `{path}` not found.")

  for line in readFile(path).splitLines():
    let parts = line.split(" ")
    if parts.len != 4:
      continue
    info "Syncing package: " & line
    enqueuePackage(line)

  var threads: array[WorkerCount, Thread[int]]
  for i in 0 ..< WorkerCount:
    createThread(threads[i], worker, i)
  for i in 0 ..< WorkerCount:
    joinThread(threads[i])

  timeEnd()
  quit(0)


proc installNim(nimVersion: string) =
  ## Install a specific version of Nim.
  info &"Installing Nim: {nimVersion}"
  let nimbyDir = "~/.nimby".expandTilde()
  if not dirExists(nimbyDir):
    createDir(nimbyDir)
  let installDir = nimbyDir / ("nim-" & nimVersion)
  if dirExists(installDir):
    echo &"Nim {nimVersion} already installed at: {installDir}"
  else:
    createDir(installDir)

    let previousDir = getCurrentDir()
    setCurrentDir(installDir)

    when defined(windows):
      let url = &"https://nim-lang.org/download/nim-{nimVersion}_x64.zip"
      echo &"Downloading: {url}"
      cmd(&"curl -sSL {url} -o nim.zip")
      # Use PowerShell to extract to current directory for wider availability on Windows
      cmd("powershell -NoProfile -Command Expand-Archive -Force -Path nim.zip -DestinationPath .")
      let extractedDir = &"nim-{nimVersion}"
      if dirExists(extractedDir):
        for kind, path in walkDir(extractedDir):
          let name = path.extractFilename()
          if kind == pcDir:
            moveDir(extractedDir / name, installDir / name)
          else:
            moveFile(extractedDir / name, installDir / name)
        removeDir(extractedDir)

    elif defined(macosx):
      let url = &"https://nim-lang.org/download/nim-{nimVersion}.tar.xz"
      echo &"Downloading: {url}"
      cmd(&"curl -sSL {url} -o nim.tar.xz")
      cmd("tar xf nim.tar.xz --strip-components=1")
      echo "Building the Nim compiler"
      cmd("./build.sh")
      echo "Building the Koch tool"
      cmd("./bin/nim c --noNimblePath --skipUserCfg --skipParentCfg --hints:off koch")
      echo "Booting the Nim compiler"
      cmd("./koch boot -d:release --skipUserCfg --skipParentCfg --hints:off")
      echo "Building the Koch tools"
      cmd("./koch tools --skipUserCfg --skipParentCfg --hints:off")

    elif defined(linux):
      let url = &"https://nim-lang.org/download/nim-{nimVersion}-linux_x64.tar.xz"
      echo &"Downloading: {url}"
      cmd(&"curl -sSL {url} -o nim.tar.xz")
      echo "Extracting the Nim compiler"
      cmd("tar xf nim.tar.xz --strip-components=1")

    else:
      quit "unsupported platform for Nim installation"

    setCurrentDir(previousDir)
    echo &"Installed Nim {nimVersion} to: {installDir}"

  # copy installDir/nim-{nimVersion} to installDir/bin
  let versionNimDir = nimbyDir / "nim-" & nimVersion
  let globalNimDir = nimbyDir / "nim"
  removeDir(globalNimDir)
  copyDir(versionNimDir, globalNimDir)
  info &"Copied {versionNimDir} to {globalNimDir}"

  when not defined(windows):
    # Make sure the Nim binary is executable.
    cmd(&"chmod +x {globalNimDir}/bin/nim")

  # Tell the user a single PATH change they can run now.
  let binPath = nimbyDir / "nim" / "bin"
  echo "Add Nim to your PATH for this session with one of:"
  when defined(windows):
    let winBin = (binPath.replace("/", "\\"))
    echo &"$env:PATH = \"{winBin};$env:PATH\"   # PowerShell"
  else:
    echo &"export PATH=\"{binPath}:$PATH\"      # bash/zsh"
    echo &"fish_add_path {binPath}              # fish"

when isMainModule:

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
      of "global", "g":
        echo "Using global packages directory."
        global = true
        if not dirExists(getGlobalPackagesDir()):
          info &"Creating global packages directory: {getGlobalPackagesDir()}"
          createDir(getGlobalPackagesDir())
      else:
        echo "Unknown option: " & key
        quit(1)
    of cmdEnd:
      assert(false) # cannot happen

  case subcommand
    of "": writeHelp()
    of "install": installPackage(argument)
    of "sync": syncPackage(argument)
    of "update": updatePackage(argument)
    of "remove", "uninstall": removePackage(argument)
    of "list": listPackages(argument)
    of "tree": treePackages(argument)
    of "lock": lockPackage(argument)
    of "use": installNim(argument)
    of "doctor": doctorPackage(argument)
    of "help": writeHelp()
    else:
      quit "invalid command"
