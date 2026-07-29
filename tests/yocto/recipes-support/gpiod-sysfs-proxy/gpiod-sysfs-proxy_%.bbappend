# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Qualcomm Technologies, Inc. and/or its subsidiaries

# Build the checked out working tree rather than a release.
#
# The recipe this appends to lives in meta-openembedded and inherits pypi, so
# on its own it builds the gpiod_sysfs_proxy sdist from PyPI - which means the
# ptest suite would exercise a published release and never the tree under
# test. GPIOD_SYSFS_PROXY_SRC comes from this layer's conf/layer.conf.

# TODO: also download new test suite ???

FILESEXTRAPATHS:prepend := "${GPIOD_SYSFS_PROXY_SRC}:"

# Removes only the sdist that pypi.bbclass prepends to SRC_URI. The init
# script and the gpio-sysfs-compat-tests repository that ptest runs are still
# wanted, which is why this is not an outright SRC_URI assignment. The recipe's
# own systemd units are fetched too but no longer installed; see the
# do_install:append below.
PYPI_SRC_URI = ""

# Unpacked into a directory of our own rather than the ${PYPI_PACKAGE}-${PV}
# one the sdist would have created, so that S does not depend on the version
# the recipe is named for.
#
# Listing individual paths is deliberate: the checkout also holds the kas
# build directory and the layers kas clones, which must not be dragged into
# WORKDIR or hashed on every build. The cost is that a new top level source
# file has to be added here too, or it is silently left out of the build.
SRC_URI += "\
    file://gpiod-sysfs-proxy;subdir=checkout \
    file://pyproject.toml;subdir=checkout \
    file://setup.py;subdir=checkout \
    file://README.md;subdir=checkout \
    file://MANIFEST.in;subdir=checkout \
    file://share;subdir=checkout \
    file://LICENSES;subdir=checkout \
"

S = "${UNPACKDIR}/checkout"

# The tree carries its licensing as REUSE metadata and has no COPYING file
# like the sdist does.
LIC_FILES_CHKSUM = "file://LICENSES/MIT.txt;md5=b1008aa4e86ef6163fc80a22d1547bea"

# PV still names the release the recipe was written for. The wheel that gets
# built carries the version in the tree's pyproject.toml instead, which is
# what `gpiod-sysfs-proxy --version` reports on the target.

# The old OE recipe we are basing off depends on python3-fuse; we switched to
# python3-pyfuse3.
# This workaround is needed until gpiod-sysfs-proxy_0.1.4.bb is in an
# OpenEmbedded release.
RDEPENDS:${PN} += "python3-pyfuse3"
RDEPENDS:${PN}:remove = "python3-fuse"

# Install this tree's systemd units in place of the ones carried in
# meta-openembedded's files/ directory. The two sets are not interchangeable:
# the recipe ships a flat gpiod-sysfs-proxy.service with @mountpoint@ patched
# in at build time, whereas share/ here has a template unit whose instance name
# is the systemd-escaped mountpoint, plus an instance drop-in that pulls in the
# overlay mounts. Testing the image against the recipe's copies would leave the
# units in this repository unexercised.
#
# share/ is already unpacked as part of the checkout (see SRC_URI above), so
# these are installed from ${S}/share.

# systemd-escape --path of MOUNTPOINT. Written out rather than derived from the
# path because a general escaping implementation is more than these two fixed
# mountpoints need, and a wrong instance name fails as a unit that never runs.
GPIO_INSTANCE = "${@bb.utils.contains('PACKAGECONFIG', 'sys-class-mount', 'sys-class-gpio', 'run-gpio', d)}"

SYSTEMD_SERVICE:${PN} = "gpiod-sysfs-proxy@${GPIO_INSTANCE}.service"

# Appended after the recipe's own do_install:append, so this runs last and can
# clear what that installed before putting this tree's units in place.
do_install:append() {
    if ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}; then
        rm -f ${D}${systemd_system_unitdir}/gpiod-sysfs-proxy.service

        install -m 0644 ${S}/share/gpiod-sysfs-proxy@.service \
            ${D}${systemd_system_unitdir}/gpiod-sysfs-proxy@.service

        if ${@bb.utils.contains('PACKAGECONFIG', 'sys-class-mount', 'true', 'false', d)}; then
            # The recipe enables its mount units by hand. This tree's are
            # ordered by the drop-in's Requires=/After= instead, so the
            # symlinks would now start them independently of the proxy.
            rm -f ${D}${systemd_system_unitdir}/sysinit.target.wants/run-gpio-sys.mount
            rm -f ${D}${systemd_system_unitdir}/sysinit.target.wants/sys-class.mount
            rmdir --ignore-fail-on-non-empty \
                ${D}${systemd_system_unitdir}/sysinit.target.wants

            install -m 0644 ${S}/share/run-gpio-sys.mount \
                ${D}${systemd_system_unitdir}/run-gpio-sys.mount
            install -m 0644 ${S}/share/sys-class.mount \
                ${D}${systemd_system_unitdir}/sys-class.mount

            install -d ${D}${systemd_system_unitdir}/gpiod-sysfs-proxy@${GPIO_INSTANCE}.service.d
            install -m 0644 \
                ${S}/share/gpiod-sysfs-proxy@sys-class-gpio.service.d/overlay.conf \
                ${D}${systemd_system_unitdir}/gpiod-sysfs-proxy@${GPIO_INSTANCE}.service.d/overlay.conf
        else
            rm -f ${D}${systemd_system_unitdir}/run-gpio-sys.mount
            rm -f ${D}${systemd_system_unitdir}/sys-class.mount
        fi
    fi
}
