Vagrant.configure(2) do |config|
  config.vm.box = "windows-2019-amd64"

  config.vm.provider "libvirt" do |lv, config|
    lv.memory = 2048
    lv.cpus = 2
    lv.cpu_mode = "host-passthrough"
    lv.nested = true
    lv.keymap = "pt"
    config.vm.synced_folder ".", "/vagrant", type: "smb", smb_username: ENV["USER"], smb_password: ENV["VAGRANT_SMB_PASSWORD"]
  end

  config.vm.provider "virtualbox" do |vb, config|
    vb.linked_clone = true
    vb.memory = 2048
    vb.cpus = 2
    vb.customize ["modifyvm", :id, "--vram", 256]
    vb.customize ["modifyvm", :id, "--accelerate3d", "on"]
    vb.customize ["modifyvm", :id, "--accelerate2dvideo", "on"]
    vb.customize ["modifyvm", :id, "--clipboard", "bidirectional"]
    vb.customize ["modifyvm", :id, "--draganddrop", "bidirectional"]
    vb.customize [
      "storageattach", :id,
      "--storagectl", "IDE Controller",
      "--device", 0,
      "--port", 1,
      "--type", "dvddrive",
      "--medium", "emptydrive"]
    audio_driver = case RUBY_PLATFORM
      when /linux/
        "alsa"
      when /darwin/
        "coreaudio"
      when /mswin|mingw|cygwin/
        "dsound"
      else
        raise "Unknown RUBY_PLATFORM=#{RUBY_PLATFORM}"
      end
    vb.customize ["modifyvm", :id, "--audio", audio_driver, "--audiocontroller", "hda"]
  end

  config.vm.provision "shell", inline: "$env:chocolateyVersion='0.10.13'; iwr https://chocolatey.org/install.ps1 -UseBasicParsing | iex", name: "Install Chocolatey"
  config.vm.provision "shell", path: "provision.ps1"
  config.vm.provision "shell", path: "provision-example-services.ps1"
  config.vm.provision "shell", inline: "echo 'Rebooting...'", reboot: true
end