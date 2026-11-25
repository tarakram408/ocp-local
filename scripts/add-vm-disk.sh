#!/usr/bin/env bash
# Create an extra VM disk with a readable name: <vm>-disk-<n> on ontap-nas, without the CDI populator, so Trident names
# the ONTAP volume <cluster>_<namespace>_<vm>_disk_<n>_<suffix> (a disk added from the console gets prime_<uuid>).
# Attach it afterwards: VM -> Configuration -> Storage -> Add -> use an existing PVC -> <vm>-disk-<n>, interface virtio.
#
# Usage: scripts/add-vm-disk.sh <vm> <disk-number> <size> [namespace] [storageclass]
#   OC="oc --context ocp-a" scripts/add-vm-disk.sh test-vm 1 10Gi
# Number extra disks from 1 (disk-0 is the root disk from the template or the MTV plan).
set -euo pipefail
OC=${OC:-oc}
VM=${1:?vm name}; N=${2:?disk number}; SIZE=${3:?size, e.g. 10Gi}
NS=${4:-virtual-machines}; SC=${5:-ontap-nas}
NAME="${VM}-disk-${N}"

$OC -n "$NS" get vm "$VM" >/dev/null || { echo "VM $VM not found in $NS" >&2; exit 1; }
if $OC -n "$NS" get pvc "$NAME" >/dev/null 2>&1; then echo "PVC $NAME already exists in $NS" >&2; exit 1; fi

cat <<YAML | $OC apply -f -
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: ${NAME}
  namespace: ${NS}
  labels:
    example.com/vm: ${VM}
  annotations:
    cdi.kubevirt.io/storage.usePopulator: "false"
spec:
  source:
    blank: {}
  storage:
    storageClassName: ${SC}
    accessModes: [ReadWriteMany]
    volumeMode: Filesystem
    resources:
      requests:
        storage: ${SIZE}
YAML

echo "Waiting for $NAME ..."
$OC -n "$NS" wait dv "$NAME" --for=jsonpath='{.status.phase}'=Succeeded --timeout=10m
PV=$($OC -n "$NS" get pvc "$NAME" -o jsonpath='{.spec.volumeName}')
echo "ONTAP volume: $($OC get pv "$PV" -o jsonpath='{.spec.csi.volumeAttributes.internalName}')"
echo "Attach: VM $VM -> Configuration -> Storage -> Add -> existing PVC $NAME (virtio), then restart the VM if it is running."
