# Warm migration from VMware with VDDK (ocp-a)

Two MTV providers point at the same vCenter (`vcenter01.example.com`), both from the policy `mtv-vmware-source`:

| Provider | Type | Disks land on | Use for |
|---|---|---|---|
| `vcenter01` | Cold, NetApp Shift (clone in place, no copy) | `ontap-nas-vmw-c` (SVM_VMW_C) | Default for VMs on the Charlie datastores: about 2 min (Linux) / 16 min (Windows incl. reboot and drivers) |
| `vcenter01-vddk` | **Warm**, VMware VDDK (copy over the network, VM keeps running) | `ontap-nas` (SVM_OCP_A, covered by SVM-DR) | Large VMs, VMs not on a Shift datastore, or VMs that should land straight on DR-covered storage |

First warm run, 17 Nov, `vm-test01-linux` (36 GiB): started 10:16, full copy done 10:21 with the VM running, cutover 10:22,
VM created and running 10:25. Downtime about 3–4 minutes, most of it the image conversion. No clone split or storage
move afterwards (unlike Shift).

## What git provides (`policies/manifests/mtv-vmware-source/`)

| File | Object |
|---|---|
| `provider-vddk.yaml` | Provider `vcenter01-vddk`, same login secret as `vcenter01`, `vddkInitImage` from the site value |
| `storagemap-vddk.yaml` | StorageMap `vcenter01-vddk-storagemap`: `ds_c_0`–`3` and (since 23 Nov) `ds_b_0`–`6` `ds_l_0`–`2` and `ds_a_0`–`2` → `ontap-nas` (RWX, Filesystem). Never the Shift class: MTV refuses warm plans to Shift storage |
| `networkmap-vddk.yaml` | NetworkMap `vcenter01-vddk-to-ocp`: same pairs as `vcenter01-to-ocp` (a map belongs to one provider; keep both in step) |
| `vddk-image-pullers.yaml` | RoleBinding: every service account may pull from `openshift-mtv` (the validation job and importer pods run in the target project) |
| `policies/site-values/ocp-a.yaml` | `vddkInitImage: image-registry.openshift-image-registry.svc:5000/openshift-mtv/vddk@sha256:a4ab33df…` (VDDK 8.0.3, pinned by digest) |

Not in git: the VDDK tarball and the image (VMware/Broadcom licence). Built on the cluster by `scripts/build-vddk-image.sh`.

## Build the VDDK image (once per VDDK version)

1. Download **VMware Virtual Disk Development Kit 8.0.3** (`VMware-vix-disklib-8.0.3-23950268.x86_64.tar.gz`) from the
   Broadcom developer portal and compare its sha256 with Broadcom's published checksum. Use only the official download.
2. On the bastion:
   ```bash
   cd ~/ocp-local/ocp-local
   scripts/build-vddk-image.sh ~/VMware-vix-disklib-8.0.3-23950268.x86_64.tar.gz 8.0.3
   ```
   The script checks the tarball has `lib64/libvixDiskLib.so.8`, builds the image on ocp-a (BuildConfig `vddk` in
   `openshift-mtv`, base `ubi9/ubi-minimal`, entrypoint copies `/vmware-vix-disklib-distrib` to `/opt`) and tags
   `openshift-mtv/vddk:8.0.3`.
3. Set `vddkInitImage` in `policies/site-values/ocp-a.yaml` to the **digest** the script prints
   (`…/openshift-mtv/vddk@sha256:<digest>`) and push. A digest pins the exact image: rebuilding the same tag cannot
   change what the provider runs, and a new digest makes MTV validate the image again.

## Run a warm migration

1. vSphere admin: enable **Changed Block Tracking** on the VM and each disk, then take and delete a snapshot (or power-cycle).
2. Check no VM with the same name exists in the target project, and that no copy of it is running elsewhere (same IP).
3. ocp-a console → Migration for Virtualization → Migration plans → Create: source `vcenter01-vddk`, target `host`,
   maps `vcenter01-vddk-to-ocp` / `vcenter01-vddk-storagemap`, type **Warm**.
4. Start. DiskTransfer copies the full disk; MTV then copies changes about hourly. Cutover shows **Paused**.
5. **Schedule cutover** (now or in the window): VMware VM shut down, last changes copied, conversion, VM created and started.
6. Validate: VM Running, console login, IP reachable, PVC on `ontap-nas`, source powered off without snapshots.

## Troubleshooting (all seen on 17 Nov)

| Plan concern / error | Cause | Fix |
|---|---|---|
| *NetApp Shift/Trident destination storage is not supported for warm migration* | Storage map targets `ontap-nas-vmw-c` | Use `vcenter01-vddk-storagemap` (→ `ontap-nas`); create a fresh plan |
| *VDDK image not set on the provider* | Plan uses `vcenter01` | Use `vcenter01-vddk` |
| `VDDKInitImageNotReady … authentication required` | Target project cannot pull from `openshift-mtv` | `vddk-image-pullers.yaml` (policy); delete the failed validation job |
| *VDDK init image is invalid* | Library not at `/vmware-vix-disklib-distrib/lib64/libvixDiskLib.so.8`, or wrong entrypoint | Rebuild with the script under a new tag; set the site value |
| DiskTransfer stays Pending; controller log mentions CBT or snapshots | CBT off, or snapshot problem in vCenter | Enable CBT (step 1) or fix the snapshot, then restart |
| *VMStorageNotMapped* (23 Nov, `app-vm01`) | VM on a Bravo datastore (`ds_b_*`), not in the VDDK map | `ds_b_0`–`6` added to `storagemap-vddk.yaml` |
| *VM PVC name template is invalid* (23 Nov) | VMware name with dots (`app-vm01.corp.example.com`): disk names are checked as labels | Switch 19 writes the short host name into the template (`app-vm01-disk-0`); wait about 15 s after adding VMs, refresh the plan |

## Second warm run, 23 Nov

Plan `app-vm01-migtest`, VM `app-vm01.corp.example.com` (Bravo datastore, 2 disks, 153,600 MB): started 10:35,
cutover 10:47 to 10:49, VM created 10:52, all steps done 11:12. Disks named by switch 19 (`app-vm01-disk-0`,
`-disk-1`). The *Wait for Windows guest reboots* step runs for every VM, Linux included.

```bash
oc $W -n openshift-mtv get provider vcenter01-vddk -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'
oc $W get jobs -A | grep -i vddk
oc $W -n virtual-machines get dv,pvc,pods | grep -i -E 'importer|<vm>'
oc $W -n openshift-mtv logs deploy/forklift-controller -c main --since=15m | grep -i -E 'error|<vm>'
```
