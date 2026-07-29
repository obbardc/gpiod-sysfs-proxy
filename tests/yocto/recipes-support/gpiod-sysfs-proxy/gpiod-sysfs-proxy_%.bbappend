# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Qualcomm Technologies, Inc. and/or its subsidiaries

# Build the checked out working tree rather than a release.
#
# The recipe this appends to lives in meta-openembedded and inherits pypi, so
# on its own it builds the gpiod_sysfs_proxy sdist from PyPI - which means the
# ptest suite would exercise a published release and never the tree under
# test. GPIOD_SYSFS_PROXY_SRC comes from this layer's conf/layer.conf.

# TODO: test systemd units too with v1.0.2 recipe; will need newer yocto too.
# https://git.openembedded.org/meta-openembedded/commit/meta-filesystems/dynamic-layers/meta-python/recipes-support/gpiod-sysfs-proxy?id=af37a6f0fbfed230634246a0e7a0beecc71956f1

# TODO: also download new test suite ???

FILESEXTRAPATHS:prepend := "${GPIOD_SYSFS_PROXY_SRC}:"

# Removes only the sdist that pypi.bbclass prepends to SRC_URI. Everything the
# recipe fetches for itself - the unit files, the init script, and the
# gpio-sysfs-compat-tests repository that ptest runs - is still wanted, which
# is why this is not an outright SRC_URI assignment.
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
