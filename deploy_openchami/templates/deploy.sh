#! /usr/bin/bash
# SPDX-FileCopyrightText: (C) Copyright 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Top-level deployment orchestrator.
#
# This script calls each enabled phase script in sequence.  It is run
# as the deployment user (non-root); individual phase scripts use sudo
# internally for any privileged operations.
#
# Phases are enabled or disabled via openchami_config.deployment_phases
# in the deployment configuration.
#
# The common entrypoint (run as root) is:
#
#     deploy-openchami [<config-overlay> [<config-overlay [...]]]
#
# Where <config-overlay> is a YAML file containing an overlay to be
# applied to the base configuration or the result of applying a
# previous <config-overlay> to the base configuration.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"
source "${SCRIPT_DIR}/prep_setup.sh"

# NOTE: Phase 1, which is setting up the node, is done in 'setup-node.sh'
#       run by a user with passwordless sudo access, or in response to
#
#       deploy-openchami -p [<config-overlay> [<config-overlay [...]]]
#
#       run as root.

{%- if openchami_config.deployment_phases.setup_s3_and_registry %}
info "=== Phase 2: setup-s3-and-registry ==="
"${SCRIPT_DIR}/setup-s3-and-registry.sh"
{%- endif %}

{%- if openchami_config.deployment_phases.prepare_openchami %}
info "=== Phase 3: prepare-openchami ==="
"${SCRIPT_DIR}/prepare-openchami.sh"
{%- endif %}

{%- if openchami_config.deployment_phases.install_openchami %}
info "=== Phase 4: install-openchami ==="
"${SCRIPT_DIR}/install-openchami.sh"
{%- endif %}

{%- if openchami_config.deployment_phases.start_openchami %}
info "=== Phase 5: start-openchami ==="
"${SCRIPT_DIR}/start-openchami.sh"
{%- endif %}

{%- if openchami_config.deployment_phases.configure_cluster %}
info "=== Phase 6: configure-cluster ==="
"${SCRIPT_DIR}/configure-cluster.sh"
{%- endif %}

{%- if openchami_config.deployment_phases.build_images %}
info "=== Phase 7: build-node-images ==="
"${SCRIPT_DIR}/build-node-images.sh"
{%- endif %}

{%- if openchami_config.deployment_phases.boot_managed_nodes %}
info "=== Phase 8: boot-managed-nodes ==="
"${SCRIPT_DIR}/boot-managed-nodes.sh"
{%- endif %}

info "=== Deployment complete ==="
