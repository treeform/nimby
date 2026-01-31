

# To make Nimby easy to install, it depends only on system packages.
import std/[os, json, times, osproc, parseopt, strutils, strformat, streams,
  locks, deques, sets]

when defined(monkey):
  # Monkey mode: Randomly raise errors to test error handling and robustness.
  import std/random
  const MonkeyProbability = 10
  randomize()

const
  WorkerCount = 32
  lockDir = "nimbylock"

type
  NimbyError* = object of CatchableError

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
  source: bool = false
  updatedGlobalPackages: bool = false
  timeStarted: float64

  printLock: Lock
  jobLock: Lock
  retryLock: Lock

  jobQueue: Deque[string]
  jobsInProgress: HashSet[string]

initLock(jobLock)
initLock(printLock)
initLock(retryLock)

template withLock(lock: Lock, body: untyped) =
  ## Acquire the lock and execute the body.
  acquire(lock)
  {.gcsafe.}:
    try:
      body
    finally:
      release(lock)

proc info(message: string) =
  ## Print an informational message if verbose is true.
  if verbose:
    # To prevent garbled output, lock the print lock.
    withLock(printLock):
      echo message

proc print(message: string) =
  ## Print a log message.
  # To prevent garbled output, lock the print lock.
  withLock(printLock):
    echo message

proc getGlobalNimbyDir(): string =
  ## Get the global packages directory.
  "~/.nimby".expandTilde()

proc getGlobalPackagesDir(): string =
  ## Get the global packages directory.
  getGlobalNimbyDir() / "pkgs"

proc getLockDirPath(): string =
  getGlobalNimbyDir() / lockDir

proc acquireGlobalLock(): bool =
  # We use a directory because creating a directory is atomic and we can know
  # if it already existed or not. Checking for the existance of a file and then
  # creating it if needed is not atomic.
  let lockPath = getLockDirPath()
  try:
    let alreadyExists = existsOrCreateDir(lockPath)
    return not alreadyExists
  except:
    return false

proc releaseGlobalLock() =
  let lockPath = getLockDirPath()
  removeDir(lockPath)

proc nimbyQuit(errorCode: int) =
  releaseGlobalLock()
  quit(errorCode)

proc nimbyQuit(errorMsg: string) =
  releaseGlobalLock()
  quit(errorMsg)

proc readFileSafe(fileName: string): string =
  ## Read the file and return the content.
  try:
    when defined(monkey):
      if rand(100) < MonkeyProbability:
        raise newException(NimbyError, "error reading file `" & fileName & "`: " & "Monkey error")
    return readFile(fileName)
  except:
    # Lock is normally not needed, but if we are retrying, lets be double safe.
    withLock(retryLock):
      for trying in 2 .. 3:
        print &"Try {trying} of 3: {getCurrentExceptionMsg()}"
        try:
          return readFile(fileName)
        except:
          sleep(100 * trying)
      raise newException(NimbyError, "error reading file `" & fileName & "`: " & getCurrentExceptionMsg())

proc writeFileSafe(fileName: string, content: string) =
  ## Write the file and return the content.
  try:
    when defined(monkey):
      if rand(100) < MonkeyProbability:
        raise newException(NimbyError, "error writing file `" & fileName & "`: " & "Monkey error")
    writeFile(fileName, content)
  except:
    # Lock is normally not needed, but if we are retrying, lets be double safe.
    withLock(retryLock):
      for trying in 2 .. 3:
        print &"Try {trying} of 3: {getCurrentExceptionMsg()}"
        try:
          writeFile(fileName, content)
          return
        except:
          sleep(100 * trying)
      raise newException(NimbyError, "error writing file `" & fileName & "`: " & getCurrentExceptionMsg())

proc runOnce(command: string) =
  let exeName = command.split(" ")[0]
  let args = command.split(" ")[1..^1]
  try:
    var options = {poUsePath}
    if verbose:
      # Print the command output to the console.
      options.incl(poStdErrToStdOut)
      options.incl(poParentStreams)
    if verbose:
      print "> " & command
    let p = startProcess(exeName, args=args, options=options)
    if p.waitForExit(-1) != 0:
      if not verbose:
        print "> " & command
      print p.peekableOutputStream().readAll()
      print p.peekableErrorStream().readAll()
      raise newException(NimbyError, "error code: " & $p.peekExitCode())
    p.close()
  except:
    raise newException(NimbyError, "error running command `" & command & "`: " & $getCurrentExceptionMsg())

proc runSafe(command: string) =
  ## Run the command and print the output if it fails.
  try:
    when defined(monkey):
      if rand(100) < MonkeyProbability:
        raise newException(NimbyError, "error starting process `" & command & "`: " & "Monkey error")
    runOnce(command)
  except:
    # Lock is normally not needed, but if we are retrying, lets be double safe.
    withLock(retryLock):
      for trying in 2 .. 3:
        print &"Try {trying} of 3: {getCurrentExceptionMsg()}"
        try:
          runOnce(command)
          return
        except:
          sleep(100 * trying)
      raise newException(NimbyError, "error running command `" & command & "`: " & getCurrentExceptionMsg())

proc timeStart() =
  ## Start the timer.
  timeStarted = epochTime()

proc timeEnd() =
  ## Stop the timer and print the time taken.
  let timeEnded = epochTime()
  let dt = timeEnded - timeStarted
  print &"Took: {dt:.2f} seconds"

proc writeVersion() =
  ## Print the version of Nimby.
  print "Nimby 0.1.14"

proc writeHelp() =
  ## Show the help message.
  print "Usage: nimby <subcommand> [options]"
  print "  ~ Minimal package manager for Nim. ~"
  print "    -g, --global Install packages in the ~/.nimby/pkgs directory"
  print "    -v, --version print the version of Nimby"
  print "    -h, --help show this help message"
  print "    -V, --verbose print verbose output"
  print "Subcommands:"
  print "  install    install all Nim packages in the current directory"
  print "  update     update all Nim packages in the current directory"
  print "  remove     remove all Nim packages in the current directory"
  print "  list       list all Nim packages in the current directory"
  print "  tree       show all packages as a dependency tree"
  print "  doctor     diagnose all packages and fix linking issues"
  print "  lock       generate a lock file for a package"
  print "  sync       synchronize packages from a lock file"
  print "  help       show this help message"

proc isGitUrl*(s: string): bool =
  ## Check if a string is a git URL.
  s.startsWith("http://") or s.startsWith("https://") or s.startsWith("git@")

proc extractPackageNameFromUrl*(url: string): string =
  ## Extract package name from a git URL.
  var cleanUrl = url
  if "#" in cleanUrl:
    cleanUrl = cleanUrl.split("#")[0]
  if cleanUrl.endsWith(".git"):
    cleanUrl = cleanUrl[0..^5]
  result = cleanUrl.split("/")[^1]

proc extractUrlFragment*(url: string): string =
  ## Extract fragment (branch/tag/commit) from URL.
  if "#" in url:
    result = url.split("#")[1]

proc parseNimbleFile*(fileName: string): NimbleFile =
  ## Parse the .nimble file and return a NimbleFile object.
  let nimble = readFileSafe(fileName)
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
      while i < line.len and line[i] notin ['=', '<', '>', '~', '^', ' ', '"']:
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
  ## Get the .nimble file for a package.
  let
    localPath = name / name & ".nimble"
    globalPath = getGlobalPackagesDir() / name / name & ".nimble"
  if fileExists(localPath):
    return parseNimbleFile(localPath)
  if fileExists(globalPath):
    return parseNimbleFile(globalPath)

proc getGlobalPackages(): JsonNode =
  ## Fetch and return the global packages index (packages.json).
  let globalPackagesDir = getGlobalPackagesDir() / "packages"
  if not updatedGlobalPackages:
    if not fileExists(globalPackagesDir / "packages.json"):
      info "Packages.json not found, cloning..."
      withLock(jobLock):
        if not fileExists(globalPackagesDir / "packages.json") and not updatedGlobalPackages:
          runOnce(&"git clone https://github.com/nim-lang/packages.git --depth 1 {globalPackagesDir}")
        updatedGlobalPackages = true
    else:
      info "Packages.json found, pulling..."
      withLock(jobLock):
        if not updatedGlobalPackages:
          runSafe(&"git -C {globalPackagesDir} pull")
        updatedGlobalPackages = true

  return readFileSafe(globalPackagesDir & "/packages.json").parseJson()

proc getGlobalPackage(packageName: string): JsonNode =
  ## Get a global package from the global packages.json file.
  let packages = getGlobalPackages()
  for p in packages:
    if p["name"].getStr() == packageName:
      return p

proc fetchPackage(argument: string) {.gcsafe.}
proc addTreeToConfig(path: string) {.gcsafe.}

proc enqueuePackage(packageName: string) =
  ## Add a package to the job queue. Ensure it is not already queued or in progress.
  withLock(jobLock):
    if packageName notin jobQueue and packageName notin jobsInProgress:
      jobQueue.addLast(packageName)
    else:
      info &"Package already in queue: {packageName}"

proc popPackage(): string =
  ## Pop a package from the job queue or return an empty string.
  var pkg: string
  withLock(jobLock):
    if jobQueue.len > 0:
      result = jobQueue.popFirst()
    if result != "":
      jobsInProgress.incl(result)

proc readGitHash(packageName: string): string =
  ## Read the Git hash of a package.
  let globalPath = getGlobalPackagesDir() / packageName
  for path in [packageName, globalPath]:
    if dirExists(path):
      let p = execCmdEx(&"git -C {path} rev-parse HEAD")
      if p.exitCode == 0:
        return p.output.strip()
  return ""

proc readPackageUrl(packageName: string): string =
  ## Read the URL of a package.
  let packages = getGlobalPackages()
  for p in packages:
    if p["name"].getStr() == packageName:
      return p["url"].getStr()

proc fetchDeps(packageName: string) =
  ## Fetch the dependencies of a package.
  let package = getNimbleFile(packageName)
  if package == nil:
    nimbyQuit(&"Can't fetch deps for: Nimble file not found: {packageName}")
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
        done = (jobsInProgress.len == 0)
      if done:
        break
      sleep(20)
      continue

    if dirExists(pkg):
      withLock(jobLock):
        jobsInProgress.excl(pkg)
      info &"Package already exists: {pkg}"
      addTreeToConfig(pkg)
      continue

    fetchPackage(pkg)

    withLock(jobLock):
      jobsInProgress.excl(pkg)

proc addConfigDir(path: string) =
  ## Add a directory to the nim.cfg file.
  withLock(jobLock):
    let path = path.replace("\\", "/") # Always use Linux-style paths.
    if not fileExists("nim.cfg"):
      writeFileSafe("nim.cfg", "# Created by Nimby\n")
    var nimCfg = readFileSafe("nim.cfg")
    if nimCfg.contains(&"--path:\"{path}\""):
      return
    let line = &"--path:\"{path}\"\n"
    info &"Adding nim.cfg line: {line.strip()}"
    nimCfg.add(line)
    writeFileSafe("nim.cfg", nimCfg)

proc addConfigPackage(name: string) =
  ## Add a package to the nim.cfg file.
  let package = getNimbleFile(name)
  if package == nil:
    nimbyQuit(&"Can't add config package: Nimble file not found: {name}")
  addConfigDir(package.installDir / package.srcDir)

proc removeConfigDir(path: string) =
  ## Remove a directory from the nim.cfg file.
  withLock(jobLock):
    var nimCfg = readFileSafe("nim.cfg")
    var lines = nimCfg.splitLines()
    for i, line in lines:
      if line.contains(&"--path:\"{path}\""):
        lines.delete(i)
        break
    nimCfg = lines.join("\n")
    writeFileSafe("nim.cfg", lines.join("\n"))

proc removeConfigPackage(name: string) =
  ## Remove the package from the nim.cfg file.
  let package = getNimbleFile(name)
  if package == nil:
    nimbyQuit(&"Can't remove config package: Nimble file not found: {name}")
  removeConfigDir(package.installDir / package.srcDir)

proc addTreeToConfig(path: string) =
  ## Add the tree of a package to the nim.cfg file.
  let nimbleFile = getNimbleFile(path)
  if nimbleFile == nil:
    nimbyQuit(&"Can't add tree to config: Nimble file not found: {path}")
  addConfigDir(nimbleFile.installDir / nimbleFile.srcDir)
  for dependency in nimbleFile.dependencies:
    enqueuePackage(dependency.name)

proc fetchPackage(argument: string) =
  ## Main recursive function to fetch a package and its dependencies.
  if argument.endsWith(".nimble"):
    # Package from a Nimble file.
    let nimblePath = argument
    if not fileExists(nimblePath):
      nimbyQuit(&"Local .nimble file not found: {nimblePath}")
    else:
      info &"Using local .nimble file: {nimblePath}"
    let
      packageName = nimblePath.splitFile().name
      packagePath = nimblePath.parentDir()
    addConfigPackage(packageName)
    for dependency in parseNimbleFile(nimblePath).dependencies:
      enqueuePackage(dependency.name)

  elif argument.contains(" "):

    # Install a locked package.
    let
      parts = argument.split(" ")
      packageName = parts[0]
      packageUrl = parts[2]
      packageGitHash = parts[3]
      packagePath =
        if global:
          getGlobalPackagesDir() / packageName
        else:
          packageName

    info &"Looking in directory: {packagePath}"

    if not dirExists(packagePath):
      # Clone the package from the URL at the given Git hash.
      runOnce(&"git clone --no-checkout --depth 1 {packageUrl} {packagePath}")
      runOnce(&"git -C {packagePath} fetch --depth 1 origin {packageGitHash}")
      runOnce(&"git -C {packagePath} checkout {packageGitHash}")
      print &"Installed package: {packageName}"
    else:
      # Check whether the package is at the given Git hash.
      let gitHash = readGitHash(packageName)
      if gitHash != packageGitHash:
        runSafe(&"git -C {packagePath} fetch --depth 1 origin {packageGitHash}")
        runSafe(&"git -C {packagePath} checkout {packageGitHash}")
        print &"Updated package: {packageName}"
      else:
        info &"Package {packageName} has the correct hash."
    addConfigPackage(packageName)

  elif isGitUrl(argument):

    # Install directly from git URL.
    let url = argument
    let packageName = extractPackageNameFromUrl(url)
    let fragment = extractUrlFragment(url)
    let path =
      if global:
        getGlobalPackagesDir() / packageName
      else:
        packageName

    info &"Cloning package from URL: {url} to {path}"

    if dirExists(path):
      info &"Package already exists: {path}"
    else:
      runOnce(&"git clone --depth 1 {url} {path}")
      if fragment != "":
        runSafe(&"git -C {path} checkout {fragment}")
    addConfigPackage(packageName)
    print &"Installed package: {packageName}"
    fetchDeps(packageName)

  else:

    # Install a global or local package.
    let package = getGlobalPackage(argument)
    if package == nil:
      nimbyQuit(&"Package `{argument}` not found in global packages.")
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
        runOnce(&"git clone --depth 1 {url} {path}")
      addConfigPackage(name)
      print &"Installed package: {name}"
      fetchDeps(name)
    else:
      nimbyQuit(&"Unknown method {methodKind} for fetching package {name}")

proc installPackage(argument: string) =
  ## Install a package.
  timeStart()
  print &"Installing package: {argument}"

  if dirExists(argument):
    nimbyQuit("Package already installed.")

  # Ensure the packages index is available before workers start.
  # Enqueue the initial package.
  enqueuePackage(argument)

  var threads: array[WorkerCount, Thread[int]]
  for i in 0 ..< WorkerCount:
    createThread(threads[i], worker, i)
  for i in 0 ..< WorkerCount:
    joinThread(threads[i])

  timeEnd()
  nimbyQuit(0)

proc updatePackage(argument: string) =
  ## Update a package.
  if argument == "":
    nimbyQuit("No package specified for update")
  info &"Updating package: {argument}"
  let package = getNimbleFile(argument)
  if package == nil:
    nimbyQuit(&"Can't update package: Nimble file not found: {argument}")
  let packagePath = package.installDir
  if not dirExists(packagePath):
    nimbyQuit(&"Package not found: {packagePath}")
  runSafe(&"git -C {packagePath} pull")
  print &"Updated package: {argument}"

proc removePackage(argument: string) =
  ## Remove a package.
  if argument == "":
    nimbyQuit("No package specified for removal")
  info &"Removing package: {argument}"
  removeConfigPackage(argument)
  let package = getNimbleFile(argument)
  if package == nil:
    nimbyQuit(&"Can't remove package: Nimble file not found: {argument}")
  let packagePath = package.installDir
  if not dirExists(packagePath):
    nimbyQuit(&"Package not found: {packagePath}")
  removeDir(packagePath)
  print &"Removed package: {argument}"

proc listPackage(argument: string) =
  ## List a package.
  let nimbleFile = getNimbleFile(argument)
  if nimbleFile != nil:
    let packageName = argument
    let packageVersion = nimbleFile.version
    let gitUrl = readPackageUrl(packageName)
    let gitHash = readGitHash(packageName)
    print &"{packageName} {packageVersion} {gitUrl} {gitHash}"

proc listPackages(argument: string) =
  ## List all packages in the workspace.
  if argument != "":
    listPackage(argument)
  else:
    for dir in [".", getGlobalPackagesDir()]:
      for kind, path in walkDir(dir):
        if kind == pcDir:
          listPackage(path.extractFilename())

proc treePackage(name, indent: string) =
  ## Walk the tree of a package.
  let nimbleFile = getNimbleFile(name)
  if nimbleFile != nil:
    let packageName = name
    let packageVersion = nimbleFile.version
    print &"{indent}{packageName} {packageVersion}"
    for dependency in nimbleFile.dependencies:
      treePackage(dependency.name, indent & "  ")

proc treePackages(argument: string) =
  ## Tree the package dependencies.
  if argument != "":
    treePackage(argument, "")
  else:
    for dir in [".", getGlobalPackagesDir()]:
      for kind, path in walkDir(dir):
        if kind == pcDir:
          treePackage(path.extractFilename(), "")

proc checkPackage(packageName: string) =
  ## Check a package.
  let nimbleFile = getNimbleFile(packageName)
  if nimbleFile == nil:
    print &"Package `{packageName}` is not a Nim project (no .nimble file found)."
    return
  for dependency in nimbleFile.dependencies:
    if not dirExists(dependency.name):
      print &"Dependency `{dependency.name}` not found for package `{packageName}`."
  if not fileExists(&"nim.cfg"):
    nimbyQuit(&"Package `nim.cfg` not found.")
  let nimCfg = readFileSafe("nim.cfg")
  if not nimCfg.contains(&"--path:\"{packageName}/") and not nimCfg.contains(&"--path:\"{packageName}\""):
    print &"Package `{packageName}` not found in nim.cfg."

proc doctorPackage(argument: string) =
  ## Diagnose packages and fix configuration issues.
  # Walk through all packages.
  # Ensure the workspace root has a nim.cfg entry.
  # Ensure all dependencies are installed.
  if argument != "":
    if not dirExists(argument):
      nimbyQuit(&"Package `{argument}` not found.")
    let packageName = argument
    checkPackage(packageName)
  else:
    var lines: seq[string]
    if fileExists("nim.cfg"):
      let cfg = readFile("nim.cfg")
      lines = cfg.split('\n')

    if lines.len == 0 or lines[0] != "# Created by Nimby":
      nimbyQuit("Working dir is not a Nimby workspace")

    var packageNames: seq[string]
    for line in lines[1 .. lines.high]:
      if line.startsWith("--path:\""):
        var stop = line.find('/')
        if stop == -1:
          stop = line.high
        packageNames.add(line[8 .. stop - 1])
      else:
        if line != "":
          echo "Unexpected line in workspace nim.cfg: \"" & line & '"'

    for packageName in packageNames:
      checkPackage(packageName)

    var nonworkspaceDirs: seq[string]
    for kind, path in walkDir("."):
      if kind == pcDir:
        let dir = path.extractFilename()
        if dir notin packageNames:
          nonworkspaceDirs.add(dir)

    if nonworkspaceDirs.len > 0:
      echo nonworkspaceDirs.len, " dir(s) not in workspace nim.cfg"
      if verbose:
        for dir in nonworkspaceDirs:
          echo dir, '/'

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
          print &"{dependency.name} {version} {url} {gitHash}"
          listedDeps.add(dependency.name)
          walkDeps(dependency.name)
    walkDeps(packageName)
    break

proc syncPackage(path: string) =
  ## Synchronize packages from a lock file.
  info &"Syncing lock file: {path}"
  timeStart()

  if not fileExists(path):
    nimbyQuit(&"Package lock file `{path}` not found.")

  for line in readFileSafe(path).splitLines():
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
  nimbyQuit(0)

proc installNim(nimVersion: string) =
  ## Install a specific version of Nim.
  info &"Installing Nim: {nimVersion}"
  let nimbyDir = "~/.nimby".expandTilde()
  if not dirExists(nimbyDir):
    createDir(nimbyDir)
  let installDir = nimbyDir / ("nim-" & nimVersion)

  if dirExists(installDir):
    info &"Nim {nimVersion} already downloaded at: {installDir}"
  else:
    createDir(installDir)

    let previousDir = getCurrentDir()
    setCurrentDir(installDir)

    if source:
      runOnce(&"git clone https://github.com/nim-lang/Nim.git --branch v{nimVersion} --depth 1 {installDir}")
      setCurrentDir(installDir)
      when defined(windows):
        runSafe("build_all.bat")
      else:
        runSafe("./build_all.sh")
      let keepDirsAndFiles = @[
          "bin",
          "compiler",
          "config",
          "lib",
          "copying.txt"
      ]
      for kind, path in walkDir(installDir):
        if path.extractFilename() notin keepDirsAndFiles:
          info &"Cleaning up: {path}"
          if kind == pcDir:
            removeDir(path)
          else:
            removeFile(path)
    else:
      when defined(windows):
        let url = &"https://github.com/treeform/nimby-nim-builds/releases/download/{nimVersion}/nim-{nimVersion}-Windows-X64.zip"
        print &"Downloading: {url}"
        runSafe(&"curl -sSL {url} -o nim.zip")
        runSafe("powershell -NoProfile -Command Expand-Archive -Force -Path nim.zip -DestinationPath .")
        let extractedDir = &"nim-{nimVersion}-Windows-X64"
        if dirExists(extractedDir):
          for kind, path in walkDir(extractedDir):
            let name = path.extractFilename()
            if kind == pcDir:
              moveDir(extractedDir / name, installDir / name)
            else:
              moveFile(extractedDir / name, installDir / name)
          removeDir(extractedDir)

      elif defined(macosx):
        let url = &"https://github.com/treeform/nimby-nim-builds/releases/download/{nimVersion}/nim-{nimVersion}-macOS-ARM64.tar.gz"
        print &"Downloading: {url}"
        runSafe(&"curl -sSL {url} -o nim.tar.gz")
        print "Extracting the Nim compiler"
        runSafe("tar xf nim.tar.gz --strip-components=1")

      elif defined(linux):
        when defined(arm64):
          let url = &"https://github.com/treeform/nimby-nim-builds/releases/download/{nimVersion}/nim-{nimVersion}-Linux-ARM64.tar.gz"
        else:
          let url = &"https://github.com/treeform/nimby-nim-builds/releases/download/{nimVersion}/nim-{nimVersion}-Linux-X64.tar.gz"
        print &"Downloading: {url}"
        runSafe(&"curl -sSL {url} -o nim.tar.gz")
        print "Extracting the Nim compiler"
        runSafe("tar xf nim.tar.gz --strip-components=1")

      else:
        nimbyQuit "Unsupported platform for Nim installation"

    setCurrentDir(previousDir)
    print &"Installed Nim {nimVersion} to: {installDir}"

  # copy nim-{nimVersion} to global nim directory
  let versionNimDir = nimbyDir / "nim-" & nimVersion
  let globalNimDir = nimbyDir / "nim"
  removeDir(globalNimDir)
  copyDir(versionNimDir, globalNimDir)
  print &"Copied {versionNimDir} to {globalNimDir}"

  when not defined(windows):
    # Make sure the Nim binary is executable.
    runSafe(&"chmod +x {globalNimDir}/bin/nim")

  # Tell the user a single PATH change they can run now.
  let pathEnv = getEnv("PATH")
  let binPath = nimbyDir / "nim" / "bin"
  info &"Checking if Nim is in the PATH: {pathEnv}"
  if not pathEnv.contains(binPath):
    print "Add Nim to your PATH for this session with one of:"
    when defined(windows):
      let winBin = (binPath.replace("/", "\\"))
      print &"$env:PATH = \"{winBin};$env:PATH\"   # PowerShell"
    else:
      print &"export PATH=\"{binPath}:$PATH\"      # bash/zsh"
      print &"fish_add_path {binPath}              # fish"

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
        print "Using global packages directory."
        global = true
        if not dirExists(getGlobalPackagesDir()):
          info &"Creating global packages directory: {getGlobalPackagesDir()}"
          createDir(getGlobalPackagesDir())
      of "source", "s":
        source = true
      else:
        print "Unknown option: " & key
        quit(1)
    of cmdEnd:
      assert(false) # cannot happen

  if not acquireGlobalLock():
    quit("Nimby is already running, delete ~/.nimby/nimbylock to release lock")

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
      nimbyQuit("Invalid command")

  releaseGlobalLock()
