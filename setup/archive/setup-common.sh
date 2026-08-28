#!/bin/bash
# shellcheck disable=SC2187,SC2016,SC2094,SC2164,SC2317

return


git clone https://github.com/DragonCrafted87/dot-files.git
rm .bashrc
rm .bashrc.d
ln -s /home/dragon/dot-files/hw_bashrc.sh .bashrc
ln -s /home/dragon/dot-files/bashrc.d/ .bashrc.d

sudo sh -c 'echo "dragon ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/dragon'
sudo rm /root/.bashrc
sudo ln -s /home/dragon/.bashrc /root/.bashrc
sudo ln -s /home/dragon/.bashrc.d/ /root/.bashrc.d
sudo timedatectl set-timezone America/Chicago
sudo ln -s /usr/bin/python3 /usr/bin/python

sudo apt autoremove --purge kubeadm  kubectl  kubelet
sudo apt autoremove --purge docker-ce docker-ce-cli containerd.io

sudo hostnamectl set-hostname rancher.lan

#add to root crontab
sudo crontab -e
# @reboot sudo swapoff -a
# also remove entry in /etc/fstab
sudo nano /etc/fstab

sudo apt update
sudo apt dist-upgrade -y

# do hw specific setup
