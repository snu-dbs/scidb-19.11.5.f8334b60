#!/bin/bash
#
# BEGIN_COPYRIGHT
#
# Copyright (C) 2008-2019 SciDB, Inc.
# All Rights Reserved.
#
# SciDB is free software: you can redistribute it and/or modify
# it under the terms of the AFFERO GNU General Public License as published by
# the Free Software Foundation.
#
# SciDB is distributed "AS-IS" AND WITHOUT ANY WARRANTY OF ANY KIND,
# INCLUDING ANY IMPLIED WARRANTY OF MERCHANTABILITY,
# NON-INFRINGEMENT, OR FITNESS FOR A PARTICULAR PURPOSE. See
# the AFFERO GNU General Public License for the complete license terms.
#
# You should have received a copy of the AFFERO GNU General Public License
# along with SciDB.  If not, see <http://www.gnu.org/licenses/agpl-3.0.html>
#
# END_COPYRIGHT
#

set -e

function usage()
{
cat <<EOF
Usage:
    $0 <rpm|deb> insource <result_dir> <chroot_distro> <package_name>
    $0 <rpm|deb> <local|chroot> <Assert|RelWithDebInfo> <result_dir> <chroot_distro> <package_name>

    insource - (dirty) build packages from already compiled build
    local - (dirty) build packages from source without a chroot
    chroot - (clean) build packages from source in a chroot

    chroot_distro - centos-6-x86_64, centos-7-x86_64, ubuntu-trusty-amd64, ubuntu-xenial-amd64
EOF
    exit 1
}

function info()
{
    echo "$*" >&2
}

function error()
{
    echo "$*" >&2
    echo
    usage
    exit 1
}

if [ "$#" -lt 5 ]; then
    error "Wrong number of arguments."
fi

type="${1}"
target="${2}"

case $type in
    "deb"|"rpm");;
    *)
        error "Invalid package type '${type}'. Should be one of 'deb' or 'rpm'."
        ;;
esac

case $target in
    "insource")
        result_dir="${3}"
        distro="${4}"
        PKGNAME="${5}"
        ;;
    "chroot"|"local")
        if [ "$#" -lt 6 ]; then
            error "Wrong number of arguments."
        fi
        build_type="${3}"
        result_dir="${4}"
        distro="${5}"
        PKGNAME="${6}"
        ;;
    *)
        error "Invalid target '${target}'. Should be one of 'insource', 'chroot', or 'local'."
        ;;
esac

if [ $target != "insource" ]; then
    case $build_type in
        "Assert"|"RelWithDebInfo");;
        *)
            error "Invalid build_type '${build_type}'. Should be one of 'Assert' or 'RelWithDebInfo'."
            ;;
    esac
fi

case $distro in
    "centos-6-x86_64");;
    "centos-7-x86_64");;
    "ubuntu-trusty-amd64");;
    "ubuntu-xenial-amd64");;
    *)
        error "Invalid distro '${distro}'. Should be one of 'centos-6-x86_64' or 'centos-7-x86_64' or 'ubuntu-trusty-amd64' or 'ubuntu-xenial-amd64'."
        ;;
esac

jobs=$[`getconf _NPROCESSORS_ONLN`+1]

scidb_src_dir=$(readlink -f $(dirname $0)/..)

if [ $target != "insource" ]; then
    build_dir="`pwd`/scidb_packaging"
    build_src_dir="${build_dir}/${PKGNAME}-sources"
else
    build_dir="`pwd`"
fi

# This is the directory where mock root puts packages
#   This intermediate is needed so that the packages in pre_result_dir
#   are copied, as the not-root user, into result_dir.
#   The centOS 7 mock does everything as root while the centOS 6 mock
#   would run as the user.
#   Having root writeable only packages in result_dir broke many things.
#   This solves that problem.
#
pre_result_dir="`pwd`/p4_packaging_result"

function cleanup()
{
  if [ $target != "insource" ]; then
      info Removing pre_result_dir = ${pre_result_dir}
      sudo rm -rf ${pre_result_dir}
  fi
}

function die()
{
  cleanup
  echo $*
  exit 1
}

cleanup

pushd ${scidb_src_dir} > /dev/null 2>&1
info Extracting version info from file ${scidb_src_dir}/version
VERSION_MAJOR=`awk -F . '{print $1}' version`
VERSION_MINOR=`awk -F . '{print $2}' version`
VERSION_PATCH=`awk -F . '{print $3}' version`
info Extracted VERSION_MAJOR.VERSION_MINOR.VERSION_PATCH = ${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}

if [ -d .git ]; then
    info Extracting revision from git
    REVISION=$(git rev-list --abbrev-commit -1 HEAD)
elif [ -f revision ]; then
    info Extracting revision from file
    REVISION=$(cat revision)
else
    die "Can not extract source control revision."
fi
info Extracted REVISION="${REVISION}"

popd > /dev/null 2>&1

if [ -n "${SCIDB_INSTALL_PREFIX}" ]; then
    export SCIDB_INSTALL_PREFIX
    info SciDB installation: ${SCIDB_INSTALL_PREFIX}
fi

M4="m4 -DPKGNAME=${PKGNAME} -DVERSION_MAJOR=${VERSION_MAJOR} -DVERSION_MINOR=${VERSION_MINOR} -DVERSION_PATCH=${VERSION_PATCH} -DBUILD=${REVISION}"

if [ $target != "insource" ]; then
    M4="${M4} -DPACKAGE_BUILD_TYPE=${build_type}"
    case $build_type in
        "Assert")
	    M4="${M4} -DM4_ROOT_LOGGER=DEBUG"
	    ;;
	"RelWithDebInfo")
	    M4="${M4} -DM4_ROOT_LOGGER=INFO"
	    ;;
        *)
            error "Invalid build_type '${build_type}'. Should be one of 'Assert' or 'RelWithDebInfo'."
            ;;
    esac
fi

info Creating build_dir = ${build_dir}
mkdir -p "${build_dir}"

info Creating pre_result_dir = ${pre_result_dir}
mkdir -p "${pre_result_dir}" || die Can not create "${pre_result_dir}"
pre_result_dir=$(readlink -f "${pre_result_dir}")

info Creating result_dir = ${result_dir}
mkdir -p "${result_dir}" || die Can not create "${result_dir}"
result_dir=`readlink -f "${result_dir}"`
info Creating result_dir = ${result_dir}


if [ $target != "insource" ]; then
    info Preparing building dir ${build_dir}
    mkdir -p "${build_dir}" "${build_src_dir}" || die "mkdir failed"

    pushd ${scidb_src_dir} > /dev/null 2>&1
    if [ -d .git ]; then
        info Extracting sources from git
        git archive HEAD | tar -xC "${build_src_dir}"  || die "git archive"
        git diff HEAD > "${build_src_dir}"/local.patch || die "git diff"
        pushd "${build_src_dir}" > /dev/null 2>&1
        echo "${REVISION}" > revision
        if [ -s local.patch ]; then
            patch -p1 < local.patch || die "patch scidb source with uncommitted changes"
        fi
        popd > /dev/null 2>&1
    elif [ -f revision ]; then
        info Extracting sources from source tree
        mkdir -p ${build_src_dir} || die mkdir ${build_src_dir}
        cp -a . ${build_src_dir}  || die copy
    else
        die "Can not extract source."
    fi
    popd > /dev/null 2>&1
fi

if [ "$type" == "deb" ]; then

    debian_dir=$(readlink -f ${scidb_src_dir}/debian)
    [ ! -d ${debian_dir} ] && die Can not find ${debian_dir}

    function deb_prepare_sources ()
    {
        dirSrc="${1}"
        dirTgt="${2}"
        info Preparing sources from ${dirSrc} to ${dirTgt}
        codename=`echo ${distro}|awk -F- '{print $2}'`
        $M4 ${dirSrc}/"control.${codename}.in" > ${dirTgt}/control || die $M4 failed
        $M4 ${dirSrc}/"rules.${codename}.in" > ${dirTgt}/rules || die $M4 failed
        chmod a+x ${dirTgt}/rules
        for filename in changelog conffiles; do
            $M4 ${dirSrc}/${filename}.in > ${dirTgt}/${filename} || die $M4 failed
        done
        $M4 ${dirSrc}/postinst_plugins > ${dirTgt}/${PKGNAME}-${VERSION_MAJOR}.${VERSION_MINOR}-plugins.postinst || die $M4 failed
        $M4 ${dirSrc}/postrm_plugins > ${dirTgt}/${PKGNAME}-${VERSION_MAJOR}.${VERSION_MINOR}-plugins.postrm || die $M4 failed
        $M4 ${dirSrc}/postinst > ${dirTgt}/${PKGNAME}-${VERSION_MAJOR}.${VERSION_MINOR}.postinst || die $M4 failed
    }
    DSC_FILE_NAME="${PKGNAME}-${VERSION_MAJOR}.${VERSION_MINOR}_${VERSION_PATCH}-1.dsc"

    if [ $target != "insource" ]; then
            deb_prepare_sources ${debian_dir} "${build_src_dir}/debian"

        pushd "${build_src_dir}" > /dev/null 2>&1
            info Building source packages in ${build_src_dir}
            dpkg-buildpackage -rfakeroot -S -uc -us || die dpkg-buildpackage failed
        popd > /dev/null 2>&1

        if [ "$target" == "local" ]; then
            info Building binary packages locally
            pushd "${build_dir}" > /dev/null 2>&1
                dpkg-source -x ${DSC_FILE_NAME} ${PKGNAME}-build || die dpkg-source failed
            popd > /dev/null 2>&1
            pushd "${build_dir}"/${PKGNAME}-build > /dev/null 2>&1
                dpkg-buildpackage -rfakeroot -uc -us -j${jobs} || die dpkg-buildpackage failed
            popd > /dev/null 2>&1
            pushd "${build_dir}" > /dev/null 2>&1
                info Moving result from `pwd` to ${result_dir}
                cp *.deb *.dsc *.changes *.tar.gz "${result_dir}" || die cp failed
            popd > /dev/null 2>&1
        elif [ "$target" == "chroot" ]; then
            info Building binary packages in chroot
            python ${scidb_src_dir}/utils/chroot_build.py -u -d "${distro}" -r "${pre_result_dir}" -t "${build_dir}" -s "${build_dir}"/${DSC_FILE_NAME} -j${jobs} || die chroot_build.py failed
            python ${scidb_src_dir}/utils/chroot_build.py -b -d "${distro}" -r "${pre_result_dir}" -t "${build_dir}" -s "${build_dir}"/${DSC_FILE_NAME} -j${jobs} || die chroot_build.py failed
        fi
    else
        info Cleaning old packages
        rm -f ${result_dir}/*.deb
        rm -f ${result_dir}/*.changes

        # dpkg-buildpackage wants to have ./debian in the build tree
        build_debian_dir=$(readlink -f ${build_dir}/debian)
        if [ "${build_debian_dir}" != "${debian_dir}" ]; then
           rm -rf ${build_debian_dir}
           cp -r ${debian_dir} ${build_debian_dir} || die cp failed
        fi

        deb_prepare_sources ${build_debian_dir} ${build_debian_dir}

        info Building binary packages locally
        pushd ${build_dir} > /dev/null 2>&1
           BUILD_DIR="${build_dir}" INSOURCE=1 dpkg-buildpackage -rfakeroot -uc -us -b -j${jobs} || die dpkg-buildpackage failed
        popd > /dev/null 2>&1

        # Apparently, dpkg-buildpackage has to generate .deb files in ../ (go figure ...)
        pushd ${build_dir}/.. > /dev/null 2>&1
           info Moving result from ${build_dir}/.. to ${pre_result_dir}
           cp *.deb *.changes "${pre_result_dir}" || die cp failed
        popd > /dev/null 2>&1
    fi
elif [ "$type" == "rpm" ]; then

    scidb_spec=${scidb_src_dir}/scidb.spec.in

    [ ! -f ${scidb_spec} ] && die Can not find ${scidb_spec} file

    function rpm_prepare_sources ()
    {
       dirSrc="${1}"
       dirTgt="${2}"
       info Preparing sources from ${dirSrc} to ${dirTgt}

       $M4 ${dirSrc}/scidb.spec.in > "${dirTgt}"/scidb.spec || die $M4 failed
    }

    if [ $target != "insource" ]; then
        info Preparing rpmbuild dirs
        mkdir -p "${build_dir}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} || die mkdir failed

        rpm_prepare_sources ${scidb_src_dir} "${build_dir}/SPECS"

        pushd "${build_src_dir}" > /dev/null 2>&1
            tar czf ${build_dir}/SOURCES/scidb.tar.gz * || die tar failed
        popd > /dev/null 2>&1

        info Building SRPM
        pushd "${build_dir}"/SPECS/ > /dev/null 2>&1
            rpmbuild -D"_topdir ${build_dir}" -bs ./scidb.spec || die rpmbuild failed
        popd > /dev/null 2>&1

        SCIDB_SRC_RPM=${PKGNAME}-${VERSION_MAJOR}.${VERSION_MINOR}-${VERSION_PATCH}-1.src.rpm

        if [ "$target" == "local" ]; then
            info Building RPM locally
            pushd ${build_dir}/SRPMS > /dev/null 2>&1
                rpmbuild -D"_topdir ${build_dir}" --rebuild ${SCIDB_SRC_RPM} || die rpmbuild failed
            popd > /dev/null 2>&1
            info Moving result from "${build_dir}"/SRPMS and "${build_dir}"/RPMS and to ${pre_result_dir}
            cp "${build_dir}"/SRPMS/*.rpm "${build_dir}"/RPMS/*/*.rpm "${pre_result_dir}" || die cp failed
        elif [ "$target" == "chroot" ]; then
            info Building RPM in chroot
            python ${scidb_src_dir}/utils/chroot_build.py -u -d "${distro}" -r "${pre_result_dir}" -t "${build_dir}" -s "${build_dir}"/SRPMS/${SCIDB_SRC_RPM} || die chroot_build.py failed
            python ${scidb_src_dir}/utils/chroot_build.py -b -d "${distro}" -r "${pre_result_dir}" -t "${build_dir}" -s "${build_dir}"/SRPMS/${SCIDB_SRC_RPM} || die chroot_build.py failed
        fi
    else
        info Cleaning old files from ${build_dir}
        rm -rf ${build_dir}/rpmbuild

        rpm_prepare_sources ${scidb_src_dir} ${build_dir}

        info Building binary packages insource
        rpmbuild --with insource -D"_topdir ${build_dir}/rpmbuild" -D"_builddir ${build_dir}" -bb ${build_dir}/scidb.spec || die rpmbuild failed

        info Moving result from ${build_dir} to ${pre_result_dir}
        cp ${build_dir}/rpmbuild/RPMS/*/*.rpm "${pre_result_dir}" || die cp failed

        info Cleaning files from ${build_dir}
        rm -rf ${build_dir}/rpmbuild

    fi
fi


info "Copying packages (except source packages) from ${pre_result_dir} to ${result_dir}"
pushd ${pre_result_dir}
for file in $(ls *.rpm 2>/dev/null| grep -v src.rpm); do
    rm -f ${result_dir}/${file}
    cp $file ${result_dir} || die cp failed
done
for file in $(ls *.deb 2>/dev/null); do
    rm -f ${result_dir}/${file}
    cp $file ${result_dir} || die cp failed
done
popd

cleanup

info Done. Take result packages in ${result_dir}
