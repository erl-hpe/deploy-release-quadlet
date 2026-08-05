#! /usr/bin/bash
# SPDX-FileCopyrightText: (C) Copyright 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Phase 7: build-node-images
#
# - Build all configured node boot images
#
# Run as the deployment user; uses sudo for privileged operations.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
source "${SCRIPT_DIR}/prep_setup.sh"
source "/etc/profile.d/build-image.sh"

IMAGE_BUILDERS=(
    {%- for file in manifest.files.values() %}
    {%- if "image-builder" in file.annotations %}
    "{{ manifest.deployment_directory }}/{{ file.target }}"
    {%- endif %}
    {%- endfor %}
)

# Refresh the ochami token before the (potentially long) image builds
info "build-node-images: obtaining ochami access token"
get-ochami-token || { fail "unable to obtain ochami access token"; exit 1; }

for builder in "${IMAGE_BUILDERS[@]}"; do
    info "build-node-images: building image from '${builder}'"
    build-image "${builder}"
done

# Refresh token after builds in case it expired during a long build
info "build-node-images: refreshing ochami access token"
get-ochami-token || { fail "unable to refresh ochami access token"; exit 1; }

info "build-node-images: complete"
