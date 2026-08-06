#! /usr/bin/bash
# SPDX-FileCopyrightText: (C) Copyright 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Phase 3: prepare-openchami
#
# - Remove any existing 'ochami' package installation
# - Install 'ochami' (download RPM or build from source)
# - Remove any existing 'openchami' package installation
# - Remove any existing 'openchami-release' git repo
# - Set up new OpenCHAMI Release repo, check out specified version, build RPM
#
# Run as the deployment user; uses sudo for privileged operations.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
source "${SCRIPT_DIR}/prep_setup.sh"

# ── Remove any existing ochami installation ───────────────────────────
info "prepare-openchami: removing any existing 'ochami' installation"
sudo dnf remove -y --noautoremove ochami || true

# ── Install ochami ─────────────────────────────────────────────────────
info "prepare-openchami: installing 'ochami'"
OCHAMI_VERSION="{{ openchami_config.ochami.version }}"
{%- if openchami_config.ochami.build %}
OCHAMI_URL="{{ openchami_config.ochami.url }}"
info "prepare-openchami: cloning ochami source: ${OCHAMI_URL}"
rm -rf "${DEPLOY_DIR}/ochami"
su - "${DEPLOY_USER}" -c \
     "git config --global --add safe.directory '${DEPLOY_DIR}/ochami'"
git clone "${OCHAMI_URL}" "${DEPLOY_DIR}/ochami"
cd "${DEPLOY_DIR}/ochami"
git checkout "${OCHAMI_VERSION}"
make install
{%- else %}
info "prepare-openchami: downloading ochami RPM version '${OCHAMI_VERSION}'"
LATEST_RELEASE_URL="$(curl -s \
    "https://api.github.com/repos/OpenCHAMI/ochami/releases/${OCHAMI_VERSION}" | \
    jq -r ".assets[] | select(.name | endswith(\"$(derive_architecture).rpm\")) | .browser_download_url")"
curl -fsSL "${LATEST_RELEASE_URL}" -o ochami.rpm
info "prepare-openchami: installing ochami RPM"
sudo dnf install -y ./ochami.rpm
{%- endif %}

# ── Remove any existing openchami installation ────────────────────────
info "prepare-openchami: removing any existing 'openchami' package"
sudo dnf remove -y --noautoremove openchami || true
sudo rm -rf /etc/openchami

# ── Remove any existing openchami-release git repo ────────────────────
info "prepare-openchami: removing old openchami-release repo (if any)"
rm -rf "${DEPLOY_DIR}/openchami_release"

# ── Clone and build the openchami release RPM ─────────────────────────
OPENCHAMI_URL="{{ openchami_config.release.url }}"
RELEASE_VERSION="{{ openchami_config.release.version }}"
info "prepare-openchami: cloning openchami-release: ${OPENCHAMI_URL}"
git clone "${OPENCHAMI_URL}" "${DEPLOY_DIR}/openchami_release"
cd "${DEPLOY_DIR}/openchami_release"
info "prepare-openchami: checking out version '${RELEASE_VERSION}'"
git checkout "${RELEASE_VERSION}"
info "prepare-openchami: building OpenCHAMI Release RPM"
make

info "prepare-openchami: complete (RPM built in ${DEPLOY_DIR}/openchami_release)"
