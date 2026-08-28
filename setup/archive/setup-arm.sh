#!/bin/bash
# shellcheck disable=SC2086,SC2093,SC2016,SC2094,SC2164,SC2317

return

#ssh keys
curl -0 https://github.com/dragoncrafted87.keys > .ssh/authorized_keys

# Only allow key based logins
cd /tmp
sed -n 'H;${x;s/\#PasswordAuthentication yes/PasswordAuthentication no/;p;}' /etc/ssh/sshd_config > tmp_sshd_config
sed -n 'H;${x;s/\PasswordAuthentication yes/PasswordAuthentication no/;p;}' tmp_sshd_config > tmp_sshd_config
sudo mv tmp_sshd_config /etc/ssh/sshd_config

#hostname
sudo hostnamectl set-hostname arm64node1.lan

exec sudo -i
function replace-user ()
{
  killall -u $1
  id $1
  usermod -l $2 $1
  groupmod -n $2 $1
  usermod -d /home/$2 -m $2
  usermod -c $3 $2
  id $2
}
replace-user ubuntu dragon 'Scott Gudeman'



# microk8s setup
sudo nano /boot/firmware/cmdline.txt
# insert at start of line: cgroup_enable=memory cgroup_memory=1

sudo reboot
