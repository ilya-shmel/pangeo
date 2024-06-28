#!/bin/bash
#set -e -o pipefail

## Check the script name
if [ -z ${TRYLAUNCH} ] ; then
  echo "USE install.sh ONLY!"
  exit 1
fi

# platform installation check
if ! [[ -d /opt/pangeoradar/ ]];
then
  echo "Устaновленная Платформа Радар не обнаружена! Процесс обновления прерван!"
  exit
fi



# unpack dependencies archive to the folder named after release version
RELEASE_VERSION=$(<scripts/VERSION)
UPDATE_PACKAGES_DIR=/opt/pangeoradar/updates/$RELEASE_VERSION
CONFIGS_DIR=/opt/pangeoradar/configs
PACKAGES_DIR=/opt/pangeoradar/distrs/
CURRENT_VERSION=`apt list --installed | grep pangeoradar-ui | egrep -o '[0-9].*[0-9]' | cut -b 1-5`

# Show only the first two numbers of the current version
CURRENT_VERSION_CUTTED=$(apt-cache show pangeoradar-cluster-manager | grep 'Version' | awk '{print $2}' | cut -d. -f1,2)
# Show only the first two numbers of the release version
RELEASE_VERSION_CUTTED=$(grep -oP '\b\d+\.\d+' VERSION)

# create "UPDATE_TERMITE_PROPS" variable
if [ "$CURRENT_VERSION_CUTTED" == "3.6" ] && [ "$RELEASE_VERSION_CUTTED" != "3.6" ];
then
  UPDATE_TERMITE_PROPS=true
else
  UPDATE_TERMITE_PROPS=false
fi

currentPath=`pwd`


LOG_FILE="/opt/pangeoradar/update_$RELEASE_VERSION.log"
LOG_PIPE=/var/tmp/uplog
mknod $LOG_PIPE p
exec 3>&1
tee $LOG_FILE <$LOG_PIPE &
exec 1>$LOG_PIPE

# fix apt for some cases
apt --fix-broken install -y
apt autoremove -y

echo "Распаковка архивов обновления..."
mkdir -p $UPDATE_PACKAGES_DIR
tar zxf dependencies.tar.gz -C $UPDATE_PACKAGES_DIR

# clean distrs dir and copy updated ones
rm -rf $PACKAGES_DIR/*
cp -rf $UPDATE_PACKAGES_DIR/* $PACKAGES_DIR/

# create configs backup
mkdir -p $UPDATE_PACKAGES_DIR/previous_configs
cp -rf $CONFIGS_DIR/* $UPDATE_PACKAGES_DIR/previous_configs

# add pgr repository on master

rm -rf /opt/pangeoradar/repository
mkdir -p /opt/pangeoradar/repository


REPO_DIR=/opt/pangeoradar/repository


tar -xzf repository.tar.gz -C "$REPO_DIR"
#unzip -o rbenv.zip -d /

IP=`ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1`
echo ""$IP"       master" >> /etc/hosts

cp /opt/pangeoradar/certs/pgr.crt /usr/local/share/ca-certificates/
update-ca-certificates


echo -n "server {
      listen 4443 ssl;
      listen [::]:4443 ssl;

      server_name localhost;
      root /opt/pangeoradar/repository/;
      allow all;
      autoindex on;
      autoindex_localtime on;
      ssl on;
      ssl_protocols TLSv1.2 TLSv1.3;
      ssl_prefer_server_ciphers on;
      ssl_certificate /opt/pangeoradar/certs/pgr.crt;
      ssl_certificate_key /opt/pangeoradar/certs/pgr.key;
  }
" > /opt/pangeoradar/configs/repository.nginx

ln -sf /opt/pangeoradar/configs/repository.nginx /etc/nginx/sites-enabled/repository.nginx

systemctl restart nginx

cp /etc/apt/sources.list /etc/apt/sources.list.bak

echo -n "deb [trusted=yes] https://"$IP":4443 buster main

" >  /etc/apt/sources.list

apt update

apt install -y apache2-utils openssl

chmod 755 $REPO_DIR/key.gpg
apt-key add $REPO_DIR/key.gpg


# secure repo with a password
REPO_PASS=`openssl rand -base64 30`
mkdir -p /etc/apache2/
htpasswd -bmc /etc/apache2/.htpasswd pgr_repo_user "$REPO_PASS"

echo -n "machine "$IP"
login pgr_repo_user
password "$REPO_PASS"

"> /etc/apt/auth.conf.d/pgr_repo.conf

echo -n "server {
      listen 4443 ssl;
      listen [::]:4443 ssl;

      server_name localhost;
      root /opt/pangeoradar/repository/;
      auth_basic           \"Resticted area\";
      auth_basic_user_file /etc/apache2/.htpasswd;
      allow all;
      autoindex on;
      autoindex_localtime on;
      ssl on;
      ssl_protocols TLSv1.2 TLSv1.3;
      ssl_prefer_server_ciphers on;
      ssl_certificate /opt/pangeoradar/certs/pgr.crt;
      ssl_certificate_key /opt/pangeoradar/certs/pgr.key;
  }
" > /opt/pangeoradar/configs/repository.nginx


systemctl restart nginx

ufw allow 4443
echo "y" | ufw enable
ufw status

# remove old eventant and install a new one (update 3.5)
apt remove pangeoradar-eventant -y
rm -rf /opt/pangeoradar/eventant/
rm -rf /opt/pangeoradar/configs/eventant
echo "Y" | apt install -f $UPDATE_PACKAGES_DIR/pangeoradar-eventant/*.deb

# save termite content if master has termite service dir
if [ "$UPDATE_TERMITE_PROPS" = true ] && [ -d "/opt/pangeoradar/configs/termite/" ];
then
  . scripts/termite_content_save.sh
fi

# update packages on master keeping current config files, restore nginx configs
echo "Y" | apt install -f --only-upgrade -o Dpkg::Options::='--force-confold' $UPDATE_PACKAGES_DIR/pangeoradar-*/*.deb
cp -rf $UPDATE_PACKAGES_DIR/previous_configs/*.nginx $CONFIGS_DIR/ && systemctl restart nginx

# load saved termite content
if [ "$UPDATE_TERMITE_PROPS" = true ] && [ -d "/opt/pangeoradar/configs/termite/" ];
then
  . scripts/termite_content_load.sh
fi

# replace cluster agent with a new version
rm -rf /opt/pangeoradar/distrs/pangeoradar-cluster-agent/*
cp $UPDATE_PACKAGES_DIR/pangeoradar-cluster-agent/* /opt/pangeoradar/distrs/pangeoradar-cluster-agent/
ln -sfr $(find $PACKAGES_DIR/pangeoradar-cluster-agent/ -name "*cluster-agent*" -printf '%T@ %p\n' | sort -n | tail -1| cut -f2- -d" ") $PACKAGES_DIR/pangeoradar-cluster-agent_amd64.deb

#FIX node_roles
echo -n "DELETE FROM node_roles WHERE node_id not in (SELECT id from nodes)" | sudo -u postgres psql -t pgr_cm 2>/dev/null

# discover remote nodes IP
NODES_IP=`echo -n "select ip from nodes where ip not in (SELECT distinct ip FROM nodes INNER JOIN node_roles nr on nodes.id = nr.node_id INNER JOIN roles r on nr.role_id = r.id WHERE r.name in ('agent_win', 'master'))" | sudo -u postgres psql -t pgr_cm 2>/dev/null | awk '{ print $1 }'`
# check for distributed installation
NODES_COUNT=`echo $NODES_IP | wc -w`

if [ "$NODES_COUNT" -gt 0 ];
then

  # copy dependencies to the remote nodes, create configs backup
  for NODE_IP in $NODES_IP; do
    echo "Загружаются файлы обновления на ноду $NODE_IP"
    ssh root@$NODE_IP "mkdir -p $UPDATE_PACKAGES_DIR"
    scp dependencies.tar.gz root@$NODE_IP:$UPDATE_PACKAGES_DIR
    scp $REPO_DIR/key.gpg root@$NODE_IP:/opt/pangeoradar/
    scp /etc/apt/auth.conf.d/pgr_repo.conf root@$NODE_IP:/etc/apt/auth.conf.d/
    scp /etc/apt/sources.list root@$NODE_IP:/etc/apt/
    ssh root@$NODE_IP "tar zxvf $UPDATE_PACKAGES_DIR/dependencies.tar.gz -C $UPDATE_PACKAGES_DIR"
    ssh root@$NODE_IP "mkdir -p $UPDATE_PACKAGES_DIR/previous_configs && cp -rf $CONFIGS_DIR/* $UPDATE_PACKAGES_DIR/previous_configs"
    ssh root@$NODE_IP "rm -rf $PACKAGES_DIR/* && cp -rf $UPDATE_PACKAGES_DIR/* $PACKAGES_DIR/"

    # save termite content if node has termite service dir
    if [ "$UPDATE_TERMITE_PROPS" = true ] && ssh root@$NODE_IP "[ -d /opt/pangeoradar/configs/termite/ ]";
    then
      ssh root@$NODE_IP "export RELEASE_VERSION=$RELEASE_VERSION && bash -s" < scripts/termite_content_save.sh
    fi
  done

  # update packages on the remote nodes keeping current config files, restore nginx configs


  echo "Выключаю Beaver"
  for NODE_IP in $NODES_IP; do
    ssh root@$NODE_IP "export UPDATE_PACKAGES_DIR=$UPDATE_PACKAGES_DIR && export PACKAGES_DIR=$PACKAGES_DIR && bash -s" < scripts/stop_beaver.sh
  done

  for NODE_IP in $NODES_IP; do
    echo "Обновляется нода $NODE_IP"

    ssh root@$NODE_IP "apt-key add /opt/pangeoradar/key.gpg"
    ssh root@$NODE_IP "echo "Y" | apt install -f --only-upgrade -o Dpkg::Options::='--force-confold' $UPDATE_PACKAGES_DIR/pangeoradar-*/*.deb"
    ssh root@$NODE_IP "cp -rf $UPDATE_PACKAGES_DIR/previous_configs/*.nginx $CONFIGS_DIR/ &&  systemctl restart nginx"

    ssh root@$NODE_IP "export UPDATE_PACKAGES_DIR=$UPDATE_PACKAGES_DIR && export PACKAGES_DIR=$PACKAGES_DIR && bash -s" < scripts/stop_beaver.sh
    ssh root@$NODE_IP "export UPDATE_PACKAGES_DIR=$UPDATE_PACKAGES_DIR && export PACKAGES_DIR=$PACKAGES_DIR && bash -s" < scripts/update_logmule.sh
    ssh root@$NODE_IP "if apt list --installed | grep -Fq 'grafana'; then echo "Y" | apt install -f --only-upgrade -o Dpkg::Options::='--force-confold' grafana; fi"
    ssh root@$NODE_IP "export UPDATE_PACKAGES_DIR=$UPDATE_PACKAGES_DIR && export PACKAGES_DIR=$PACKAGES_DIR && bash -s" < scripts/update_es_to_os.sh

    # load saved termite content
    if [ "$UPDATE_TERMITE_PROPS" = true ] && ssh root@$NODE_IP "[ -d /opt/pangeoradar/configs/termite/ ]";
    then
      ssh root@$NODE_IP "export RELEASE_VERSION=$RELEASE_VERSION && bash -s" < scripts/termite_content_load.sh
    fi
  done
  echo "Включаю Beaver"
  for NODE_IP in $NODES_IP; do
    ssh root@$NODE_IP "export UPDATE_PACKAGES_DIR=$UPDATE_PACKAGES_DIR && export PACKAGES_DIR=$PACKAGES_DIR && bash -s" < scripts/start_beaver.sh
  done

fi

if apt list --installed | grep -Fq 'rvsapi';
    then
    apt remove pangeoradar-rvsapi --purge -y
fi

if apt list --installed | grep -wiq "pangeoradar-ui4";
then
  echo "UI4 Installed"
else
  dpkg -R --install "$UPDATE_PACKAGES_DIR"/pangeoradar-ui4/
fi


# pslq migrations
cd /opt/pangeoradar/bin
./pangeoradar-cluster-manager --migrate --config=/opt/pangeoradar/configs/

cd $currentPath

# update configs
#echo -n "installed flag" > /opt/pangeoradar/bin/system_installed
systemctl restart pangeoradar-cluster-manager

. scripts/stop_beaver.sh
. scripts/update_logmule.sh
. scripts/update_es_to_os.sh
. scripts/start_beaver.sh

sleep 20s
systemctl restart pangeoradar-karaken
systemctl restart pangeoradar-datasapi


sleep 120s

service nginx restart

sleep 20s


dpkg -R --install "$UPDATE_PACKAGES_DIR"/expert-packs/


echo "Обновление завершено!"

exec 1>&3
exec 3>&-
rm -rf $LOG_PIPE