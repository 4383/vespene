#!/bin/bash

# ---------------------------------------------------------------------------
# 2_database.sh: common settings used by the for Vespene setup scripts.
# This file is loaded by the the other setup scripts and just contains variables.
# ---------------------------------------------------------------------------

# load common settings
source ./0_common.sh

# ---
echo "installing packages ..."
CONFIG=""
PG_PREFIX=""

# install postgresql
if [[ "$DISTRO" == "redhat" ]]; then
    # this just covers CentOS for now
    sudo yum -y install centos-release-scl
    # on Red Hat
    # use software collections
    sudo yum -y install epel-release
    sudo yum -y install rh-postgresql10
    sudo tee /etc/profile.d/enable_pg10.sh >/dev/null << END_OF_PG10
    #!/bin/bash
    source scl_source enable rh-postgresql10
END_OF_PG10
    sudo chmod +x /etc/profile.d/enable_pg10.sh 
    PG_PREFIX="/opt/rh/rh-postgresql10/root/usr/bin/"
    CONFIG="/var/opt/rh/rh-postgresql10/lib/pgsql/data/pg_hba.conf"
elif [[ "$DISTRO" == "ubuntu" ]]; then
    sudo apt install -y postgresql postgresql-contrib postgresql-client
    CONFIG="/etc/postgresql/10/main/pg_hba.conf"
elif [[ "$DISTRO" == "archlinux" ]]; then
    sudo pacman --noconfirm -Sy postgresql
    CONFIG="/var/lib/postgres/data/pg_hba.conf"
elif [[ "$DISTRO" == "MacOS" ]]; then
    brew install postgresql
    CONFIG="/usr/local/var/postgres/pg_hba.conf"
fi

# ---
echo "initializing the database server..."

if [[ "$DISTRO" == "archlinux" ]]; then
    sudo -u postgres initdb -D '/var/lib/postgres/data'
elif [[ "$DISTRO" == "MacOS" ]]; then
    initdb /usr/local/var/postgres
elif [[ "$DISTRO" == "redhat" ]]; then
    sudo -u postgres ${PG_PREFIX}postgresql-setup initdb
else
    echo "initdb should not be needed on this platform"
fi

# ----
echo "configuring security at ${CONFIG} ..."

# configure PostgreSQL security to allow the postgres account in locally, and allow
# password access remotely.  You can tweak this if you want but must choose something
# that will work with the /etc/vespene/settings.d/database.py that will be created.
# Using password auth is highly recommended as the workers also use database access.
sudo tee $CONFIG > /dev/null <<END_OF_CONF
local	all	${DB_USER}	ident
host	all	all	0.0.0.0/0	md5
END_OF_CONF

sudo chown $DB_USER $CONFIG

if [ "$DISTRO" == "redhat" ]; then
   echo "creating symbolic links to libraries..."
   sudo ln -s /opt/rh/rh-postgresql10/root/usr/lib64/libpq.so.rh-postgresql10-5 /usr/lib64/libpq.so.rh-postgresql10-5
   sudo ln -s /opt/rh/rh-postgresql10/root/usr/lib64/libpq.so.rh-postgresql10-5 /usr/lib/libpq.so.rh-postgresql10-5
fi

# ---
echo "starting postgresql..."
if [ "$OSTYPE" == "linux-gnu" ]; then
    if [ "$DISTRO" == "redhat" ]; then  
        # run from software collections
        sudo service rh-postgresql10-postgresql restart
    else
        sudo systemctl enable postgresql.service
        sudo systemctl start postgresql.service
    fi
elif [ "$DISTRO" == "MacOS" ]; then
    /usr/local/bin/pg_ctl restart -D /usr/local/var/postgres/
fi

# --
echo "creating the vespene database and user..."
echo "  (if you any errors from 'cd' here or further down they can be ignored)"

EXISTS=`sudo -u $DB_USER ${PG_PREFIX}psql -lqt | grep vespene`
if [ $? -eq 1 ]; then
   $POST_SUDO ${PG_PREFIX}createdb vespene
   echo "creating the vespene user"
   $POST_SUDO ${PG_PREFIX}createuser vespene
else
   echo "- database already exists"
fi

# --
echo "granting access..."
# give the user access and set their password
$POST_SUDO ${PG_PREFIX}psql -d vespene -c "GRANT ALL on DATABASE vespene TO vespene"
$POST_SUDO ${PG_PREFIX}psql -d vespene -c "ALTER USER vespene WITH ENCRYPTED PASSWORD '$DBPASS'"
