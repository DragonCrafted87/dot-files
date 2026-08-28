#!/bin/bash
# shellcheck disable=SC2187,SC2016,SC2094,SC2164,SC2317

return

sudo apt install git curl ssh
git config --global pull.rebase false

#ssh keys
curl -0 https://github.com/dragoncrafted87.keys > .ssh/authorized_keys

git clone https://github.com/DragonCrafted87/dot-files.git
rm .bashrc
rm .bashrc.d
ln -s /home/dragon/dot-files/media_bashrc.sh .bashrc
ln -s /home/dragon/dot-files/bashrc.d/ .bashrc.d

sudo sh -c 'echo "dragon ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/sudoers'
sudo rm /root/.bashrc
sudo ln -s /home/dragon/.bashrc /root/.bashrc
sudo ln -s /home/dragon/.bashrc.d/ /root/.bashrc.d
sudo timedatectl set-timezone America/Chicago
sudo ln -s /usr/bin/python3 /usr/bin/python

sudo hostnamectl set-hostname medialivingroom.lan

reboot

sudo apt install x11vnc net-tools

sudo mkdir /usr/share/wayland-sessions/hidden
sudo dpkg-divert --rename \
      --divert /usr/share/wayland-sessions/hidden/ubuntu.desktop \
      --add /usr/share/wayland-sessions/ubuntu.desktop

sudo apt install software-properties-common
sudo add-apt-repository -ysP team-xbmc/ppa
sudo apt install kodi

sudo apt install kodi-visualization-goom kodi-visualization-projectm kodi-visualization-shadertoy kodi-visualization-spectrum kodi-visualization-waveform xbmc-visualization-fishbmc
