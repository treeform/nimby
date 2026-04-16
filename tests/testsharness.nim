import os, osproc, strformat, strutils

let testWorkspace* = getTempDir() / "nimby_tests"

proc cmd*(command: string): string {.discardable.} =
  echo "  > ", command
  let (output, exitCode) = execCmdEx(command, workingDir = testWorkspace)
  result = output
  echo output.indent(4)

  if exitCode != 0:
    raise newException(Exception, &"Command failed: {exitCode}")

template suite*(suitDescription: string, body: untyped) {.dirty.} =
  template setup(setupBody: untyped) {.dirty, used, redefine.} =
    template setupImplementation: untyped {.dirty, redefine.} = setupBody

  template teardown(teardownBody: untyped) {.dirty, used, redefine.} =
    template teardownImplementation: untyped {.dirty, redefine.} = teardownBody

  template test(testDescription: string, testBody: untyped) {.dirty, used, redefine.} =
    when compiles(setupImplementation()): setupImplementation()
    try:
      testBody
      stdout.write("  [OK] ")
      echo testDescription
    except AssertionDefect as e:
      echo e.msg
      stdout.write("  [FAILED] ")
      echo testDescription
      programResult = 1
    except Exception as e:
      echo e.msg
      stdout.write("  [FAILED] ")
      echo testDescription
      programResult = 1
    when compiles(teardownImplementation()): teardownImplementation()

  template skip(testDescription: string, testBody: untyped) {.dirty, used, redefine.} =
    discard

  stdout.write("[Suit] ")
  echo suitDescription
  body
