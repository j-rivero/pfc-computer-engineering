#
# Copyright Open Source Robotics Foundation 2013-2017
# License: Apache2
#
#!/bin/bash -x
set -e

TIMEDIR=${WORKSPACE}/timing
mkdir -p $TIMEDIR

date +%s > ${TIMEDIR}/absolute_init

###################################################
# Dependencies
BASE_DEPENDENCIES="build-essential \
                   cmake           \
                   debhelper       \
                   cppcheck        \
                   xsltproc        \
                   python          \
                   gnupg2          \
                   python-empy     \
                   python-argparse \
                   debhelper"
                   
GAZEBO_BASE_DEPENDENCIES="cppcheck \
                            libfreeimage-dev     \
                            libprotoc-dev                    \
                            libprotobuf-dev                  \
                            protobuf-compiler                \
                            freeglut3-dev                    \
                            libcurl4-openssl-dev             \
                            libtinyxml-dev                   \
                            libtar-dev                       \
                            libtbb-dev                       \
                            ros-fuerte-visualization-common  \                            
                            ros-fuerte-urdfdom               \
                            libxml2-dev                      \
                            pkg-config                       \
                            libqt4-dev                       \
                            libltdl-dev                      \
                            libgts-dev                       \
                            libboost-thread-dev              \
                            libboost-signals-dev             \
                            libboost-system-dev              \
                            libboost-filesystem-dev          \
                            libboost-program-options-dev     \
                            libboost-regex-dev               \
                            libboost-iostreams-dev           \
                            sdformat"
###################################################

###################################################
# Job Configuration
LINUX_DISTRO=ubuntu
DISTRO=precise
ARCH=amd64
USE_OSRF_REPO=true
USE_ROS_REPO=true
DEPENDENCY_PKGS="${BASE_DEPENDENCIES} \
                 ${GAZEBO_BASE_DEPENDENCIES}"
###################################################

###################################################
# build.sh
#
cat > build.sh << DELIM
date +%s > ${TIMEDIR}/build_sh_init
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
###################################################

###################################################
# Docker creation


date +%s > ${TIMEDIR}/docker_create_init

case ${LINUX_DISTRO} in
  'ubuntu')
    SOURCE_LIST_URL="http://archive.ubuntu.com/ubuntu"
    # zesty does not ship locales by default
    export DEPENDENCY_PKGS="locales ${DEPENDENCY_PKGS}"
    ;;
  *)
    echo "Unknow linux distribution: ${LINUX_DISTRO}"
    exit 1
esac

# Select the docker container depenending on the ARCH
case ${ARCH} in
  'amd64')
     FROM_VALUE=${LINUX_DISTRO}:${DISTRO}
     ;;
  'i386')
     if [[ ${LINUX_DISTRO} == 'ubuntu' ]]; then
       FROM_VALUE=osrf/${LINUX_DISTRO}_${ARCH}:${DISTRO}
     else
       FROM_VALUE=${LINUX_DISTRO}:${DISTRO}
     fi
     ;;
   'armhf' | 'arm64' )
       FROM_VALUE=osrf/${LINUX_DISTRO}_${ARCH}:${DISTRO}
     ;;
  *)
     echo "Arch unknown"
     exit 1
esac

[[ -z ${USE_OSRF_REPO} ]] && USE_OSRF_REPO=false
[[ -z ${OSRF_REPOS_TO_USE} ]] && OSRF_REPOS_TO_USE=""
[[ -z ${USE_ROS_REPO} ]] && USE_ROS_REPO=false

# depracted variable, do migration here
if [[ -z ${OSRF_REPOS_TO_USE} ]]; then
  if ${USE_OSRF_REPO}; then
     OSRF_REPOS_TO_USE="stable"
  fi
fi

DOCKER_RND_ID=$(( ( RANDOM % 10000 )  + 1 ))

cat > Dockerfile << DELIM_DOCKER
# Docker file to run build.sh

FROM ${FROM_VALUE}
MAINTAINER Jose Luis Rivero <jose.luis.rivero.partida@gmail.com>

# setup environment
ENV LANG C
ENV LC_ALL C
ENV DEBIAN_FRONTEND noninteractive
ENV DEBFULLNAME "OSRF Jenkins"
ENV DEBEMAIL "jose.luis.rivero.partida@gmail.com"
DELIM_DOCKER

# Handle special INVALIDATE_DOCKER_CACHE keyword by set a random
if [[ -n ${INVALIDATE_DOCKER_CACHE} ]]; then
cat >> Dockerfile << DELIM_DOCKER_INVALIDATE
RUN echo 'BEGIN SECTION: invalidate full docker cache'
RUN echo "Detecting content in INVALIDATE_DOCKER_CACHE. Invalidating it"
RUN echo "Invalidate cache enabled. ${DOCKER_RND_ID}"
RUN echo 'END SECTION'
DELIM_DOCKER_INVALIDATE
fi

# The redirection fails too many times using us default httpredir
if [[ ${LINUX_DISTRO} == 'debian' ]]; then
cat >> Dockerfile << DELIM_DEBIAN_APT
  RUN sed -i -e 's:httpredir:ftp.us:g' /etc/apt/sources.list
  RUN echo "deb-src http://ftp.us.debian.org/debian ${DISTRO} main" \\
                                                         >> /etc/apt/sources.list
DELIM_DEBIAN_APT
fi

if [[ ${LINUX_DISTRO} == 'ubuntu' ]]; then
  if [[ ${ARCH} != 'armhf' && ${ARCH} != 'arm64' ]]; then
cat >> Dockerfile << DELIM_DOCKER_ARCH
  # Note that main,restricted and universe are not here, only multiverse
  # main, restricted and unvierse are already setup in the original image
  RUN echo "deb ${SOURCE_LIST_URL} ${DISTRO} multiverse" \\
                                                         >> /etc/apt/sources.list && \\
      echo "deb ${SOURCE_LIST_URL} ${DISTRO}-updates main restricted universe multiverse" \\
                                                         >> /etc/apt/sources.list && \\
      echo "deb ${SOURCE_LIST_URL} ${DISTRO}-security main restricted universe multiverse" && \\
                                                         >> /etc/apt/sources.list
DELIM_DOCKER_ARCH
  fi
fi

# i386 image only have main by default
if [[ ${LINUX_DISTRO} == 'ubuntu' && ${ARCH} == 'i386' ]]; then
cat >> Dockerfile << DELIM_DOCKER_I386_APT
RUN echo "deb ${SOURCE_LIST_URL} ${DISTRO} restricted universe" \\
                                                       >> /etc/apt/sources.list
DELIM_DOCKER_I386_APT
fi

# Workaround for: https://bugs.launchpad.net/ubuntu/+source/systemd/+bug/1325142
if [[ ${ARCH} == 'i386' ]]; then
cat >> Dockerfile << DELIM_DOCKER_PAM_BUG
RUN echo "Workaround on i386 to bug in libpam. Needs first apt-get update"
RUN dpkg-divert --rename --add /usr/sbin/invoke-rc.d \\
        && ln -s /bin/true /usr/sbin/invoke-rc.d \\
    && apt-get update \\
        && apt-get install -y libpam-systemd \\
    && rm /usr/sbin/invoke-rc.d \\
        && dpkg-divert --rename --remove /usr/sbin/invoke-rc.d
DELIM_DOCKER_PAM_BUG
fi

# dirmngr from Yaketty on needed by apt-key
if [[ $DISTRO != 'trusty' ]] || [[ $DISTRO != 'xenial' ]]; then
cat >> Dockerfile << DELIM_DOCKER_DIRMNGR
RUN apt-get update && \\
    apt-get install -y dirmngr
DELIM_DOCKER_DIRMNGR
fi

for repo in ${OSRF_REPOS_TO_USE}; do
cat >> Dockerfile << DELIM_OSRF_REPO
RUN echo "deb http://packages.osrfoundation.org/gazebo/${LINUX_DISTRO}-${repo} ${DISTRO} main" >\\
                                                /etc/apt/sources.list.d/osrf.${repo}.list
RUN apt-key adv --keyserver ha.pool.sks-keyservers.net --recv-keys D2486D2DD83DB69272AFE98867170598AF249743
DELIM_OSRF_REPO
done

if ${USE_ROS_REPO}; then
cat >> Dockerfile << DELIM_ROS_REPO
# Note that ROS uses ubuntu hardcoded in the paths of repositories
RUN echo "deb http://packages.ros.org/ros/ubuntu ${DISTRO} main" > \\
                                                /etc/apt/sources.list.d/ros.list
RUN apt-key adv --keyserver ha.pool.sks-keyservers.net --recv-keys 421C365BD9FF1F717815A3895523BAEEB01FA116
DELIM_ROS_REPO
fi

# Packages that will be installed and cached by docker. In a non-cache
# run below, the docker script will check for the latest updates
PACKAGES_CACHE_AND_CHECK_UPDATES="${BASE_DEPENDENCIES} ${DEPENDENCY_PKGS}"

if $USE_GPU_DOCKER; then
  PACKAGES_CACHE_AND_CHECK_UPDATES="${PACKAGES_CACHE_AND_CHECK_UPDATES} ${GRAPHIC_CARD_PKG}"
fi

cat >> Dockerfile << DELIM_DOCKER3
# Invalidate cache monthly
# This is the firt big installation of packages on top of the raw image.
# The expection of updates is low and anyway it is cathed by the next
# update command below
# The rm after the fail of apt-get update is a workaround to deal with the error:
# Could not open file *_Packages.diff_Index - open (2: No such file or directory)
RUN echo "${MONTH_YEAR_STR}" \
 && (apt-get update || (rm -rf /var/lib/apt/lists/* && apt-get update)) \
 && apt-get install -y ${PACKAGES_CACHE_AND_CHECK_UPDATES} \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# This is killing the cache so we get the most recent packages if there
# was any update. Note that we don't remove the apt/lists file here since
# it will make to run apt-get update again
RUN echo "Invalidating cache $(( ( RANDOM % 100000 )  + 1 ))" \
 && (apt-get update || (rm -rf /var/lib/apt/lists/* && apt-get update)) \
 && apt-get install -y ${PACKAGES_CACHE_AND_CHECK_UPDATES} \
 && apt-get clean

# Map the workspace into the container
RUN mkdir -p ${WORKSPACE}
DELIM_DOCKER3

if [[ -n ${SOFTWARE_DIR} ]]; then
cat >> Dockerfile << DELIM_DOCKER4
COPY ${SOFTWARE_DIR} ${WORKSPACE}/${SOFTWARE_DIR}
DELIM_DOCKER4
fi

cat >> Dockerfile << DELIM_WORKAROUND_91
# Workaround to issue:
# https://bitbucket.org/osrf/handsim/issue/91
RUN echo "en_GB.utf8 UTF-8" >> /etc/locale.gen
RUN locale-gen en_GB.utf8
ENV LC_ALL en_GB.utf8
ENV LANG en_GB.utf8
ENV LANGUAGE en_GB
# Docker has problems with Qt X11 MIT-SHM extension
ENV QT_X11_NO_MITSHM 1
DELIM_WORKAROUND_91

echo '# BEGIN SECTION: see build.sh script'
cat build.sh
echo '# END SECTION'

cat >> Dockerfile << DELIM_DOCKER4
COPY build.sh build.sh
RUN chmod +x build.sh
DELIM_DOCKER4
echo '# END SECTION'

echo '# BEGIN SECTION: see Dockerfile'
cat Dockerfile
echo '# END SECTION'

date +%s > ${TIMEDIR}/docker_create_end

###################################################

###################################################
# Docker execution

date +%s > ${TIMEDIR}/docker_execution_init
# TODO: run inside docker as a normal user and replace the sudo calls
export docker_cmd="docker"

if [[ -z $DOCKER_JOB_NAME ]]; then
    export DOCKER_JOB_NAME=${DOCKER_RND_ID}
    echo "Warning: DOCKER_JOB_NAME was not defined"
    echo " - using ${DOCKER_JOB_NAME}"
fi

# Check if the job was called from jenkins
if [[ -n ${BUILD_NUMBER} ]]; then
   export DOCKER_JOB_NAME="${DOCKER_JOB_NAME}:${BUILD_NUMBER}"
else
   # Reuse the random id
   export DOCKER_JOB_NAME="${DOCKER_JOB_NAME}:${DOCKER_RND_ID}"
fi

echo " - Using DOCKER_JOB_NAME ${DOCKER_JOB_NAME}"

export CIDFILE="${WORKSPACE}/${DOCKER_JOB_NAME}.cid"

# CIDFILE should not exists
if [[ -f ${CIDFILE} ]]; then
    echo "CIDFILE: ${CIDFILE} exists, which will make docker to fail."
    echo "Container ID file found, make sure the other container isn't running"
    exit 1
fi

export DOCKER_TAG="${DOCKER_JOB_NAME}"

# This are usually for continous integration jobs
sudo rm -fr ${WORKSPACE}/build
sudo mkdir -p ${WORKSPACE}/build

sudo docker build --tag ${DOCKER_TAG} .

# needed for docker in docker use
EXTRA_PARAMS_STR="--privileged"

# DOCKER_FIX is for workaround https://github.com/docker/docker/issues/14203
sudo ${docker_cmd} run $EXTRA_PARAMS_STR  \
            -e DOCKER_FIX=''  \
            -e WORKSPACE=${WORKSPACE} \
            -e TERM=xterm-256color \
            -v ${WORKSPACE}:${WORKSPACE} \
            -v /dev/log:/dev/log:ro \
            -v /run/log:/run/log:ro \
            --tty \
            --rm \
            ${DOCKER_TAG} \
            /bin/bash build.sh

date +%s > ${TIMEDIR}/docker_execution_end


###################################################

date +%s > ${TIMEDIR}/absolute_end
