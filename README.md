# About

This shows ways to programmatically customize Windows through PowerShell. For example:

* Change the System Culture, Keyboard Layout and Time Zone.
* Change the Account Picture.
* Change the Desktop and Lock Screen background.
* Configure Explorer to show hidden and protected files.
* Configure the Taskbar.
* Create Desktop Shortcuts.
* Install Googe Chrome and Extensions.
* Replace notepad with [notepad2](http://www.flos-freeware.ch/notepad2.html).
* Replace the Start Menu with [Classic Shell](http://www.classicshell.net/).


# Base Box

Build the base box with:

```bash
git clone https://github.com/joefitzgerald/packer-windows
cd packer-windows
# this will take ages so leave it running over night...
packer build windows_2012_r2.json
vagrant box add windows_2012_r2 windows_2012_r2_virtualbox.box
rm *.box
cd ..
```

Install the needed plugins:

```bash
vagrant plugin install vagrant-reload # https://github.com/aidanns/vagrant-reload 
```

Then start this environment:

```bash
vagrant up
``` 
