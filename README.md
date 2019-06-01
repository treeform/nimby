![Nimby Logo](docs/nimbyLogo.png)

# Nimby

Nimby is a very simple and unofficial package manager for nim language. It is a very stripped down package manager under 200 lines of code.

⚠️ Warning do not use in production. This is an idea-only software to spark converstions about packadge managers. ⚠️


## Install

`nimby install https://github.com/treeform/typography`

Nimby does these things during install:

* Uses git urls to install packages.
* Installs packages in local `libs` folder.
* Updates local `nim.cfg` to have the `--path:` entry.
* Updates the local `.nimby` file making the package a requirement.
* Optionally updates `.gitmodules` file if it exists.


`nimby install`

Nimby will read the local `.nimby` file and install all referenced libraries.


## Remove

`nimby remove typography`

Nimby will try to undo the steps done by install

* Use git url or the name of the library
* Removes the library from the `libs/` folder.
* Removes `--path:` entry from the local `nim.cfg`.
* Removes it from the local `.nimby` file.
* Removes it from the `.gitmodules` if it exists.


## .nimby file is just a json file

It has very simple structure. All fields are required.

```
{
  "name": "test",
  "version": "0.1.0",
  "author": "",
  "url": "",
  "requires": [
    {
      "name": "typography",
      "url": "https://github.com/treeform/typography",
      "version": ""
    }
  ]
}
```