# VM disk names in ONTAP

**Goal:** every VM disk in ONTAP carries the VM's name, so the storage team can tell which volume belongs to which VM
without asking the OpenShift team.


## Why some volumes are called `prime_<uuid>`

Trident names each ONTAP volume from the PVC it is asked to create (backend `nameTemplate`, already in git):

```
<cluster>_<namespace>_<pvc>        e.g. ocp_a_virtual_machines_vm-test01_linux_disk_0_29efc
```

The short suffix at the end (`_29efc`) is added by Trident to keep names unique.

For most VM disks, OpenShift Virtualization does not create the final PVC straight away. It first fills a temporary PVC
called `prime-<uuid>` (the CDI "populator") and then hands that volume over to the real PVC. Trident only ever saw the
temporary name, so the ONTAP volume is `ocp_a_<namespace>_prime_<uuid>`. Renaming the volume in ONTAP afterwards
breaks Trident's link to it: **never rename Trident volumes in ONTAP.**

## What sets the name, per way a disk is created

| Disk created by | PVC name | ONTAP volume | In git |
|---|---|---|---|
| MTV plan (VMware → OpenShift, or cluster → cluster on the hub) | `<vm>-disk-<n>` | `<cluster>_<ns>_<vm>_disk_<n>_<suffix>` | switch 19 `mtv-pvc-naming` (common/) stamps the PVC name template on every new plan |
| VM from a **Corp** template (Catalog → Template catalog → "Corp …") | `<vm>-disk-0` | `<cluster>_<ns>_<vm>_disk_0_<suffix>` | policy `vm-templates` |
| Extra disk with `scripts/add-vm-disk.sh` | `<vm>-disk-<n>` | `<cluster>_<ns>_<vm>_disk_<n>_<suffix>` | script |
| Red Hat template, InstanceTypes page, or **Add disk** in the console | console default | `prime_<uuid>` | cannot be changed |
| Storage migration (Migrate VirtualMachine storage) | `<pvc>-mig-<xxxx>` | `prime_<uuid>` | cannot be changed |

## 1. MTV plans (switch 19)

`common/manifests/mtv-pvc-naming/pvc-naming.yaml` gives every plan in `openshift-mtv` that has not started and has no
template of its own:

```
pvcNameTemplate: {{.TargetVmName}}-disk-{{.DiskIndex}}
pvcNameTemplateUseGenerateName: false
```

- `TargetVmName` (not `VmName`): the name MTV has already made valid for OpenShift. Source names with capitals make a
  plan "Not Ready" with `VmName`.
- On: ocp-a, hub-a, hub-b. Off: ocp-b (no MTV operator). Switch per cluster in `clusters/<cluster>/managedcluster.yaml`
  and `hubs/<hub>/local-cluster-labels.yaml`.
- VMware names with dots, capitals, underscores or spaces are handled by the same policy: it reads each plan's VM list and writes the template with a clean name for those VMs (host name only, lower case, `_` and spaces as `-`): `app-vm01.corp.example.com` → disks `app-vm01-disk-0`, `WEB_Server.corp.example.com` → `web-server-disk-0`. VMs added later are picked up within about 15 seconds. Only disk names change; the VM keeps the name MTV gives it. Two VMs in one plan with the same host name (`app1.a.edu`, `app1.b.edu`) would get the same disk names: put them in separate plans.
- A different naming for one plan: annotate the plan `example.com/pvc-names=manual`, then type the template on its **Details** tab (PVC name template) before Start. Started and finished plans are never changed.

**Check:** Governance → Policies → `common-mtv-pvc-naming` Compliant; a new plan's Details tab shows the template within
about 15 seconds.

## 2. New VMs: Corp templates

`policies/manifests/vm-templates/` holds copies of the Red Hat templates with two changes to the root disk:

```yaml
dataVolumeTemplates:
  - metadata:
      name: '${NAME}-disk-0'                              # was '${NAME}'
      annotations:
        cdi.kubevirt.io/storage.usePopulator: 'false'     # PVC created directly, no prime-<uuid>
...
volumes:
  - dataVolume:
      name: '${NAME}-disk-0'                              # must match the DataVolume name
    name: rootdisk
```

The SSP operator's labels and annotations are removed from the copies so the operator does not manage them.
Tested 19 Nov on ocp-a: `test-vm` → `ocp_a_virtual_machines_test_vm_disk_0_ceed`.

**Adding a template for another OS (Windows, RHEL 8, …):**
1. Virtualization → Templates → the Red Hat template → Actions → Clone (`corp-<os>-<flavor>`), project `openshift`.
2. Export its YAML, make the two changes above, remove `uid`, `resourceVersion`, `creationTimestamp`, `managedFields`,
   `app.kubernetes.io/*` labels and `operator-sdk/*` annotations, set `openshift.io/display-name` to "Corp …".
3. Save it in `policies/manifests/vm-templates/`, commit, push, sync `policies`.

**Use the Template catalog, not the InstanceTypes page**, for production VMs: the InstanceTypes page builds its own disk
(prime_ name). If the InstanceTypes page is used, add the annotation on its YAML tab before Create.

## 3. Extra disks: `scripts/add-vm-disk.sh`

The console's **Add disk** creates its own DataVolume with the populator, so the volume is `prime_<uuid>`. Create the disk
with the script instead, then attach it:

```bash
OC="oc $W" scripts/add-vm-disk.sh test-vm 1 10Gi           # namespace virtual-machines, ontap-nas by default
```

Then VM → Configuration → Storage → Add → use an existing PVC → `test-vm-disk-1`, interface virtio; restart the VM if it
is running. Number extra disks from 1.

## 4. Volumes that keep `prime_` names: the mapping report

```bash
OC="oc $W" scripts/vm-storage-map.sh                      # all namespaces; add a namespace to narrow it
```

prints VM → disk → PVC → StorageClass → ONTAP volume for every VM disk. For a single `prime_` volume, CDI names the
temporary PVC after the final PVC's UID, so the first 8 characters after `prime_` find it:

```bash
oc $W get pvc -A -o custom-columns=NS:.metadata.namespace,PVC:.metadata.name,UID:.metadata.uid | grep -i bb1639dc
```

The PV always holds the real ONTAP name: `oc $W get pv <pv> -o jsonpath='{.spec.csi.volumeAttributes.internalName}'`.

## Deleting a VM and its disks

`ontap-nas` has reclaim policy **Delete**: deleting the VM with its disks deletes the ONTAP volumes. The Shift StorageClass
`ontap-nas-vmw-c` has **Retain**: its volumes stay in ONTAP after the PVC is gone. Patch the PV to Delete first
(`oc $W patch pv <pv> -p '{"spec":{"persistentVolumeReclaimPolicy":"Delete"}}'`), or remove the volume in ONTAP after
the PV is deleted.
