#!/bin/bash
# shellcheck disable=SC2187,SC2016,SC2094,SC2164,SC2317

return

git clone git@github.com:DragonCrafted87/dot-files.git
rm -rf .bashrc
rm -rf .bashrc.d
ln -s /home/dragon/dot-files/wsl_bashrc.sh .bashrc
ln -s /home/dragon/dot-files/bashrc.d/ .bashrc.d

sudo sh -c 'echo "dragon ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers'
sudo rm /root/.bashrc
sudo ln -s /home/dragon/.bashrc /root/.bashrc
sudo ln -s /home/dragon/.bashrc.d/ /root/.bashrc.d

# sudo apt install cifs-utils
#
#  # Helm Install
#  curl https://helm.baltorepo.com/organization/signing.asc | sudo apt-key add -
#  sudo apt-get install apt-transport-https --yes
#  echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
#  sudo apt-get update
#  sudo apt-get install helm
#

sudo apt-get update && sudo apt-get install -y apt-transport-https gnupg2 curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl
