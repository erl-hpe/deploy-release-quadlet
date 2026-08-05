#! /usr/bin/bash
# SPDX-FileCopyrightText: (C) Copyright 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Phase 1: setup-node
#
# - Install required packages
# - Create the deployment user (check first, create if absent)
# - Add deployment user to sudoers with NOPASSWD (check first)
#
# Can be run stand-alone as the deployment user; uses sudo internally
# for all privileged operations.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
source "${SCRIPT_DIR}/prep_setup.sh"

# ── Install required packages ──────────────────────────────────────────
info "setup-node: installing required packages"

PRE_INSTALL_PACKAGES="\
        epel-release \
{%- for package in hosting_config.extra_packages.pre %}
        {{ package }} \
{%- endfor %}
"
PACKAGES="\
{%- if deployment_mode == 'host' %}
        libvirt \
        qemu-kvm \
        virt-install \
        virt-manager \
{%- endif %}
        dnsmasq \
        podman \
        buildah \
        git \
        ansible-core \
        openssl \
        nfs-utils \
        s3cmd \
        make \
        rpmdevtools \
{%- if openchami_config.ochami.build %}
        scdoc \
{%- endif %}
{%- for package in hosting_config.extra_packages.main %}
        {{ package }} \
{%- endfor %}
"
sudo dnf -y check-update || true
sudo dnf install -y ${PRE_INSTALL_PACKAGES}
sudo dnf -y install ${PACKAGES}

{%- if deployment_mode == 'host' %}
sudo systemctl enable --now libvirtd
{%- endif %}

{%- if openchami_config.ochami.build %}
# Install latest stable Go (needed to build ochami)
sudo dnf remove -y golang || true
sudo rm -rf /usr/local/go
sudo rm -f /usr/bin/go
GOLANG_VERSION="$(curl -s 'https://go.dev/VERSION?m=text' | head -1)"
GOLANG_ARCH="$(derive_architecture)"
curl -s -o "${DEPLOY_DIR}/golang.tgz" \
     "https://dl.google.com/go/${GOLANG_VERSION}.linux-${GOLANG_ARCH}.tar.gz"
(cd /usr/local; sudo tar xzf "${DEPLOY_DIR}/golang.tgz")
sudo ln -sf /usr/local/go/bin/go /usr/bin/go
{%- endif %}

# ── Create the deployment user ─────────────────────────────
info "setup-node: checking/creating deployment user '${DEPLOY_USER}'"

if ! getent group "${DEPLOY_GROUP}" > /dev/null; then
    info "creating primary group '${DEPLOY_GROUP}'"
    sudo groupadd "${DEPLOY_GROUP}"
else
    info "primary group '${DEPLOY_GROUP}' already exists, skipping"
fi

{%- for group in manifest.deployment_user.supplementary_groups %}
if ! getent group "{{ group }}" > /dev/null; then
    info "creating supplementary group '{{ group }}'"
    sudo groupadd "{{ group }}"
else
    info "supplementary group '{{ group }}' already exists, skipping"
fi
{%- endfor %}

if ! getent passwd "${DEPLOY_USER}" > /dev/null; then
    info "creating user '${DEPLOY_USER}'"
    sudo useradd -g "${DEPLOY_GROUP}" "${DEPLOY_USER}"
else
    info "user '${DEPLOY_USER}' already exists, skipping"
fi

{%- for group in manifest.deployment_user.supplementary_groups %}
if getent group "{{ group }}" > /dev/null; then
    if ! id -nG "${DEPLOY_USER}" | grep -qw "{{ group }}"; then
        info "adding '${DEPLOY_USER}' to supplementary group '{{ group }}'"
        sudo usermod -aG "{{ group }}" "${DEPLOY_USER}"
    else
        info "'${DEPLOY_USER}' already in group '{{ group }}', skipping"
    fi
fi
{%- endfor %}

# ── Grant passwordless sudo ────────────────────────────────
info "setup-node: checking/granting passwordless sudo for '${DEPLOY_USER}'"
SUDOERS_LINE="${DEPLOY_USER} ALL=(ALL) NOPASSWD: ALL"
if sudo grep -qF "${SUDOERS_LINE}" /etc/sudoers 2>/dev/null; then
    info "passwordless sudo entry for '${DEPLOY_USER}' already present, skipping"
else
    sudo sed -i -e "/[[:space:]]*${DEPLOY_USER}/d" /etc/sudoers
    echo "${SUDOERS_LINE}" | sudo tee -a /etc/sudoers > /dev/null
    info "passwordless sudo entry added for '${DEPLOY_USER}'"
fi

info "setup-node: complete"

# ── Put cluster information in /etc/hosts ───────────────────
info "setup-node: put cluster information in /e/tc/hosts"

# Set up an /etc/hosts entry for the OpenCHAMI management head node so
# we can use it for certs and for reaching the services before any other
# DNS is set up.
info "Adding head node (${MANAGEMENT_HEADNODE_IP}) to /etc/hosts"
sudo sed -i /etc/hosts -e "/${MANAGEMENT_HEADNODE_FQDN}/d"
echo "${MANAGEMENT_HEADNODE_IP} ${MANAGEMENT_HEADNODE_FQDN}" | \
    sudo tee -a /etc/hosts > /dev/null

{%- if deployment_mode == 'host' %}
# While we are at it, also add the managed nodes' hostnames and IP
# addresses to /etc/hosts because, since we are in 'host' mode, we are
# not going to be using any other DNS for cluster host naming.
#
# XXX - At the moment we are using the first IP address in the first
#       interface. A better scheme should really be found using the
#       network name, the cluster network name and the interface name,
#       but I think that needs to be done in the python code not in
#       the shell code.
{%- for node in nodes %}
info "Adding managed node {{ node.hostname }} to /etc/hosts"
NID="$(printf "nid-%3.3d"  {{ node.nid }})"
NID_FQDN="${NID}.{{ hosting_config.net_head_domain }}"
NODE_FQDN="{{ node.hostname }}.{{ hosting_config.net_head_domain }}"
NODE_IP="{{ node.interfaces[0].ip_addrs[0].ip_addr }}"
sudo sed -i /etc/hosts -e "/${NODE_FQDN}/d"
echo "${NODE_IP} ${NODE_FQDN} {{ node.hostname }} ${NID_FQDN} ${NID}" | \
    sudo tee -a /etc/hosts > /dev/null
{%- endfor %}
{%- endif %}
