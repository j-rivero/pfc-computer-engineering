#
# Copyright Open Source Robotics Foundation 2013-2017
# License: Apache2
#
#!/bin/bash -x

TIMEDIR=${WORKSPACE}/timing
mkdir -p $TIMEDIR

date +%s > ${TIMEDIR}/absolute_init

###################################################
# Boilerplate.
# DO NOT MODIFY

#stop on error
set -e

distro=precise
arch=amd64
base=/var/cache/pbuilder-$distro-$arch

aptconffile=$WORKSPACE/apt.conf

#increment this value if you have changed something that will invalidate base tarballs. #TODO this will need cleanup eventually.
basetgz_version=2

rootdir=$base/apt-conf-$basetgz_version

basetgz=$base/base-$basetgz_version.tgz
output_dir=$WORKSPACE/output
work_dir=$WORKSPACE/work

sudo apt-get update
sudo apt-get install -y pbuilder python-empy python-argparse debhelper # todo move to server setup, or confirm it's there

if [ -e $WORKSPACE/catkin-debs ]
then
  rm -rf $WORKSPACE/catkin-debs
fi

sudo apt-get install --reinstall python-pkg-resources ubuntu-archive-keyring pbuilder
git clone https://github.com/ahendrix/catkin-debs $WORKSPACE/catkin-debs -b master --depth 1


cd $WORKSPACE/catkin-debs
. setup.sh

#setup the cross platform apt environment
# using sudo since this is shared with pbuilder and if pbuilder is interupted it will leave a sudo only lock file.  Otherwise sudo is not necessary.
# And you can't chown it even with sudo and recursive
sudo PYTHONPATH=$PYTHONPATH $WORKSPACE/catkin-debs/scripts/setup_apt_root.py $distro $arch $rootdir --local-conf-dir $WORKSPACE

sudo rm -rf $output_dir
mkdir -p $output_dir

sudo rm -rf $work_dir
mkdir -p $work_dir
cd $work_dir

sudo apt-get update -c $aptconffile

# Grab a newer version of pbuilder, because the one that ships with Lucid suffers from a bug when using --execute
# https://bugs.launchpad.net/ubuntu/+source/pbuilder/+bug/811016
rm -f $WORKSPACE/pbuilder
wget -O $WORKSPACE/pbuilder http://bazaar.launchpad.net/~vcs-imports/pbuilder/trunk/download/head:/pbuilder/pbuilder
chmod a+x $WORKSPACE/pbuilder

# Setup the pbuilder environment if not existing, or update
if [ ! -e $basetgz ] || [ ! -s $basetgz ]
then
  date +%s > ${TIMEDIR}/pbuilder_create_init
  #make sure the base dir exists
  sudo mkdir -p $base
  #create the base image
  sudo $WORKSPACE/pbuilder create \
    --distribution $distro \
    --aptconfdir $rootdir/etc/apt \
    --basetgz $basetgz \
    --architecture $arch \
    --mirror http://archive.ubuntu.com/ubuntu \
    --debootstrapopts "--keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg"
    date +%s > ${TIMEDIR}/pbuilder_create_end
else
  date +%s > ${TIMEDIR}/pbuilder_update_init
  sudo $WORKSPACE/pbuilder --update --basetgz $basetgz
  date +%s > ${TIMEDIR}/pbuilder_update_end
fi

# Boilerplate.
# DO NOT MODIFY
###################################################

cat > build.sh << DELIM
date +%s > ${TIMEDIR}/build_sh_init

###################################################
# Make project-specific changes here
#
set -ex

# get ROS repo's key, to be used both in installing prereqs here and in creating the pbuilder chroot
apt-get install -y wget
sh -c 'echo "deb http://packages.ros.org/ros/ubuntu precise main" > /etc/apt/sources.list.d/ros-latest.list'
wget http://packages.ros.org/ros.key -O - | apt-key add -
apt-get update

# Step 1: install everything you need
# Required stuff for Gazebo
apt-get install -y cmake build-essential debhelper libfreeimage-dev libprotoc-dev libprotobuf-dev protobuf-compiler freeglut3-dev libcurl4-openssl-dev libtinyxml-dev libtar-dev libtbb-dev ros-fuerte-visualization-common libxml2-dev pkg-config libqt4-dev ros-fuerte-urdfdom libltdl-dev libboost-thread-dev libboost-signals-dev libboost-system-dev libboost-filesystem-dev libboost-program-options-dev libboost-regex-dev libboost-iostreams-dev cppcheck

# Step 2: configure and build
date +%s > ${TIMEDIR}/build_and_test_init

# Normal cmake routine for Gazebo
rm -rf $WORKSPACE/build $WORKSPACE/install
mkdir -p $WORKSPACE/build $WORKSPACE/install
cd $WORKSPACE/build
cmake -DPKG_CONFIG_PATH=/opt/ros/fuerte/lib/pkgconfig:/opt/ros/fuerte/stacks/visualization_common/ogre/ogre/lib/pkgconfig -DCMAKE_INSTALL_PREFIX=$WORKSPACE/install $WORKSPACE/gazebo
make -j3
make install
. $WORKSPACE/install/share/gazebo-1.*/setup.sh
LD_LIBRARY_PATH=/opt/ros/fuerte/lib:/opt/ros/fuerte/stacks/visualization_common/ogre/ogre/lib make test ARGS="-VV" || true

# Step 3: code check
cd $WORKSPACE/gazebo
sh tools/code_check.sh -xmldir $WORKSPACE/build/cppcheck_results || true
date +%s > ${TIMEDIR}/build_and_test_end
date +%s > ${TIMEDIR}/build_sh_end
DELIM

# Make project-specific changes here
###################################################

sudo $WORKSPACE/pbuilder  --execute \
    --bindmounts $WORKSPACE \
    --basetgz $basetgz \
    -- build.sh

date +%s > ${TIMEDIR}/absolute_end

