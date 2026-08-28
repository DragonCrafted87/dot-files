#!/bin/ash
# shellcheck disable=SC2187,SC2016,SC2094,SC2164,SC2317

return
# apk add nano sudo git curl
# git clone https://github.com/DragonCrafted87/dot-files.git
# sudo nano /etc/passwd

mkdir /home/dragon/.ssh/
chmod 700 .ssh/
curl -0 https://github.com/dragoncrafted87.keys > /home/dragon/.ssh/authorized_keys


# Only allow key based logins
cd /tmp
sed -n 'H;${x;s/\#PasswordAuthentication yes/PasswordAuthentication no/;p;}' /etc/ssh/sshd_config > tmp_sshd_config
sed -n 'H;${x;s/\PasswordAuthentication yes/PasswordAuthentication no/;p;}' tmp_sshd_config > tmp_sshd_config
sudo mv tmp_sshd_config /etc/ssh/sshd_config

ln -s /home/dragon/dot-files/hw_bashrc.sh .bashrc
ln -s /home/dragon/dot-files/bashrc.d/ .bashrc.d
ln -s /home/dragon/dot-files/profile .profile

sudo sh -c 'echo "dragon ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers'
sudo rm /root/.bashrc
sudo ln -s /home/dragon/.bashrc /root/.bashrc
sudo ln -s /home/dragon/.bashrc.d/ /root/.bashrc.d
sudo timedatectl set-timezone America/Chicago
sudo ln -s /usr/bin/python3 /usr/bin/python
