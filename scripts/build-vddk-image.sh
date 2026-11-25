#!/usr/bin/env bash
# Build the MTV VDDK init image on ocp-a from VMware's VDDK tarball and push it to the internal registry
# (image openshift-mtv/vddk:<tag>, the site value vddkInitImage used by provider vcenter01-vddk).
# The build runs on the cluster (OpenShift binary Docker build), so the bastion needs no podman and the
# internal registry needs no external route.
#
# VDDK is VMware/Broadcom software under its own licence: never commit the tarball or the unpacked files to git.
# Download it from the Broadcom developer portal (VMware Virtual Disk Development Kit 8.0.3,
# VMware-vix-disklib-8.0.3-23950268.x86_64.tar.gz) and compare its sha256 with the one Broadcom publishes.
#
# Usage: scripts/build-vddk-image.sh <path to VMware-vix-disklib-*.tar.gz> [tag, default 8.0.3]
#        KUBECONFIG_A=~/ocp-a.kubeconfig (default)
set -euo pipefail
TARBALL=${1:?usage: $0 <VMware-vix-disklib-*.tar.gz> [tag]}
TAG=${2:-8.0.3}
KC=${KUBECONFIG_A:-$HOME/ocp-a.kubeconfig}
OC="oc --kubeconfig $KC"
NS=openshift-mtv

echo "sha256 of $TARBALL (compare with Broadcom's published checksum):"
sha256sum "$TARBALL"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
tar -xzf "$TARBALL" -C "$WORK"
test -e "$WORK/vmware-vix-disklib-distrib/lib64/libvixDiskLib.so.8" \
  || { echo "lib64/libvixDiskLib.so.8 not found: not a VDDK 8 tarball?"; exit 1; }

cat > "$WORK/Dockerfile" <<'DOCKERFILE'
FROM registry.access.redhat.com/ubi9/ubi-minimal
USER 1001
COPY vmware-vix-disklib-distrib /vmware-vix-disklib-distrib
RUN mkdir -p /opt
ENTRYPOINT ["cp", "-r", "/vmware-vix-disklib-distrib", "/opt"]
DOCKERFILE

# One BuildConfig, created once; each run builds a new image and tags it.
$OC -n $NS get bc vddk >/dev/null 2>&1 || \
  $OC -n $NS new-build --name vddk --binary --strategy docker --to "vddk:$TAG"
$OC -n $NS patch bc vddk --type merge -p "{\"spec\":{\"output\":{\"to\":{\"kind\":\"ImageStreamTag\",\"name\":\"vddk:$TAG\"}}}}"
$OC -n $NS start-build vddk --from-dir "$WORK" --follow --wait

echo
$OC -n $NS get istag "vddk:$TAG"
DIGEST=$($OC -n $NS get istag "vddk:$TAG" -o jsonpath='{.image.metadata.name}')
echo "Image: image-registry.openshift-image-registry.svc:5000/$NS/vddk@$DIGEST"
echo "Set this as vddkInitImage in policies/site-values/ocp-a.yaml (pinned by digest) and push."
