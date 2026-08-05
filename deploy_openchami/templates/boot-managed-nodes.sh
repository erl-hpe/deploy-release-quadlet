#! /usr/bin/bash
# SPDX-FileCopyrightText: (C) Copyright 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Phase 8: boot-managed-nodes
#
# - On cluster systems, switch DNS to the coresmd-coredns server
# - Set up boot service configuration for the nodes
# - Set up cloud-init metadata for nodes
# - Boot managed nodes (host mode: create VMs; cluster mode: power cycle)
# - Try to SSH to the nodes as a sanity check
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

WORK_DIRS=(
    "${DEPLOY_DIR}/boot"
    "${DEPLOY_DIR}/boot-metadata"
)

OCHAMI_PATH="$(command -v ochami)" || true
[ -n "${OCHAMI_PATH}" ] || { fail "'ochami' not installed"; exit 1; }

function ssh_to_compute_node() {
    local hostname="${1}"; shift || { fail "no hostname specified"; die; }
    local user="${1}"; shift || { fail "no deployment username provided"; die; }
    local cmd="${1}"; shift || cmd="true"
    local retries="${1}"; shift || retries=60
    local check="-o StrictHostKeyChecking=no"
    local file="-o UserKnownHostsFile=/dev/null"
    local time="-o ConnectTimeout=10"
    local where="root@${hostname}"
    info "attempting SSH to ${hostname} as ${user}"
    for ((retry=0; retry<retries; ++retry)); do
        if sudo su - "${user}" -c \
                "ssh ${check} ${file} ${time} ${where} '${cmd}'"; then
            info "SSH to ${hostname} succeeded"
            return 0
        fi
        (( retry < retries-1 )) && sleep 10
    done
    info "failed to SSH to ${hostname} after ${retries} attempts"
    return 1
}

# ── Create work directories ───────────────────────────────────────────
for dir in "${WORK_DIRS[@]}"; do
    info "boot-managed-nodes: preparing work directory ${dir}"
    [ -d "${dir}" ] && rm -rf "${dir}"
    mkdir -p "${dir}"
done

{%- if deployment_mode == 'cluster' %}
# ── Switch DNS to coresmd-coredns (cluster mode only) ─────────────────
info "boot-managed-nodes: verifying coresmd-coredns is active"
systemctl is-active --quiet coresmd-coredns.service || \
    { fail "coresmd-coredns is not active -- investigate and retry"; exit 1; }
info "boot-managed-nodes: switching DNS to cluster internal nameserver"
switch_dns "${MANAGEMENT_HEADNODE_IP}" "${CLUSTER_DOMAIN}"
{%- endif %}

# ── Generate boot configuration ───────────────────────────────────────
info "boot-managed-nodes: generating boot configuration"
cd "${DEPLOY_DIR}/boot"
for builder in "${IMAGE_BUILDERS[@]}"; do
    BOOT_CONFIG_FILE="${DEPLOY_DIR}/boot/$(basename "${builder}" .yaml).json"
    S3_PREFIX="$(yaml_to_json < "${builder}" | \
        jq -r '.options.s3_prefix' | sed -e 's:/[[:blank:]]*$::')"
    [[ "${S3_PREFIX}" != "null" ]] || continue
    generate-boot-config-json \
        "${S3_PREFIX}" \
        "${MANAGEMENT_HEADNODE_IP}" \
        $(managed_macs) | \
        tee "${BOOT_CONFIG_FILE}"
done

# ── Install boot configuration ────────────────────────────────────────
ACTIVE_BOOT_CONFIG="$(basename \
    "{{ images.builders[images.deployment_targets['compute']].metadata.boot_param_filename }}" \
    .yaml).json"

info "boot-managed-nodes: installing boot configuration '${ACTIVE_BOOT_CONFIG}'"
{%- if openchami_config.use_boot_service %}
sudo "${OCHAMI_PATH}" config --system cluster set demo cluster.boot-service.uri /boot-service
ochami boot config add -d @"${DEPLOY_DIR}/boot/${ACTIVE_BOOT_CONFIG}"
{%- else %}
ochami bss boot params set -d @"${DEPLOY_DIR}/boot/${ACTIVE_BOOT_CONFIG}"
{%- endif %}

# ── Set up cloud-init metadata ────────────────────────────────────────
info "boot-managed-nodes: configuring cloud-init metadata"
rm -f ~/.ssh/id_rsa*
ssh-keygen -t rsa -q -f ~/.ssh/id_rsa -N ""
mkdir -p "${DEPLOY_DIR}/boot-metadata"

{%- if openchami_config.metadata_service == "metadata-service" %}
cat <<EOF | tee "${DEPLOY_DIR}/boot-metadata/md-defaults.yaml"
---
metadata:
  name: "${CLUSTER_NAME}"
spec:
  base_url: "http://${MANAGEMENT_HEADNODE_IP}:8081/metadata-service"
  cluster_name: "${CLUSTER_NAME}"
  nid_length: 3
  public_keys:
    - "$(cat ~/.ssh/id_rsa.pub)"
  short_name: "nid-"
EOF
ochami metadata defaults add \
       -d "$(yaml_to_json < "${DEPLOY_DIR}/boot-metadata/md-defaults.yaml")"

for group in $(node_groups); do
    cat <<EOF | tee "${DEPLOY_DIR}/boot-metadata/md-group-${group}.yaml"
metadata:
  name: "${group}"
spec:
  description: "${group} nodes"
  template: |
    ## template: jinja
    #cloud-config
    merge_how:
    - name: list
      settings: [append]
    - name: dict
      settings: [no_replace, recurse_list]
    users:
{%- if openchami_config.cloud_init_templating_disabled %}
    - name: testuser
      ssh_authorized_keys:
      - "$(cat ~/.ssh/id_rsa.pub)"
    - name: root
      ssh_authorized_keys:
      - "$(cat ~/.ssh/id_rsa.pub)"
{%- else %}
      - name: testuser
        ssh_authorized_keys: {{ "{{ ds.meta_data.instance_data.v1.public_keys }}" }}
      - name: root
        ssh_authorized_keys: {{ "{{ ds.meta_data.instance_data.v1.public_keys }}" }}
{%- endif %}
    disable_root: false
EOF
    ochami metadata group add \
           -d "$(yaml_to_json < "${DEPLOY_DIR}/boot-metadata/md-group-${group}.yaml")"
done
{%- for node in nodes %}
ochami metadata instance add \
       -d '{"spec": {"instance_id": "{{ node.name }}", "local_hostname": "{{ node.hostname }}" }}'
{% endfor %}

{%- elif openchami_config.metadata_service == "cloud-init" %}
cat <<EOF | tee "${DEPLOY_DIR}/boot-metadata/ci-defaults.yaml"
---
base-url: "http://${MANAGEMENT_HEADNODE_IP}:8081/cloud-init"
cluster-name: "${CLUSTER_NAME}"
nid-length: 3
public-keys:
  - "$(cat ~/.ssh/id_rsa.pub)"
short-name: "nid-"
EOF
ochami cloud-init defaults set -f yaml \
       -d @"${DEPLOY_DIR}/boot-metadata/ci-defaults.yaml"

for group in $(node_groups); do
    cat <<EOF | tee "${DEPLOY_DIR}/boot-metadata/ci-group-${group}.yaml"
- name: ${group}
  description: "${group} group config"
  file:
    encoding: plain
    content: |
      ## template: jinja
      #cloud-config
      merge_how:
      - name: list
        settings: [append]
      - name: dict
        settings: [no_replace, recurse_list]
      users:
{%- if openchami_config.cloud_init_templating_disabled %}
      - name: testuser
        ssh_authorized_keys:
        - "$(cat ~/.ssh/id_rsa.pub)"
      - name: root
        ssh_authorized_keys:
        - "$(cat ~/.ssh/id_rsa.pub)"
{%- else %}
        - name: testuser
          ssh_authorized_keys: {{ "{{ ds.meta_data.instance_data.v1.public_keys }}" }}
        - name: root
          ssh_authorized_keys: {{ "{{ ds.meta_data.instance_data.v1.public_keys }}" }}
{%- endif %}
      disable_root: false
EOF
    ochami cloud-init group set -f yaml \
           -d @"${DEPLOY_DIR}/boot-metadata/ci-group-${group}.yaml"
done
{%- for node in nodes %}
ochami cloud-init node set \
       -d '[{"id":"{{ node.name }}","local-hostname":"{{ node.hostname }}"}]'
{% endfor %}

{%- else %}
info "boot-managed-nodes: no recognized metadata service configured, skipping metadata setup"
{%- endif %}

# ── Boot managed nodes ────────────────────────────────────────────────
{%- for node in nodes %}
{%- if deployment_mode == 'cluster' %}
info "boot-managed-nodes: power-cycling '{{ node.name }}'"
power-off-node "{{ node.name }}" "{{ node.bmc_name }}" || true
power-on-node "{{ node.name }}" "{{ node.bmc_name }}"
{%- else %}
info "boot-managed-nodes: launching VM '{{ node.name }}'"
if sudo virsh list --all | grep -q "{{ node.name }}"; then
    sudo virsh destroy "{{ node.name }}" || true
    sudo virsh undefine "{{ node.name }}" --nvram || \
        info "could not undefine '{{ node.name }}'"
fi
if [ "$(derive_architecture)" == 'amd64' ]; then
    UEFI="loader=/usr/share/OVMF/OVMF_CODE.secboot.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/OVMF/OVMF_VARS.fd,loader_secure=no"
else
    UEFI="uefi"
fi
sudo virt-install \
     --name {{ node.name }} \
     --memory 4096 \
     --vcpus 1 \
     --disk none \
     --pxe \
     --os-variant centos-stream9 \
{%- for interface in node.interfaces %}
     --network network={{ interface.network_name }},model=virtio,mac={{ interface.mac_addr }} \
{%- endfor %}
     --graphics none \
     --console pty,target_type=serial \
     --boot network,hd \
     --boot "${UEFI}" \
     --virt-type kvm \
     --noautoconsole
{%- endif %}
{%- endfor %}

# ── Verify SSH connectivity ────────────────────────────────────────────
{%- for node in nodes %}
ssh_to_compute_node "$(printf "nid-%3.3d" {{ node.nid }})" "${DEPLOY_USER}"
{%- endfor %}

