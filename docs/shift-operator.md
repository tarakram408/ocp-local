# NetApp Shift operator on ocp-a (VMware to OpenShift with MTV)

The Shift operator runs NetApp's Shift toolkit inside OpenShift. An ordinary MTV migration plan from VMware maps a VM's
disks to the StorageClass `ontap-nas-vmw-c`; MTV marks the PVCs for Shift (`forklift.konveyor.io/netapp-shift: "true"`),
(`ontap-nas-vmw-b` for Bravo, `ontap-nas-vmw-a` for Alpha), and Shift converts the VMware disks in place on the NFS datastore (a clone on its SVM) instead of copying
them. Reference: [Manually deploy the Shift operator](https://docs.netapp.com/us-en/netapp-solutions-virtualization/migration/shift-toolkit-deploy-operator.html).

| Requirement | ocp-a |
|---|---|
| MTV 2.12 or later | 2.12.10 (policy `mtv-operator`) |
| Trident 26.06 or later, from OperatorHub | 26.6.2 (policy `trident-operator`) |
| NFS source datastores | Charlie (SVM_VMW_C), Bravo (SVM_VMW_B), Alpha (SVM_VMW_A) |
| Trident backend and StorageClass on the datastore's SVM | `ontap-nas-vmw-c`, `-vmw-b`, `-vmw-a` (policy `shift-backends`) |
| Images from quay.io | Reachable from ocp-a |

## What git provides

Policy `shift-operator` (primary cluster only, `dr-role: primary`; after `mtv-operator` and `shift-backends`), folder
`policies/manifests/shift-operator/`:

| File | Content |
|---|---|
| `00-namespace.yaml` | Namespace `shift` |
| `10-storageclass-shift.yaml` | Shift annotations on `ontap-nas-vmw-c`; the backend UUID is read from the cluster's TridentBackendConfig |
| `11-storageclass-shift-vmw-b.yaml`, `12-storageclass-shift-vmw-a.yaml` | The same for `ontap-nas-vmw-b` and `ontap-nas-vmw-a` |
| `20-filedb-pvc.yaml`, `21-logs-pvc.yaml` | NetApp's PVCs (50 GiB RWX each) for the Shift database and logs, `storageClassName: ontap-nas` |
| `30-shift-bundle.yaml` | NetApp's `deploy/bundle.yaml`, unchanged: SCC `shift-toolkit-stack`, service accounts, RBAC (ClusterRole on PVCs, StorageClasses, Trident backends; read on the secrets in `trident`), deployments `shift-toolkit` and `shift-toolkit-listener` (`quay.io/netapp/shift-toolkit:2.0.0`, `shift-toolkit-listener:2.0.0`), service `shift-toolkit-service` (3698, 3704) |

Not in git: the admin login and the TLS material (step 3). Until they exist the two pods wait in ContainerCreating.
ocp-a reaches quay.io (checked 13 Nov), so no offline installation is needed.

## Steps

Bastion variables: `H="--kubeconfig $HOME/hub-a.kubeconfig"`, `W="--kubeconfig $HOME/ocp-a.kubeconfig"`.

### 1. Push

```
cd ~/ocp-local/ocp-local
\cp -rv ~/ocp-local-main/policies/manifests/shift-operator policies/manifests/
\cp -v ~/ocp-local-main/policies/policy-generator.yaml policies/
\cp -v ~/ocp-local-main/docs/shift-operator.md docs/; \cp -v ~/ocp-local-main/README.md .
git add -A && git commit -m "Shift operator: NetApp manifests in the shift-operator policy" && git push
```

### 2. Check the policy applied

```
oc $H get policy -n ocp-a | grep shift-operator           # NonCompliant for a few minutes is normal while the pods wait
oc $W get ns shift; oc $W get pvc -n shift                 # shift-toolkit-filedb, shift-toolkit-logs Bound (ontap-nas)
oc $W get scc shift-toolkit-stack
oc $W get sc ontap-nas-vmw-c -o jsonpath='{.metadata.annotations}' | tr ',' '\n' | grep shift
```

### 3. Hub secrets (once, on hub-a); nothing by hand on ocp-a

| Hub secret (`policies` namespace) | Keys | Used by |
|---|---|---|
| `ontap-credentials-vmw-c` | `username`, `password` | `shift-backends` (Trident account `trident_admin` on SVM_VMW_C) |
| `ontap-credentials-vmw-b` | `username`, `password` | `shift-backends` (Trident account `trident_admin` on SVM_VMW_B) |
| `ontap-credentials-vmw-a` | `username`, `password` | `shift-backends` (Trident account `trident_admin` on SVM_VMW_A) |
| `shift-credentials-ocp-a` | `username`, `password` | `shift-operator` (Shift admin login) |
| `vcenter-credentials-ocp-a` | `user`, `password` | `mtv-vmware-source` (vCenter account for MTV) |

```
read -p "Shift admin user [admin]: " U; U=${U:-admin}; read -s -p "Password: " P; echo
oc $H -n policies create secret generic shift-credentials-ocp-a --from-literal=username="$U" --from-literal=password="$P"; unset P
read -p "vCenter user (user@vsphere.local): " U; read -s -p "Password: " P; echo
oc $H -n policies create secret generic vcenter-credentials-ocp-a --from-literal=user="$U" --from-literal=password="$P"; unset P
for s in shift-credentials-ocp-a vcenter-credentials-ocp-a; do oc $H -n policies label secret $s cluster.open-cluster-management.io/backup=""; done
```

With these in place, a (re)built ocp-a gets the Shift backend, the Shift operator, the vCenter provider and both maps
from the policies alone.

TLS (`40-tls.yaml`): the policy annotates NetApp's Service so OpenShift's service CA issues the certificate (secret
`shift-toolkit-tls`, renewed automatically about every 2 years), and fills the three ConfigMaps the bundle reads
(`shift-toolkit-service-server-crt`, `-server-key`, `-ca`) from it and from the namespace's service CA bundle. Nothing
to generate, nothing in git. After the policy first applies, or after a renewal (the pods use subPath mounts):

```
oc $W -n shift get secret shift-toolkit-tls                        # created by the service CA
oc $W -n shift rollout restart deploy shift-toolkit shift-toolkit-listener
```

The private key sits in a ConfigMap because NetApp's bundle mounts it from one; the policy has `recordDiff: None` so it
never appears in policy status. Keep `shift` restricted to cluster admins.
(13 Nov: a self-signed certificate was first made by hand; the policy replaced it.)

### 4. Check

```
oc $W get pods -n shift                                    # shift-toolkit-<hash>, shift-toolkit-listener-<hash> Running
oc $W logs -n shift deploy/shift-toolkit-listener --tail=20
oc $W logs -n shift deploy/shift-toolkit --tail=20
oc $H get policy -n ocp-a | grep shift-operator           # Compliant
```

If the pods were created before step 3 and stay in ContainerCreating: `oc $W -n shift rollout restart deploy`.

### 5. Migrate a VM

The vCenter provider `vcenter01` and the maps `vcenter01-to-ocp` come from the policy `mtv-vmware-source` (hub secret
`vcenter-credentials-ocp-a` once). Then per wave (`migration/README.md`):


1. ocp-a console > Migration for Virtualization > Migration plans > Create plan: source the VMware provider, target
   `host` (ocp-a), target project.
2. Storage map `vcenter01-to-ocp`: Charlie datastores to **`ontap-nas-vmw-c`**, Bravo to **`ontap-nas-vmw-b`**, Alpha to **`ontap-nas-vmw-a`**. Network map: each port group to the NAD of the same
   name (`migration/networkmap.yaml`).
3. Cold migration, VM target power state Power on. Start. MTV marks the PVCs (`forklift.konveyor.io/netapp-shift`),
   the listener hands them to Shift, Shift clones and converts the disks on the datastore's SVM.
4. Check: the PVCs on `ontap-nas-vmw-c` / `-vmw-b` / `-vmw-a` Bound, the VM running, same IP; `oc $W logs -n shift deploy/shift-toolkit-listener`.
5. After the migration, detach the VM from the VMware datastore: NetApp's clone split (ONTAP 9.17.1 or later; `vol move`
   before), then a **storage live migration to `ontap-nas`** (SVM_OCP_A), which SVM-DR replicates to DC2
   (`SVM_OCP_A -> SVM_OCP_A_SM`). SVM_VMW_C, SVM_VMW_B and SVM_VMW_A are not replicated. NetApp recommends source datastores of 5 TB or less.

## Bravo datastores (SVM_VMW_B, 23 Nov)

Same pattern as Charlie; policy `shift-backends` file `vmw-b.yaml`, annotations `shift-operator/11-...`, map entries in
`mtv-vmware-source/storagemap.yaml`.

| Item | Value |
|---|---|
| Management LIF | `vmw-b` `10.61.250.203` (nas01g) |
| Data LIFs | brav0 `.244` (03e), brav1 `.245` (03f), brav2 `.246` (03g), brav3 `.207` (03h), brav4 `.208` (03f), brav5 `.209` (03g), brav6 `.210` (03h) |
| Volumes | Log datastores `ds_l_0`-`2` (LIFs .211-.213, export policies `ds_l_0`-`2`) also on this SVM and in the map; `ds_b_0`, `_2` on N03e; `_1`, `_4`, `_5`, `_6` on N03f; `_3` on N03g; export policy `VMware_Default` (10.60.140.0/24) |
| Backend | `ontap-nas-vmw-b`: data LIF `.245` (03f, four of seven volumes); no aggregate pinned, so all four assigned aggregates are pools |
| Account | `trident_admin`, vsadmin, http + ontapi (storage team; `vsadmin` is locked, `snapcenter4` is SnapCenter's) |

Order: storage team creates the account and confirms `VMware_Default` is rw + superuser for 10.60.140.0/24; hub secret
`ontap-credentials-vmw-b` (`read -s`); push. Without the secret, `shift-backends` goes into template error and
`mtv-vmware-source` waits on it.

```
# ONTAP
vserver export-policy rule show -vserver SVM_VMW_B -policyname VMware_Default -fields clientmatch,rorule,rwrule,superuser
security login show -vserver SVM_VMW_B -user-or-group-name trident_admin
# ocp-a: management LIF reachable, data LIF answers on the storage network
oc $W debug node/<node> -q -- chroot /host curl -sk -o /dev/null -w '%{http_code}\n' --connect-timeout 5 https://10.61.250.203/
oc $W debug node/<node> -q -- chroot /host ping -c2 -W1 -I nfs222 10.60.140.245
# after the push
oc $W get tbc -n trident ontap-nas-vmw-b                    # Bound / Success
oc $W get sc ontap-nas-vmw-b -o jsonpath='{.metadata.annotations}' | tr ',' '\n' | grep shift
oc $W -n openshift-mtv get storagemap vcenter01-to-ocp -o jsonpath='{.status.conditions[*].type}{"\n"}'   # Ready
```

## Alpha datastores (SVM_VMW_A, 23 Nov)

Same pattern as Bravo; `shift-backends/vmw-a.yaml`, `shift-operator/12-...`, map entries `ds_a_0`-`2`.

| Item | Value |
|---|---|
| Management LIF | `vmw-a` `10.61.250.202` (nas01e) |
| Data LIFs | alph0 `.241` (03f), alph1 `.242` (03f), alph2 `.243` (03e) |
| Volumes | `ds_a_0` 11 TB and `ds_a_1` 10 TB on N03f, `ds_a_2` 10 TB on N03e; export policy `VMware_Default` (10.60.140.0/24, rw, superuser any) |
| Backend | `ontap-nas-vmw-a`: data LIF `.241` (03f, two of three volumes); no aggregate pinned |
| Account | `trident_admin`, vsadmin, http + ontapi (already present) |

The Alpha datastores are 10-11 TB, above NetApp's 5 TB recommendation for Shift sources: test with one VM first.
Checks: as for Bravo, with `10.61.250.202`, `10.60.140.241` and `ontap-nas-vmw-a`.

### Updating the images

Change the tags in `30-shift-bundle.yaml` (or replace the file with NetApp's new `deploy/bundle.yaml`), push; then
`oc $W -n shift rollout restart deploy` (the bundle uses `imagePullPolicy: Always`).

## Afterwards

- `shift-toolkit-access` (cluster-admin token for the external Shift server) stays until the first migration through the
  operator works; then remove its entry from `policy-generator.yaml` (`pruneObjectBehavior: DeleteAll` removes the
  service account and binding).
- Differences between NetApp's files: the README says images 1.0.0, the bundle uses 2.0.0 (the bundle wins); the
  bundle header says `--from-file=ca.crt=ca.cert`, the README `ca.crt=server.cert` (with a self-signed certificate they
  are the same file).
