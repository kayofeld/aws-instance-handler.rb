#! /bin/bash

# Configuration script to setup the *** repository on a CentOS machine 
# Script has to be run as root user


##################################################################################
###                           Functions declarations                           ###
##################################################################################


function inject_keys {
    echo "Installing CA certificate and keys"
    mkdir -p /etc/xxx/certs
    cp /root/include/*.pem /etc/xxx/certs/
}


function install_dependencies {
    yum -y install libncurse
    yum -y install emacs
    # whatever you want
}

function yum_update {
    echo "Updating yum cache"
    yum -y makecache
    yum -y update
}

function deactivate_selinux {
    setenforce 0
    chmod u+w /etc/selinux/config
    sed -i --follow-symlinks 's/^SELINUX=.*/SELINUX=disabled/g' /etc/sysconfig/selinux && cat /etc/sysconfig/selinux
    chmod u-w /etc/selinux
}

##################################################################################
###                        Beginning of the execution                          ###
##################################################################################

# Make shure root is running this script
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 1>&2
    echo ""
    read -p "Restart as root ? [y/N]" yn
    case $yn in
	[Yy]* ) sudo ./deploy-sbc.sh; exit 0;;
	* ) ;;
    esac
    exit 1
fi

# Deactivation of selinux
deactivate_selinux

# # Import of the CA certificate and Keys
inject_keys


# # Updating sources
yum_update

# # Installing 
install_dependencies
