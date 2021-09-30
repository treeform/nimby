![Nimby Logo](docs/nimbyLogo.png)

# Nimby

`nimble install nimby`

![Github Actions](https://github.com/treeform/nimby/workflows/Github%20Actions/badge.svg)

[API reference](https://nimdocs.com/treeform/nimby)

This library has no dependencies other than the Nim standard libarary.

## About

Nimby is a very simple tool to help with managing many Nim packages. If you have a ton of packages you are working on, this tool can help to keep everything up to date. This is an alternative to vendoring everything in git submodules.

```
nimby - manage a large collection of nimble packages in development
  - list       list all Nim packages in the current directory
  - develop    make sure all packages are linked with nimble
  - pull       pull all updates to packages from with git
  - tag        create a git tag for all pacakges if needed
```
