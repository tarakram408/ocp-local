# VM migration from VMware to ocp-a (MTV: Shift cold or VDDK warm)

Nothing in this folder is synced by Argo CD: migration is a one-time action per wave, applied by hand to the primary
cluster (`ocp-a`). The platform pieces come from policies: OpenShift Virtualization, MTV (`mtv-operator`), the VM
networks (49 NADs, `vm-networks`), the Shift backends and StorageClasses `ontap-nas-vmw-c`, `-vmw-b`, `-vmw-a`
(`shift-backends`), the Shift operator (`shift-operator`, docs/shift-operator.md) and the VDDK provider for warm
migrations (docs/vm-migration-warm-vddk.md).

How Shift works: an MTV plan maps each datastore to the Shift StorageClass of its SVM; MTV creates the disk PVCs there
with the annotation `forklift.konveyor.io/netapp-shift: "true"`; the Shift listener hands them to Shift, which clones
and converts the VMDKs in place on that SVM; MTV then creates and starts the VM. Cold only. For warm migrations use
provider `vcenter01-vddk` with maps `vcenter01-vddk-to-ocp` / `vcenter01-vddk-storagemap` (disks copied to
`ontap-nas`; Charlie, Bravo, Log and Alpha datastores mapped). Both storage maps list each datastore by vCenter id and
name (`scripts/datastore-ids.sh`) and are owned by git: console edits are reverted.

The provider and both maps come from the policy `mtv-vmware-source` (`policies/manifests/mtv-vmware-source/`):
provider `vcenter01` (`https://vcenter01.example.com/sdk`, site value `vcenterFQDN`), network map and
storage map `vcenter01-to-ocp` (Charlie `ds_c_0`-`3` to `ontap-nas-vmw-c`, Bravo `ds_b_0`-`6` and Log `ds_l_0`-`2` to `ontap-nas-vmw-b`, Alpha `ds_a_0`-`2` to `ontap-nas-vmw-a`). The vCenter
login is the hub secret `policies/vcenter-credentials-ocp-a` (keys `user` and `password`; command in `provider.yaml`).
The vCenter certificate chain is public and lives in git (`vcenter-chain.pem`, and base64 in `provider.yaml`): vCenter's
certificate expires 6 Dec 2026; a renewal by GlobalSign needs no change. Only the plans are applied here, one per wave.

| File | What |
|---|---|
| `plan-wave-1.yaml` | One plan per wave: VM list, target namespace, cold, power on |

## Per wave (bastion, `W="--kubeconfig $HOME/ocp-a.kubeconfig"`)

```
oc $W get provider vcenter01 -n openshift-mtv              # Ready, Connected, Inventory True
oc $W get networkmap,storagemap -n openshift-mtv             # vcenter01-to-ocp Ready
cp plan-wave-1.yaml plan-wave-N.yaml                          # name, VMs (on a mapped datastore), target namespace
oc $W apply -f plan-wave-N.yaml && oc $W get plan -n openshift-mtv   # Ready, then Start (console or Migration)
oc $W logs -n shift deploy/shift-toolkit-listener -f          # Shift handling the PVCs
```

Windows VMs end with the step WaitForGuestReboots: the first boot installs the virtio drivers and the guest agent and
reboots by itself (about 10 minutes for vm-test01). Afterwards: VMware Tools removal (scripts/Remove-VMwareTools.ps1.txt (rename to .ps1 on the VM)),
source VM left off in vCenter, storage live migration to `ontap-nas` (SVM-DR; no clone split needed when the disks are
copied off the clone), then delete the Released Shift PV (Retain) so Trident removes the clone. After a storage
migration, set the new PV to Retain until the VM is confirmed on it (RCA MIG-13: a deleted DataVolume took a VM's
new PVC with it). Tag the VMs: `OC="oc $W" scripts/tag-vm.sh --list`.

First migration, 13 Nov: plan `vspheretest1`, VM `vm-test01` (Windows, 2 vCPU, 4 GiB, one 90 GiB disk) from vm_char to
ocp-a in 16 minutes: disk clone about 1 minute, conversion 3 minutes, first boot and reboot 12 minutes.

## To confirm with NetApp before the first wave

Taken from the Shift Toolkit prerequisites; confirm each against the version NetApp will run.

- **Where the VMDKs live.** The toolkit clones disks on ONTAP, so each VM's datastore must be an NFS volume on the SVM that `ocp-a` uses. A VM on another SVM or on non-NFS storage must be moved in vSphere first.
- **Datastore layout.** If several VMDKs share a qtree, the toolkit uses the `ontap-nas-economy` driver, which needs a second Trident backend and storage class not yet included in this repository.
- **Target namespace.** NetApp's documentation states that VMs land in `default` unless the plan says otherwise. The plans here set `targetNamespace`; confirm the toolkit keeps it.
- **Networks.** VM networks must already exist as NetworkAttachmentDefinitions with the right VLANs. IP addresses and VLANs do not change during migration, and MAC addresses are kept.
- **Matching names.** The vCenter and OpenShift endpoints (FQDN, not IP) must be written identically in MTV and in the toolkit.
- **Guests.** VMware Tools running, guest OS supported for conversion, VMs powered off for the run.
- **Disk counts.** A plan becomes ready to start only when the number of imported PVCs equals the VM's VMDK count.
