#!/bin/bash
# shellcheck disable=SC2187,SC2016,SC2094,SC2164,SC2317

return


sudo wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /bin/oh-my-posh
sudo chmod +x /bin/oh-my-posh















#create mount directories
sudo mkdir /mnt/staging_area

sudo mkdir /mnt/enclosure1_drive1
sudo mkdir /mnt/enclosure1_drive2
sudo mkdir /mnt/enclosure1_drive3
sudo mkdir /mnt/enclosure1_drive4
sudo mkdir /mnt/enclosure1_drive5
sudo mkdir /mnt/enclosure1_drive6
sudo mkdir /mnt/enclosure1_drive7
sudo mkdir /mnt/enclosure1_drive8

sudo mkdir /mnt/enclosure2_drive1
sudo mkdir /mnt/enclosure2_drive2
sudo mkdir /mnt/enclosure2_drive3
sudo mkdir /mnt/enclosure2_drive4
sudo mkdir /mnt/enclosure2_drive5

## Storage Drives
#UUID=55d7e772-35b4-4367-b8ec-beba0d156493 /mnt/staging_area ext4 defaults,noatime,nofail 0 0
#
## Enclosure 1
#UUID=3b114c6c-5b25-4743-9790-7caebc49acfc /mnt/enclosure1_drive1 ext4 defaults,noatime,nofail 0 0
#UUID=9847d647-c680-4698-a1aa-40c37b5c591a /mnt/enclosure1_drive2 ext4 defaults,noatime,nofail 0 0
#UUID=fb2b72e6-e109-4fae-9b4d-719a2c88afdb /mnt/enclosure1_drive3 ext4 defaults,noatime,nofail 0 0
#UUID=d5ba4935-f296-4179-a20b-28fb842be89e /mnt/enclosure1_drive4 ext4 defaults,noatime,nofail 0 0
## UUID=A81EB8EE1EB8B722 /mnt/enclosure1_drive5 ntfs defaults 0 0
## UUID=3A8A9C448A9BFA99 /mnt/enclosure1_drive6 ntfs defaults 0 0
## UUID=D2AE99F9AE99D677 /mnt/enclosure1_drive7 ntfs defaults 0 0
#UUID=c262e8eb-f9bf-45ff-ad88-5c957c6ae306 /mnt/enclosure1_drive8 ext4 defaults,noatime,nofail 0 0
#
## Enclosure 2
#UUID=105ee73f-02ee-4585-a70f-9fca87ebb06b /mnt/enclosure2_drive1 ext4 defaults,noatime,nofail 0 0
#UUID=3eb0d3d1-c17a-4487-8bb7-95d7070becbb /mnt/enclosure2_drive2 ext4 defaults,noatime,nofail 0 0
#UUID=c12da01f-3c77-465d-bdf5-2451d2940afb /mnt/enclosure2_drive3 ext4 defaults,noatime,nofail 0 0
#UUID=302e14eb-1af6-40c7-a7ba-c2548f29b3d6 /mnt/enclosure2_drive4 ext4 defaults,noatime,nofail 0 0
#UUID=e067e8a1-880a-417b-ac2f-0d634dd2e5d4 /mnt/enclosure2_drive5 ext4 defaults,noatime,nofail 0 0
