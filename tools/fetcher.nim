import
  std/[strformat, strutils, os, json, base64, times],
  curly, jsony

let githubToken = block:
  let tokenPath = expandTilde("~/.github_token")
  if fileExists(tokenPath):
    readFile(tokenPath).strip()
  else:
    quit("GitHub token not found")

let curl = newCurly() # Best to start with a single long-lived instance

proc githubHeaders(token: string): HttpHeaders =
  var headers: HttpHeaders
  headers["Accept"] = "application/vnd.github+json"
  headers["X-GitHub-Api-Version"] = "2022-11-28"
  headers["User-Agent"] = "nimby-fetcher/1.0"
  if token.len > 0:
    headers["Authorization"] = "Bearer " & token
  headers

proc extractQuotedStrings(line: string): seq[string] =
  var i = 0
  while i < line.len:
    let start = line.find('"', i)
    if start < 0: break
    let stop = line.find('"', start + 1)
    if stop < 0: break
    result.add line[(start + 1) ..< stop]
    i = stop + 1

type RequireEntry = tuple[name: string, op: string, version: string]

proc parseRequires(nimbleText: string): seq[RequireEntry] =
  var inArray = false
  for raw in nimbleText.splitLines():
    let line = raw.strip()
    if not inArray:
      if line.startsWith("requires "):
        for q in extractQuotedStrings(line):
          let parts = q.splitWhitespace()
          if parts.len >= 3:
            result.add (parts[0], parts[1], parts[2].strip(chars = {'"', ',', ')'}))
          elif parts.len == 1:
            result.add (parts[0], "", "")
        if line.contains("@[") and not line.contains("]"):
          inArray = true
    else:
      for q in extractQuotedStrings(line):
        let parts = q.splitWhitespace()
        if parts.len >= 3:
          result.add (parts[0], parts[1], parts[2].strip(chars = {'"', ',', ')'}))
        elif parts.len == 1:
          result.add (parts[0], "", "")
      if line.contains("]"):
        inArray = false

type GlobalPackage = ref object
  name: string
  url: string
  `method`: string
  tags: seq[string]
  description: string
  license: string
  web: string
  doc: string

var packages: seq[GlobalPackage]

proc findGlobalPackage(name: string): GlobalPackage =
  for package in packages:
    if package.name == name:
      return package
  return nil

proc fetchGlobalPackages() =
  let url = "https://raw.githubusercontent.com/nim-lang/packages/master/packages.json"
  let response = curl.get(url)
  if response.code == 200:
    packages = fromJson(response.body, seq[GlobalPackage])
    echo "Fetched ", packages.len, " global packages"
  else:
    echo response.code
    echo response.body

proc fetchZip(owner: string, name: string, tag: string, indent: string = "") =
  if not fileExists(&"packages/{name}/{tag}/{name}.zip"):
    echo "  Downloading: ", &"https://github.com/{owner}/{name}/archive/{tag}.zip"
    let response = curl.get(&"https://github.com/{owner}/{name}/archive/{tag}.zip")
    if response.code == 200:
      writeFile(&"packages/{name}/{tag}/{name}.zip", response.body)
    else:
      echo "  Failed to download: ", &"https://github.com/{owner}/{name}/archive/{tag}.zip"
      echo "  " & $response.code

proc fetchNimble(owner: string, name: string, tag: string, indent: string = "") =
  var nimbleName = name
  nimbleName.removePrefix("nim-")
  let nimblePath = &"packages/{name}/{tag}/{nimbleName}.nimble"
  if fileExists(nimblePath):
    echo "  Nimble file already exists: ", nimblePath
    return
  let url = &"https://raw.githubusercontent.com/{owner}/{name}/{tag}/{nimbleName}.nimble"
  let response = curl.get(url, githubHeaders(githubToken))
  if response.code == 200:
    writeFile(nimblePath, response.body)
    for req in parseRequires(response.body):
      echo &"{indent}  {req.name} {req.op} {req.version}"
      # let package = findGlobalPackage(req.name)
      # if package == nil:
      #   echo "Package not found: ", req.name
      #   continue
      # if package.`method` != "git":
      #   echo "Package is not a git repository: ", req.name
      #   continue
      # if not package.url.startsWith("https://github.com/"):
      #   echo "Package is not a GitHub repository: ", req.name
      #   continue
      # fetchNimble(owner, package.name, tag, indent & "  ")
      # fetchZip(owner, name, tag, indent & "  ")
  else:
    echo indent & "  " & $response.code

proc fetchTags(owner: string, package: string, indent: string = "") =
  let url = &"https://api.github.com/repos/{owner}/{package}/tags?per_page=100"
  let response = curl.get(url, githubHeaders(githubToken))
  if response.code == 200:
    let arr = parseJson(response.body)
    echo &"{indent}{package} tags:"
    var numTags = 0
    for item in arr.items:
      let tag = item["name"].getStr
      echo &"{indent}  {tag}"
      createDir(&"packages/{package}/{tag}")
      fetchNimble(owner, package, tag, indent & "  ")
      inc numTags
      if numTags > 4:
        break
  else:
    echo indent & "  " & $response.code

  createDir("packages/" & package)
  writeFile("packages/" & package & "/fetch_time.txt", $epochTime())

proc fetchStars(owner: string, name: string): int =
  if fileExists(&"packages/{name}/stars.txt"):
    return parseInt(readFile(&"packages/{name}/stars.txt").strip())
  let url = &"https://api.github.com/repos/{owner}/{name}/stargazers?per_page=100"
  let response = curl.get(url, githubHeaders(githubToken))
  if response.code == 200:
    return fromJson(response.body).len
  else:
    return 0

proc fetchPackage(package: GlobalPackage, verbose: bool = false) =
  
  if verbose: echo "Fetching: ", package.url

  if package.`method` != "git":
    if verbose: echo "  Package is not a git repository: ", package.name
    return

  if not package.url.startsWith("https://github.com/"):
    if verbose: echo "  Package is not a GitHub repository: ", package.name
    return

  if package.url.contains("?"):
    if verbose: echo "  Package has a query string: ", package.name
    return

  var
    arr = package.url.split("/")
    owner = arr[3]
    name = arr[4].toLowerAscii()

  # if name == "about":
  #   echo "  Skipping: ", package.name
  #   echo "  Invalid name?"
  #   return

  createDir(&"packages/{name}")

  # if fileExists(&"packages/{name}/fetch_time.txt"):
  #   let fetchTime = parseFloat(readFile(&"packages/{name}/fetch_time.txt").strip())
  #   if fetchTime - epochTime() < 0:
  #     if verbose: echo "  Skipping, just fetched: ", package.name
  #     return
  let now = epochTime()
  writeFile(&"packages/{name}/fetch_time.txt", $now)

  let stars = fetchStars(owner, name)
  writeFile(&"packages/{name}/stars.txt", $stars)
  echo "  Stars: ", stars
  if stars < 1:
    if verbose: echo "  Skipping: ", package.name 
    return

  echo "Fetching: ", package.url

  fetchTags(owner, name, "  ")

fetchGlobalPackages()

for i, package in packages:
  fetchPackage(package, verbose = false)
  if i mod 10 == 0:
    echo i, "/", packages.len

