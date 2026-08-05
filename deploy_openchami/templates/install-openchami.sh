#! /usr/bin/bash
# SPDX-FileCopyrightText: (C) Copyright 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Phase 4: install-openchami
#
# - Merge the openchami.env configuration file
#   (/etc/openchami/configs/openchami.env)
# - Install the OpenCHAMI Release RPM built by prepare-openchami
#
# Run as the deployment user; uses sudo for privileged operations.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
source "${SCRIPT_DIR}/prep_setup.sh"

# ── merge_openchami_env() ──────────────────────────────────────────────
# Merges configured openchami.env values from the deployment config
# YAML into whatever is already installed in
# /etc/openchami/configs/openchami.env.
function merge_openchami_env() {
    local input_file="${DEPLOY_DIR}/openchami_env.yaml"
    local config_file
    config_file="$(mktemp)"
    local edited
    edited="$(mktemp)"
    local line var
    if [ -f "${input_file}" ]; then
        yaml_to_json < "${input_file}" | \
            jq -r 'to_entries | .[] | "\(.key)=\(.value)"' > "${config_file}"
        sudo cat /etc/openchami/configs/openchami.env | while read -r line; do
            if echo "${line}" | grep -q '^[[:space:]]*#'; then
                echo "${line}" >> "${edited}"
                continue
            fi
            var="$(echo "${line}" | sed -e 's/^[[:space:]]*\([^=]*\)=.*$/\1/')"
            if [ -z "${var}" ]; then
                echo "${line}" >> "${edited}"
                continue
            fi
            if ! grep -q "${var}=" "${config_file}"; then
                echo "${line}" >> "${edited}"
                continue
            fi
            echo "# ${line}" >> "${edited}"
            grep "${var}=" "${config_file}" >> "${edited}"
        done
        cat "${config_file}" | while read -r line; do
            var="$(echo "${line}" | sed -e 's/^[[:space:]]*\([^=]*\)=.*$/\1/')"
            if ! grep -q "${var}=" "${edited}"; then
                echo "${line}" >> "${edited}"
            fi
        done
        sudo cp "${edited}" /etc/openchami/configs/openchami.env
    fi
}

# ── Install the OpenCHAMI Release RPM ─────────────────────────────────
info "install-openchami: locating OpenCHAMI Release RPM"
RPM="$(ls "${DEPLOY_DIR}/openchami_release/openchami-"*.noarch.rpm 2>/dev/null | head -1)"
if [ -z "${RPM}" ]; then
    fail "no openchami RPM found in ${DEPLOY_DIR}/openchami_release" \
         "-- run the prepare-openchami phase first"
    exit 1
fi
info "install-openchami: installing ${RPM}"
sudo dnf install -y "${RPM}"

# ── Merge the openchami.env configuration ─────────────────────────────
info "install-openchami: merging /etc/openchami/configs/openchami.env"
merge_openchami_env

info "install-openchami: complete"
