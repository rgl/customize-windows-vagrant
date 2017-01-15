# About

This shows ways to programmatically customize Windows 2016 through PowerShell. For example:

* Change the System Culture, Keyboard Layout and Time Zone.
* Change the Account Picture.
* Change the Desktop and Lock Screen background.
* Configure Explorer to show hidden and protected files.
* Configure the Taskbar.
* Create Desktop Shortcuts.
* Install Googe Chrome and Extensions.
* Replace notepad with [notepad2](http://www.flos-freeware.ch/notepad2.html).
* Replace the Start Menu with [Classic Shell](http://www.classicshell.net/).

For more customization options see [Disassembler0/Win10-Initial-Setup-Script/Win10.ps1](https://github.com/Disassembler0/Win10-Initial-Setup-Script/blob/master/Win10.ps1).

# Base Box

Install the [Windows 2016 Base Box](https://github.com/rgl/windows-2016-vagrant).

Install the needed plugins:

```bash
vagrant plugin install vagrant-reload # https://github.com/aidanns/vagrant-reload
```

Then start this environment:

```bash
vagrant up
```
