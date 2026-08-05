#! /usr/bin/bash
# SPDX-FileCopyrightText: (C) Copyright 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Phase 2: setup-s3-and-registry
#
# - Remove S3 volumes and shut down minio.service
# - Remove registry volumes and shut down registry.service
# - Copy the deployment user's .s3cfg from the generated one
# - Reload systemd
# - Start minio.service
# - Start registry.service
# - Install and configure regctl
# - Configure the S3 client
# - Create S3 buckets
#
# Run as the deployment user; uses sudo for privileged operations.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
source "${SCRIPT_DIR}/prep_setup.sh"

ROCKY_DIRS=(
    "/data/oci"
    "/data/s3"
)

S3_PUBLIC_BUCKETS=(
    "efi"
    "boot-images"
)

function cleanup_service() {
    local service="${1}"; shift || { fail "no service specified"; die; }
    local dir="${1}"; shift || dir=""
    info "cleaning up service '${service}'"
    if sudo systemctl status --no-pager --full "${service}" > /dev/null 2>&1; then
        sudo systemctl stop "${service}"
    fi
    if [ -n "${dir}" ] && [ -d "${dir}" ]; then
        info "removing volume directory '${dir}'"
        sudo rm -rf "${dir}"
        sudo podman system prune -a -f --volumes
    fi
}

# ── Remove S3 and registry volumes and stop services ──────────────────
info "setup-s3-and-registry: stopping minio.service and removing /data/s3"
cleanup_service minio.service /data/s3
info "setup-s3-and-registry: stopping registry.service and removing /data/oci"
cleanup_service registry.service /data/oci

# ── Recreate backing directories ──────────────────────────────────────
for dir in "${ROCKY_DIRS[@]}"; do
    info "setup-s3-and-registry: creating directory ${dir}"
    sudo mkdir -p "${dir}"
    sudo chown -R "${DEPLOY_USER}:" "${dir}"
done

# ── Copy the deployment user's .s3cfg ─────────────────────────────────
info "setup-s3-and-registry: installing .s3cfg for '${DEPLOY_USER}'"
cp "${DEPLOY_DIR}/s3cfg" ~/.s3cfg

# ── Reload systemd and start services ─────────────────────────────────
info "setup-s3-and-registry: reloading systemd"
sudo systemctl daemon-reload
info "setup-s3-and-registry: starting minio.service"
sudo systemctl start minio.service
info "setup-s3-and-registry: starting registry.service"
sudo systemctl start registry.service

# ── Install and configure regctl ──────────────────────────────────────
info "setup-s3-and-registry: installing and configuring regctl"
ARCH="$(derive_architecture)"
curl -fsSL \
    "https://github.com/regclient/regclient/releases/latest/download/regctl-linux-${ARCH}" \
    -o regctl
sudo mv regctl /usr/local/bin/regctl
sudo chmod 755 /usr/local/bin/regctl
/usr/local/bin/regctl registry set --tls disabled \
    "${MANAGEMENT_HEADNODE_FQDN}:${REGISTRY_API_PORT}"

# ── Configure S3 client and create buckets ────────────────────────────
info "setup-s3-and-registry: creating and configuring S3 buckets"
for bucket in "${S3_PUBLIC_BUCKETS[@]}"; do
    s3cmd ls | grep "s3://${bucket}" && s3cmd rb -r "s3://${bucket}" || true
    s3cmd mb "s3://${bucket}"
    s3cmd setacl "s3://${bucket}" --acl-public
    s3cmd setpolicy "${DEPLOY_DIR}/s3-public-read-${bucket}.json" \
          "s3://${bucket}" \
          --host="${MANAGEMENT_HEADNODE_IP}:${S3_API_PORT}" \
          --host-bucket="${MANAGEMENT_HEADNODE_IP}:${S3_API_PORT}"
done

info "setup-s3-and-registry: complete"
