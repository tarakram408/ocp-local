# Virtual media test helper for one UCS blade (CIMC Redfish), used for the 30 Oct mount investigation.
# Usage (bash, on the bastion):  source scripts/redfish-vmedia.sh <blade KVM IP> [cluster]
#   st          show the CIMC-mapped vDVD slot (VirtualMedia/3)
#   ins <url>   InsertMedia exactly as Ironic sends it (Image, Inserted, WriteProtected), wait 45 s, show the slot
#   ins2 <url>  the same plus TransferProtocolType=HTTP
#   ej          EjectMedia
#   task <id>   show a CIMC task (each insert returns one: "vmedia insert local media monitor")
# The BMC login is read from <cluster>-bmc-secret on the hub (default ocp-a); nothing is written to disk.
# Inserting media does not power or boot the blade. Run "unset U P" when done.
K="--kubeconfig $HOME/hub-a.kubeconfig"; B=$1; C=${2:-ocp-a}
U=$(oc $K get secret $C-bmc-secret -n $C -o jsonpath='{.data.username}' | base64 -d)
P=$(oc $K get secret $C-bmc-secret -n $C -o jsonpath='{.data.password}' | base64 -d)
VM=https://$B/redfish/v1/Managers/CIMC/VirtualMedia/3
st()   { curl -sk -u "$U:$P" "$VM" | jq '{Name,MediaTypes,Inserted,Image,ConnectedVia,Status}'; }
_ins() {
  curl -sk -u "$U:$P" -X POST -H 'Content-Type: application/json' -w " HTTP %{http_code}\n" \
    "$VM/Actions/VirtualMedia.InsertMedia" -d "$1"
  sleep 45
  curl -sk -u "$U:$P" "$VM" | jq -c '{Inserted,Image,Status}'
}
ins()  { _ins "{\"Image\":\"$1\",\"Inserted\":true,\"WriteProtected\":true}"; }
ins2() { _ins "{\"Image\":\"$1\",\"Inserted\":true,\"WriteProtected\":true,\"TransferProtocolType\":\"HTTP\"}"; }
ej()   { curl -sk -u "$U:$P" -X POST -H 'Content-Type: application/json' -d '{}' -w " HTTP %{http_code}\n" "$VM/Actions/VirtualMedia.EjectMedia"; }
task() { curl -sk -u "$U:$P" "https://$B/redfish/v1/TaskService/Tasks/$1" | jq -c '{Id,TaskState,TaskStatus,StartTime,EndTime,Messages:[.Messages[]?.Message]}'; }
echo "ready for $B ($C): st | ins <url> | ins2 <url> | ej | task <id>"
