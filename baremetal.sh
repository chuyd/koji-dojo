#!/bin/bash

yum install -y epel-release
yum install -y git docker koji koji-builder koji-utils

curl -L "https://github.com/docker/compose/releases/download/1.22.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod a+x /usr/local/bin/docker-compose

mkdir koji
cd koji

systemctl enable docker
systemctl start docker

git clone https://github.com/chuyd/koji-dojo.git -b baremetal
cd koji-dojo

/usr/local/bin/docker-compose build
echo 172.17.0.3 koji-hub | sudo tee -a /etc/hosts
systemctl restart docker
/usr/local/bin/docker-compose build
/usr/local/bin/docker-compose up -d
while [ ! -e /opt/koji-clients/kojibuilder/serverca.crt ]; do
	echo "Waiting for certificates"
        sleep 1;
done

cp /opt/koji-clients/kojibuilder/client.crt /etc/kojid/kojibuilder.crt
cp /opt/koji-clients/kojibuilder/clientca.crt  /etc/kojid/koji_client_ca_cert.crt
cp /opt/koji-clients/kojibuilder/serverca.crt /etc/kojid/koji_server_ca_cert.crt

cp /opt/koji-clients/kojira/client.crt /etc/kojira/kojira.crt
cp /opt/koji-clients/kojira/clientca.crt  /etc/kojira/kojira_client_ca_cert.crt
cp /opt/koji-clients/kojira/serverca.crt /etc/kojira/kojira_server_ca_cert.crt

cp /etc/kojid/kojid.conf /etc/kojid/kojid.conf.example
cat <<EOF >> /etc/kojid/kojid.conf
allowed_scms=github.com:/*:no
server=http://koji-hub/kojihub
user = kojibuilder
topurl=http://koji-hub/kojifiles
workdir=/tmp/koji
cert = /etc/kojid/kojibuilder.crt
ca = /etc/kojid/koji_client_ca_cert.crt
serverca = /etc/kojid/koji_server_ca_cert.crt
EOF

cat <<EOF >> /etc/kojira/kojira.conf
server=http://koji-hub/kojihub
cert = /etc/kojira/kojira.crt
ca = /etc/kojira/kojira_client_ca_cert.cr
serverca = /etc/kojira/kojira_server_ca_cert.crt
EOF

SECONDS=0
while ! koji -c /opt/koji-clients/kojiadmin/config hello &>/dev/null; do
	echo "Waiting koji to initialize"
	sleep 5
	if [ $SECONDS -gt  1200 ]; then
		echo "Failure installing koji, observe the docker logs"
		break
	fi
done

cp /opt/koji-clients/kojiadmin/config /etc/koji.conf
koji -c /opt/koji-clients/kojiadmin/config add-host kojibuilder x86_64
koji -c /opt/koji-clients/kojiadmin/config add-host-to-channel kojibuilder createrepo
koji -c /opt/koji-clients/kojiadmin/config add-user kojira
koji -c /opt/koji-clients/kojiadmin/config grant-permission repo kojira

systemctl start kojid
systemctl start kojira
