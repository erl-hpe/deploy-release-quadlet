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

# ── Get OCHAMI Token ─────────────────────────────────────────────
info "build-images: waiting for an ochami access token"
for i in {1..10}; do
    get-ochami-token || DEMO_ACCESS_TOKEN=""
    [ -n "${DEMO_ACCESS_TOKEN}" ] && break
    sleep 10
done
[ -n "${DEMO_ACCESS_TOKEN}" ] || \
    { fail "cannot obtain ochami access token"; exit 1; }

for builder in "${IMAGE_BUILDERS[@]}"; do
    info "build-node-images: building image from '${builder}'"
    build-image "${builder}"
done

info "build-node-images: complete"
