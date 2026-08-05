#! /usr/bin/bash
# SPDX-FileCopyrightText: (C) Copyright 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Phase 5: start-openchami
#
# - Shut down any currently running instance of openchami.target
# - Set up OpenCHAMI system files needed for this run
# - Start openchami.target
# - Configure the ochami CLI client
# - Wait for SMD to start
#
# Run as the deployment user; uses sudo for privileged operations.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
source "${SCRIPT_DIR}/prep_setup.sh"

OCHAMI_PATH="$(command -v ochami)" || true
[ -n "${OCHAMI_PATH}" ] || \
    { fail "'ochami' is not installed -- run prepare-openchami phase first"; exit 1; }

# ── Shut down any existing OpenCHAMI instance ─────────────────────────
info "start-openchami: shutting down any existing OpenCHAMI instance"
if sudo systemctl status --no-pager openchami.target > /dev/null 2>&1; then
    sudo systemctl stop openchami.target
fi

# Remove stale postgres-data volume if present and dangling
for retry in {1..10}; do
    if ! sudo podman volume ls | grep -q postgres-data; then
        break
    fi
    sleep 5
    if sudo podman volume ls --filter dangling=true | grep -q postgres-data; then
        sudo podman volume rm postgres-data && break || true
    fi
done
if [ "${retry}" -eq 10 ]; then
    { fail "timed out waiting to clear the SMD and BSS data"; exit 1; }
fi

# ── Set up OpenCHAMI system files ─────────────────────────────────────
info "start-openchami: replacing system files with generated versions"
(
    cd "${DEPLOY_DIR}/openchami_files"
    # The files under this directory are organized the same way they would
    # be organized under '/' so we can copy them from here by their relative
    # path and give the copies an absolute path by prepending '/'.
    find * -type f | while read path; do
        sudo cp "./${path}" "/${path}"
    done
)

# ── Start the OpenCHAMI target ────────────────────────────────────────
info "start-openchami: starting openchami.target"
sudo systemctl start openchami.target

# ── Configure the ochami CLI client ──────────────────────────────────
info "start-openchami: configuring ochami CLI client"
sudo rm -f /etc/ochami/config.yaml
echo y | sudo "${OCHAMI_PATH}" config cluster set \
              --system --default "${CLUSTER_NAME}" \
              cluster.uri "https://${MANAGEMENT_HEADNODE_FQDN}:8443" \
    || { fail "failed to configure ochami CLI client"; exit 1; }

# ── Wait for SMD to start ─────────────────────────────────────────────
info "start-openchami: waiting for an ochami access token"
for i in {1..10}; do
    get-ochami-token || DEMO_ACCESS_TOKEN=""
    [ -n "${DEMO_ACCESS_TOKEN}" ] && break
    sleep 10
done
[ -n "${DEMO_ACCESS_TOKEN}" ] || \
    { fail "cannot obtain ochami access token"; exit 1; }

info "start-openchami: waiting for SMD to become available"
smd_running=false
for i in {0..9}; do
    info "waiting for SMD (up to $(( 100 - i * 10 )) more seconds)"
    if ochami smd component get > /dev/null 2>&1; then
        smd_running=true
        break
    fi
    sleep 10
done
${smd_running} || \
    { fail "timeout waiting for SMD to start; OpenCHAMI is not fully available"; exit 1; }

info "start-openchami: complete"
