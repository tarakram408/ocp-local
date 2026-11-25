# scripts

Run from the repository root on the bastion; `OC="oc $W"` (or `$C`, `$H`) selects the cluster.

| Script | Use |
|---|---|
| `tag-vm.sh` | Corp tags on existing or migrated VMs. `--list` shows the VMs still missing tags; no arguments: numbered list, pick one, answer the prompts (arrow keys and line editing work), repeat; `<ns> <vm>` asks for one VM; `<ns> <vm> Key=Value…` without questions; `--csv wave-N-tags.csv` for a wave from the vSphere tag export. Fixed values are stored in their standard spelling. `docs/vm-tagging.md` |
| `add-vm-disk.sh` | Extra disk named `<vm>-disk-<n>` (`add-vm-disk.sh <vm> <n> <size>`), so the ONTAP volume carries the VM name; attach it in the console afterwards. `docs/vm-disk-naming.md` |
| `vm-storage-map.sh` | VM → disk → PVC → StorageClass → ONTAP volume, for every VM (finds `prime_<uuid>` volumes). Read-only |
| `datastore-ids.sh` | vCenter datastore ids from the MTV inventory for the storage maps, which list each datastore by id and name. `datastore-ids.sh '^ds_a_'` prints name and id; add a StorageClass (`ontap-nas` for the warm map, `ontap-nas-vmw-*` for the Shift map) to print ready-to-paste entries; `PROVIDER=vcenter01-vddk` for the warm provider. Read-only |
| `build-vddk-image.sh` | Builds the VMware VDDK init image on ocp-a from the Broadcom tarball and prints the digest for the site value `vddkInitImage`. `docs/vm-migration-warm-vddk.md` |
| `Remove-VMwareTools.ps1.txt` | Run on Windows VMs after migration to remove VMware Tools (rename to `.ps1`) |
| `redfish-vmedia.sh` | Test CIMC virtual media on one blade (insert, eject, task status). `docs/bare-metal-provisioning.md`, "Virtual media investigation" |
| `set-node-kargs.py` | **Fallback only.** Adds `installerArgs` (static network as kernel arguments) to every node of a ClusterInstance, for installs booted from one shared discovery ISO. Not used in normal installs: `nodeNetwork` already carries the network when the hub boots each blade with its own ISO. It also duplicates the network definition, so revert it once the install is done |
