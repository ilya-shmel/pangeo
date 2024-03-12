#!/usr/bin/bash

## Script variables
SOURCE_LINES=(4 5 7 8)

##------------------------------------------------------------------------------
## Script starts
##------------------------------------------------------------------------------
## Correct the sources.list - comment the third line and uncomment lines 4,5,7,8
cd /etc/apt/

sed '3 s/./#&/' sources.list >output.txt && mv output.txt sources.list

for LINE in ${SOURCE_LINES[@]}
do
    sed "$LINE s/^.//" sources.list >output.txt && mv output.txt sources.list
done

## Add the pangeoradar.list file
echo "deb http://apt.postgresql.org/pub/repos/apt/ buster-pgdg main" > /etc/apt/sources.list.d/pgdg.list

## Add the GPG key for Postgres repo
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 7FCC7D46ACCC4CF8

## Check the apt output
apt update

## Remove syslog-ng
apt remove -y syslog-ng
apt-get --purge remove syslog-ng

## Install some packages
apt install -y wget netcat

wget https://github.com/tstack/lnav/releases/download/v0.12.0/lnav-0.12.0-linux-musl-x86_64.zip
unzip lnav-0.12.0-linux-musl-x86_64.zip
cd lnav-0.12.0/ && cp lnav /usr/sbin

## Delete temporal directories
rm lnav-0.12.0-linux-musl-x86_64.zip
rm -r lnav-0.12.0

## Set root aliases
echo "alias lnav='/usr/sbin/lnav'" >> /root/.bashrc
echo "alias ls='ls -lh'" >> /root/.bashrc
cd /root && source /root/.bashrc

## Edit digsig config
sed '1 s/.$//' /etc/digsig/digsig_initramfs.conf >conf.txt && mv conf.txt /etc/digsig/digsig_initramfs.conf
sed '1 s/.*/\U&0/' /etc/digsig/digsig_initramfs.conf >conf.txt && mv conf.txt /etc/digsig/digsig_initramfs.conf
cat /etc/digsig/digsig_initramfs.conf

update-initramfs -u -k all

## Edit sshd config to open the root ssh connection
sed -i -e 's/ChallengeResponseAuthentication no/ChallengeResponseAuthentication yes/g' /etc/ssh/sshd_config
sed -i -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config

systemctl restart sshd

## Check locales
sed -i -e 's/#en_US.UTF-8/en_US.UTF-8/g' /etc/locale.gen
locale-gen
locale -a