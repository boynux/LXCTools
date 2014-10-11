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
    sudo file "$IMAGESDIR/$1.sqfs" > /dev/null 2>$1
    
    return $?
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
