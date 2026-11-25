#!/usr/bin/env bash
# Look up vCenter datastore ids in the MTV inventory, for the storage maps in
# policies/manifests/mtv-vmware-source/ (each entry carries the datastore's id and name).
#
# Usage (from the repository root on the bastion):
#   OC="oc $W" scripts/datastore-ids.sh                            # every datastore: name and id
#   OC="oc $W" scripts/datastore-ids.sh '^ds_a_'               # only names matching a regex
#   OC="oc $W" scripts/datastore-ids.sh '^ds_a_7$' ontap-nas   # also print ready-to-paste map entries
#   PROVIDER=vcenter01-vddk OC="oc $W" scripts/datastore-ids.sh ...   # another vSphere provider
#
# With a StorageClass as the second argument, entries are printed in the format of the maps:
#   ontap-nas (warm map storagemap-vddk.yaml) adds accessMode/volumeMode; any other class (Shift map) does not.
# Read-only. Uses a 10-minute token of MTV's own service account, because the bastion kubeconfig logs in with a
# client certificate (oc whoami -t has no token).
set -euo pipefail
OC=${OC:-oc}
NS=openshift-mtv
PROVIDER=${PROVIDER:-vcenter01}
FILTER=${1:-.}
SC=${2:-}

uid=$($OC -n $NS get provider "$PROVIDER" -o jsonpath='{.metadata.uid}')
host=$($OC -n $NS get route forklift-inventory -o jsonpath='{.spec.host}')
tok=$($OC -n $NS create token forklift-controller --duration=10m)
json=$(curl -sk -H "Authorization: Bearer $tok" "https://$host/providers/vsphere/$uid/datastores")
unset tok

rows=$(echo "$json" | jq -r --arg f "$FILTER" '.[] | select(.name | test($f)) | "\(.name)\t\(.id)"' | sort -V)
[ -n "$rows" ] || { echo "No datastore matches '$FILTER' on provider $PROVIDER" >&2; exit 1; }

if [ -z "$SC" ]; then
  printf 'NAME\tID\n%s\n' "$rows" | column -t
  exit 0
fi

while IFS=$'\t' read -r name id; do
  echo "    - source:"
  echo "        id: $id"
  echo "        name: $name"
  echo "      destination:"
  echo "        storageClass: $SC"
  if [ "$SC" = "ontap-nas" ]; then
    echo "        accessMode: ReadWriteMany"
    echo "        volumeMode: Filesystem"
  fi
done <<< "$rows"
