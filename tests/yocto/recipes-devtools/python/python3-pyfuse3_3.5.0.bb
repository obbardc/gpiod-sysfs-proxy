# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 OpenEmbedded Contributors

# Copied verbatim from meta-openembedded/meta-python/recipes-devtools/python/python3-pyfuse3_3.5.0.bb
#
# This recipe is needed until it is in an OpenEmbedded release.
#
# bitbake prefers the highest available PV, so this wins over meta-python's
# 3.4.2 without needing a PREFERRED_VERSION. Delete this recipe once
# meta-openembedded carries 3.5.0 or newer.

SUMMARY = "Python bindings for libfuse3."

LICENSE = "LGPL-2.1-or-later"
LIC_FILES_CHKSUM = "file://LICENSE;md5=622e3d340933e3857b7561f37a2f412b"

inherit pypi python_setuptools_build_meta python_pep517 cython pkgconfig

SRC_URI[sha256sum] = "88399a9494b88603230bba300f4ba9ad63fece5ed514ca3633d555a0c6a42b24"

DEPENDS = " \
    fuse3 \
    python3-setuptools-native \
    python3-setuptools-scm-native \
"

RDEPENDS:${PN} += " \
    python3-ctypes \
    python3-logging \
    python3-pickle \
    python3-threading \
    python3-trio \
"
