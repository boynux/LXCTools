BASEDIR="/var/lib/lxc"
IMAGESDIR="$BASEDIR/images"

function is_container_exists {
    if [[ ! -z $(sudo lxc-ls $1) ]]; then
        return 0
    else
        return 1
    fi
}

function is_template_exists {
    sudo file "$IMAGESDIR/$1.sqfs" > /dev/null 2>&1

    return $?
}

function is_container_active {
    local ACTIVE=`sudo lxc-ls --active | grep -E "(^| )$1( |$)"`

    if [[ -z "$ACTIVE" ]]; then
        return 1
    else
        return 0
    fi
}

function get_container_dns_ip {
    IP=$(host $(echo $1 | sed 's/\.lxc$//g'). 10.0.3.1 | grep "^$1" | tail -1 | awk '{print $NF}')

    if [[ "$?" -eq "0" ]]; then
        echo "$IP"
    else
        exit 1
    fi
}

function get_host_ip {
	HOST=$(/sbin/ifconfig eth0 2>/dev/null | grep "inet addr" | awk -F: '{print $2}' | awk '{print $1}')
	
	if [[ -z $HOST ]] 
	then
		HOST=$(/sbin/ifconfig wlan0 | grep "inet addr" | awk -F: '{print $2}' | awk '{print $1}')
	fi

    echo "$HOST"
}

function do_ssh {
	IP=$1
	USER=$2

	if [ -a .lxc/unsecure-private-key ]; then
		echo 'SSH Using own key.'
		exec ssh -A -i .lxc/unsecure-private-key ${USER}@${IP}
	else
		exec ssh -A ${USER}@${IP}
	fi
}

function mount_image {
	CONTAINER=$1
	IAMGE=$(sudo file /var/lib/lxc/images/${CONTAINER}.sqfs)

	if [ $? -eq 0 ]; then
		sudo mount -oloop,ro /var/lib/lxc/images/${CONTAINER}.sqfs /var/lib/lxc/${CONTAINER}/rootfs.ro
		sudo mount -t aufs -o br:/var/lib/lxc/${CONTAINER}/rootfs.rw=rw:/var/lib/lxc/${CONTAINER}/rootfs.ro=ro,xino=/dev/shm/${CONTAINER}.xino none /var/lib/lxc/${CONTAINER}/rootfs
	fi
}

function start_container {
	CONTAINER=$1

	mount_image ${CONTAINER}
	$(sudo lxc-start -n ${CONTAINER} -d --logfile=./${CONTAINER}.log)
	$(sudo lxc-wait -n ${CONTAINER} -s RUNNING)

	sleep 5
}

function create_container {
    local TARGETDIR="$BASEDIR/$2"
    local SOURCEDIR="$BASEDIR/$1"

    sudo mkdir ${TARGETDIR}
    sudo cp "$SOURCEDIR/"{config,fstab} ${TARGETDIR}
    sudo ln -s "$IMAGESDIR/$1.sqfs" "$IMAGESDIR/$CONTAINER.sqfs"

    sudo mkdir "$TARGETDIR/"rootfs{,.ro,.rw} -p
    sudo mkdir "$TARGETDIR/"rootfs.rw/etc/ -p
}

function config_container {
    local TARGETDIR="$BASEDIR/$1"

    echo ${CONTAINER} | sudo tee "$TARGETDIR/"rootfs.rw/etc/hostname > /dev/null 2>&1

    local ROOTFS="$TARGETDIR/rootfs"
    local FSTAB="$TARGETDIR/fstab"

    sudo sed -i -E "s/lxc.rootfs = ([a-zA-Z\-\._\/]+)//g" "$TARGETDIR/config"
    sudo sed -i -E "s/lxc.mount = ([a-zA-Z\-\._\/]+)//g" "$TARGETDIR/config"

    echo "lxc.rootfs = $ROOTFS" | sudo tee -a "$TARGETDIR/config" > /dev/null 2>&1
    echo "lxc.mount = $FSTAB" | sudo tee -a "$TARGETDIR/config" > /dev/null 2>&1
}

function generate_mac {
    local TARGETDIR="$BASEDIR/$1"
    local MACADDR=$(echo ${CONTAINER}|md5sum|sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/')

    sudo sed -i -E "s/hwaddr = ([a-f0-9:]+)/hwaddr = ${MACADDR}/" "$TARGETDIR/config"
    sudo sed -i -E "s/utsname = ([a-zA-Z\-\.]+)/utsname = ${CONTAINER}/g" "$TARGETDIR/config"
}

function mount_local_directory {
    BOX=$1

    if [[ ! -z $(mount | grep -E "/$BOX/") ]];	then
        if [[ ! -d $BOX ]]; then
            mkdir $BOX
        fi

        echo "Mounting $BOX"
        sudo mount "$BASEDIR/$BOX/rootfs/home/" $BOX -o bind,umask=0774
    fi
}

function create_ssh_key_pair {
    echo "Creating SSH key pair."

    if [ ! -d .lxc ]; then
        mkdir .lxc
    fi

    ssh-keygen -q -t rsa -P '' -f .lxc/unsecure-private-key
}

function copy_ssh_pub_key {
    BOX=$1
    USERNAME=$2

	sudo lxc-attach -n $BOX -- mkdir -p /home/${USERNAME}/.ssh >/dev/null
	cat .lxc/unsecure-private-key.pub | sudo lxc-attach -n $BOX -- tee /home/${USERNAME}/.ssh/authorized_keys >/dev/null
}

function configure_port_forwarding {
    BOX=$1
    SPORT=$2
    DPORT=$3
    PROTO=$4

    GUEST=$(get_container_dns_ip $BOX)
    HOST=$(get_host_ip)

    # sudo iptables -t nat -A PREROUTING -p tcp -d $HOST --dport $DPORT -j DNAT --to $GUEST:$SPORT
    sudo iptables -t nat -A OUTPUT -p $PROTO -d 127.0.0.1 --dport $SPORT -j DNAT --to $GUEST:$DPORT
    sudo iptables -t nat -A INPUT -p $PROTO -d $GUEST --dport $DPORT -j SNAT --to $HOST
    sudo lxc-attach -n $BOX -- iptables -t nat -A OUTPUT -p $PROTO -d $HOST --dport $DPORT -j REDIRECT --to $SPORT
}

function configure_http_port_frwarding {
    BOX=$1
    SPORT=$2

    configure_port_forwarding $BOX $SPORT 80 tcp
}
