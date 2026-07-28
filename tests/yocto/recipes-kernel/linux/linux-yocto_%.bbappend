# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2024 Bartosz Golaszewski <bartosz.golaszewski@linaro.org>

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:qemux86-64 = " file://kernel-9pfs.cfg"
