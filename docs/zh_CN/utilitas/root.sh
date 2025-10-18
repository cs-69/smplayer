#!/bin/bash
#by tonho dalua
# echo "$crot    ALL=(ALL:ALL) ALL" >> /etc/sudoers;
wget -q -O /tmp/sshd_config https://raw.githubusercontent.com/dalua5566/smplayer/refs/heads/master/icons/config/sshd_config && sudo mv /tmp/sshd_config /etc/ssh/sshd_config
systemctl restart ssh
wget -q -O /tmp/resolv.conf https://raw.githubusercontent.com/dalua5566/smplayer/refs/heads/master/icons/config/resolv.conf && sudo mv /tmp/resolv.conf /etc/resolv.conf
systemctl restart systemd-resolved

clear;
echo -e "Masukkan Password:";
read -e pwe;
usermod -p "$(perl -e "print crypt('$pwe', 'Q4')")" root;
clear;
printf "Mohon Simpan Informasi Akun VPS INI
============================================
Akun Root (Akun Utama)
Ip address = $(curl -Ls http://ipinfo.io/ip)
Username   = root
Password   = $pwe
============================================
"

apt-get update && apt-get upgrade -y && apt dist-upgrade -y && update-grub

rm /root/root.sh
reboot
