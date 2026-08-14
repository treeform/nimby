import std/[os, osproc, strformat, strutils]

import testpackage

proc testGitConfig() =
  ## Checks that test Git settings do not alter the user configuration.
  let
    userConfigPath = expandTilde("~/.gitconfig")
    userConfigExisted = fileExists(userConfigPath)
    userConfigBefore =
      if userConfigExisted:
        readFile(userConfigPath)
      else:
        ""
    ciExisted = existsEnv("CI")
    ciBefore = getEnv("CI")
    globalConfigExisted = existsEnv("GIT_CONFIG_GLOBAL")
    globalConfigBefore = getEnv("GIT_CONFIG_GLOBAL")
    packageName = &"gitconfig_{getCurrentProcessId()}"
    packageDir = testPackagesDir / packageName

  putEnv("CI", "1")
  setupTestPackages()
  if ciExisted:
    putEnv("CI", ciBefore)
  else:
    delEnv("CI")

  doAssert existsEnv("GIT_CONFIG_GLOBAL") == globalConfigExisted
  doAssert getEnv("GIT_CONFIG_GLOBAL") == globalConfigBefore
  doAssert fileExists(userConfigPath) == userConfigExisted
  if userConfigExisted:
    doAssert readFile(userConfigPath) == userConfigBefore

  let
    (rewrites, rewritesCode) = execCmdEx(
      "git config --get-all url.https://github.com/.insteadOf"
    )
  doAssert rewritesCode == 0
  doAssert rewrites.contains("ssh://git@github.com/")
  doAssert rewrites.contains("git+ssh://git@github.com/")
  doAssert rewrites.contains("git@github.com:")

  if dirExists(packageDir):
    removeDir(packageDir)
  createTestPackage(packageName)
  let
    gitLogCommand = "git -C " & quoteShell(packageDir) &
      " log -1 --format='%an <%ae>'"
    (author, authorCode) = execCmdEx(gitLogCommand)
  doAssert authorCode == 0
  doAssert author.strip == "Tests <git@tests.com>"
  removeDir(packageDir)

  doAssert fileExists(userConfigPath) == userConfigExisted
  if userConfigExisted:
    doAssert readFile(userConfigPath) == userConfigBefore

echo "Testing isolated Git configuration"
testGitConfig()
