#!/usr/bin/env bash
# VM -> disk -> PVC -> StorageClass -> ONTAP volume, for the storage team (ONTAP System Manager: Storage -> Volumes).
# Usage: OC="oc --context ocp-a" scripts/vm-storage-map.sh [namespace]   (all namespaces without an argument)
# prime_<uuid> volumes: CDI named the temporary PVC prime-<UID of the final PVC>, so
#   oc get pvc -A -o custom-columns=NS:.metadata.namespace,PVC:.metadata.name,UID:.metadata.uid | grep -i <first 8 hex>
# finds the PVC for any prime_ volume.
set -euo pipefail
OC=${OC:-oc}
SCOPE=(-A); [ $# -ge 1 ] && SCOPE=(-n "$1")
printf "%-18s %-24s %-14s %-42s %-20s %s\n" NAMESPACE VM DISK PVC STORAGECLASS ONTAP_VOLUME
$OC get vm "${SCOPE[@]}" -o json | jq -r '
  .items[] | .metadata.namespace as $ns | .metadata.name as $vm
  | .spec.template.spec.volumes[]? | select(.persistentVolumeClaim or .dataVolume)
  | [$ns, $vm, .name, (.persistentVolumeClaim.claimName // .dataVolume.name)] | @tsv' |
while IFS=$'\t' read -r ns vm disk pvc; do
  pv=$($OC -n "$ns" get pvc "$pvc" -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)
  if [ -z "$pv" ]; then
    printf "%-18s %-24s %-14s %-42s %-20s %s\n" "$ns" "$vm" "$disk" "$pvc" "-" "(PVC missing)"; continue
  fi
  read -r sc ontap < <($OC get pv "$pv" -o jsonpath='{.spec.storageClassName} {.spec.csi.volumeAttributes.internalName}')
  printf "%-18s %-24s %-14s %-42s %-20s %s\n" "$ns" "$vm" "$disk" "$pvc" "$sc" "$ontap"
done
