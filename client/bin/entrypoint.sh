#!/bin/bash
set -x

# add koji-hub to hosts if not present
if [ -n "$KOJI_HUB" ]; then
    KOJI_HUB_IP=$(getent hosts $KOJI_HUB | awk '{ print $1 }')
    echo ${KOJI_HUB_IP} koji-hub >> /etc/hosts
fi

while true; do
	echo "Waiting for koji-hub to start..."
    hubstart=$(curl -X GET http://koji-hub/)
	echo $hubstart
	if [ "x$hubstart" != "x" ]; then
		echo "koji-hub started:"
	    break
	fi
	sleep 5
done

set -x

if [ -d /opt/koji/noarch ]; then
	yum -y localinstall /opt/koji/noarch/koji-1*.rpm
else
	echo "No koji RPM to install! Installing from EPEL"
	#already in docker file
#	yum -y install epel-release
	yum -y install koji
fi

mkdir /root/{.koji,bin}
echo "Generating user-specific koji client links and configs"
for userdir in $(ls -d /opt/koji-clients/*); do
	user=$(basename $userdir)
	echo "Adding: ${user} (${userdir})"

	cat <<EOF >> /root/.koji/config
[koji-${user}]
server = https://koji-hub/kojihub
authtype = ssl
cert = ${userdir}/client.crt
ca = ${userdir}/clientca.crt
serverca = ${userdir}/serverca.crt

EOF

	echo "Linking koji to: /root/bin/koji-${user}"
	ln -s /usr/bin/koji /root/bin/koji-${user}
done

echo "Generated configs are:"
cat /root/.koji/config

echo "Available user-specific koji commands are:"
ls -1 /root/bin/koji-*

ssh-keygen -t rsa -N '' -f /etc/ssh/ssh_host_rsa_key
ssh-keygen -t dsa -N '' -f /etc/ssh/ssh_host_dsa_key

IP=$(find-ip.py)

#echo "SSHd listening on: ${IP}:22"
#/usr/sbin/sshd -D

echo "Koji client environment started on ${IP}"
# This won't work in openshift
if [ -n "$KOJI_HUB" ]; then
	while true; do sleep 10000; done
else
	exec /bin/bash -l
fi

