# ocp-local

> Sanitized template of an RHACM + Argo CD GitOps repository for OpenShift Virtualization on bare metal with NetApp ONTAP (Trident, Shift, MTV). Cluster names (`hub-a`, `hub-b`, `ocp-a`, `ocp-b`), domains (`example.com`), SVMs, addresses, VM networks and credentials are placeholders: search for `CHANGEME` and replace the example values before use.

## Where to change what

Every common change, and the file that holds it. Links open the file; the last column names anything else that must change with it. After a push, Argo CD on `hub-a` applies the change within about three minutes (to apply it at once, and for hub-b's own `common-config`: [Making a change](docs/gitops-operations-guide.md#making-a-change)). Worked examples with full YAML: [section 13 of the operations guide](docs/gitops-operations-guide.md#13-worked-examples-adding-and-changing-things).

**Networking**

| To | Edit | Also |
|---|---|---|
| Add a VM network (VLAN / port group) | [policies/manifests/vm-networks/vm-networks.yaml](policies/manifests/vm-networks/vm-networks.yaml) (one NAD, both clusters) | Hub maps [policies/manifests/mtv-hub-maps/maps.yaml](policies/manifests/mtv-hub-maps/maps.yaml) (both directions); from VMware: [networkmap.yaml](policies/manifests/mtv-vmware-source/networkmap.yaml) **and** [networkmap-vddk.yaml](policies/manifests/mtv-vmware-source/networkmap-vddk.yaml), migration/vmware-port-groups.csv. [Guide 13.2](docs/gitops-operations-guide.md#132-add-a-vm-network-vlan) |
| Add or change a VMware → OpenShift network map entry | [policies/manifests/mtv-vmware-source/networkmap.yaml](policies/manifests/mtv-vmware-source/networkmap.yaml) (Shift, cold) | Same entry in [networkmap-vddk.yaml](policies/manifests/mtv-vmware-source/networkmap-vddk.yaml) (VDDK, warm). Existing plans keep their own copy: recreate them |
| Change the VM uplink (bond2 → `br-vm` → `vm-trunk`) | [policies/manifests/node-network/vm-uplink.yaml](policies/manifests/node-network/vm-uplink.yaml) | — |
| Change a node's storage address, or add a node's storage network | [policies/manifests/storage-network/ocp-a.yaml](policies/manifests/storage-network/ocp-a.yaml), [ocp-b.yaml](policies/manifests/storage-network/ocp-b.yaml) (one NNCP per node) | Hubs: [hubs/hub-a/storage-network.yaml](hubs/hub-a/storage-network.yaml), [hubs/hub-b/storage-network.yaml](hubs/hub-b/storage-network.yaml) |
| Live migration network (bond3, VLAN 333) | [policies/manifests/migration-network/migration-network.yaml](policies/manifests/migration-network/migration-network.yaml) | Address pool per cluster: `liveMigrationSubnets` / `liveMigrationExclude` in [policies/site-values/](policies/site-values/) (the two pools must never overlap) |
| VM network examples (UDN, CUDN, NAD) | [examples/vm-networks/](examples/vm-networks/) | Reference only, not applied |
| Pod egress through the host routing table | [common/manifests/routing-via-host/network.yaml](common/manifests/routing-via-host/network.yaml) | Switch 16 |
| LLDP on the vNICs | [common/manifests/lldp/lldp.yaml](common/manifests/lldp/lldp.yaml) | Switch 9 |
| MetalLB address pool | `metallbAddresses` in [policies/site-values/](policies/site-values/) or [hubs/&lt;hub&gt;/site-values.yaml](hubs/hub-a/site-values.yaml) | Switch 10; manifests in [common/manifests/metallb-config/](common/manifests/metallb-config/) |

**Storage**

| To | Edit | Also |
|---|---|---|
| Production ONTAP backends and `ontap-nas` StorageClass | [policies/manifests/trident-config/trident.yaml](policies/manifests/trident-config/trident.yaml), [storageclass.yaml](policies/manifests/trident-config/storageclass.yaml) | SVM, LIFs, aggregates per cluster: `ontap*` keys in [policies/site-values/](policies/site-values/); login: hub secret `ontap-credentials-<cluster>` |
| Add a Shift backend for another VMware SVM | New file in [policies/manifests/shift-backends/](policies/manifests/shift-backends/) (copy [vmw-a.yaml](policies/manifests/shift-backends/vmw-a.yaml)) | Shift StorageClass in [policies/manifests/shift-operator/](policies/manifests/shift-operator/) (copy [12-storageclass-shift-vmw-a.yaml](policies/manifests/shift-operator/12-storageclass-shift-vmw-a.yaml)); StorageProfile in [virtualization-config/storageprofile.yaml](policies/manifests/virtualization-config/storageprofile.yaml); hub maps in [mtv-hub-maps/maps.yaml](policies/manifests/mtv-hub-maps/maps.yaml); hub secret `ontap-credentials-<svm>`; comment in [policies/policy-generator.yaml](policies/policy-generator.yaml). [Guide 13.5](docs/gitops-operations-guide.md#135-add-a-storage-backend-or-storageclass) |
| StorageProfile (access and volume mode, clone strategy) | [policies/manifests/virtualization-config/storageprofile.yaml](policies/manifests/virtualization-config/storageprofile.yaml) | One per StorageClass used by VMs |
| Hub storage (Trident on a hub) | [bootstrap/hub-a/hub-storage/](bootstrap/hub-a/hub-storage/), [bootstrap/hub-b/hub-storage/](bootstrap/hub-b/hub-storage/) | Applied by hand at build time |
| Internal image registry size | `imageRegistrySize` in [common/values.yaml](common/values.yaml) | Switch 13; [common/manifests/image-registry/](common/manifests/image-registry/) |
| Trident Protect (install, prerequisites, replication examples) | [argocd-apps/trident-protect-appset.yaml](argocd-apps/trident-protect-appset.yaml), [policies/manifests/trident-protect-prereqs/prereqs.yaml](policies/manifests/trident-protect-prereqs/prereqs.yaml) | Examples: [examples/trident-protect/](examples/trident-protect/). hub-b copy: [argocd-apps-hub-b/](argocd-apps-hub-b/) |

**VMware migration (MTV, Shift, VDDK)**

| To | Edit | Also |
|---|---|---|
| Map another datastore (Shift, cold) | [policies/manifests/mtv-vmware-source/storagemap.yaml](policies/manifests/mtv-vmware-source/storagemap.yaml) (id **and** name) | Ids: [scripts/datastore-ids.sh](scripts/datastore-ids.sh). The SVM needs a Shift backend first (Storage, above) |
| Map another datastore (VDDK, warm) | [policies/manifests/mtv-vmware-source/storagemap-vddk.yaml](policies/manifests/mtv-vmware-source/storagemap-vddk.yaml) (id **and** name, to `ontap-nas`) | Ids: [scripts/datastore-ids.sh](scripts/datastore-ids.sh) with `PROVIDER=vcenter01-vddk` |
| vCenter provider (Shift / VDDK) | [provider.yaml](policies/manifests/mtv-vmware-source/provider.yaml), [provider-vddk.yaml](policies/manifests/mtv-vmware-source/provider-vddk.yaml) | `vcenterFQDN`, `vddkInitImage` in [policies/site-values/ocp-a.yaml](policies/site-values/ocp-a.yaml); login: hub secret `vcenter-credentials-<cluster>`; chain: migration/vcenter-chain.pem. [Guide 13.4](docs/gitops-operations-guide.md#134-add-a-vcenter-as-an-mtv-source) |
| Rebuild the VDDK image | [scripts/build-vddk-image.sh](scripts/build-vddk-image.sh) | Put the printed digest in `vddkInitImage` |
| Create a migration wave | Copy [migration/plan-wave-1.yaml](migration/plan-wave-1.yaml) (applied by hand, not synced) | [migration/README.md](migration/README.md), [Guide 13.11](docs/gitops-operations-guide.md#1311-run-a-vmware-migration-wave). `migration/networkmap.yaml`, `storagemap.yaml` and `provider-vsphere.yaml` are the pre-policy copies and are not applied |
| MTV settings on ocp-a (ForkliftController) | [policies/manifests/mtv-config/forkliftcontroller.yaml](policies/manifests/mtv-config/forkliftcontroller.yaml) | Operator: [mtv-operator/operator.yaml](policies/manifests/mtv-operator/operator.yaml) |
| Disk (PVC) names of MTV plans | [common/manifests/mtv-pvc-naming/pvc-naming.yaml](common/manifests/mtv-pvc-naming/pvc-naming.yaml) | Switch 19; [docs/vm-disk-naming.md](docs/vm-disk-naming.md) |
| Shift operator (bundle, credentials, TLS, PVCs) | [policies/manifests/shift-operator/](policies/manifests/shift-operator/) | [docs/shift-operator.md](docs/shift-operator.md) |
| After migration (VMware Tools, tags) | [scripts/Remove-VMwareTools.ps1.txt](scripts/Remove-VMwareTools.ps1.txt), [scripts/tag-vm.sh](scripts/tag-vm.sh) | [docs/vm-tagging.md](docs/vm-tagging.md) |

**Moving VMs between ocp-a and ocp-b (hub MTV)**

| To | Edit | Also |
|---|---|---|
| Network and storage maps between the clusters | [policies/manifests/mtv-hub-maps/maps.yaml](policies/manifests/mtv-hub-maps/maps.yaml) | Regenerate when a NAD is added |
| Register a cluster as a provider on the hub | [policies/manifests/mtv-hub-providers/providers.yaml](policies/manifests/mtv-hub-providers/providers.yaml), [mtv-provider-access/clusterrolebinding.yaml](policies/manifests/mtv-provider-access/clusterrolebinding.yaml) | Switch 17 (`mtv-provider`) on the cluster |
| Cross-cluster live migration settings, KubeVirt CA exchange | [policies/manifests/mtv-hub-settings/forkliftcontroller.yaml](policies/manifests/mtv-hub-settings/forkliftcontroller.yaml), [kubevirt-ca-exchange.yaml](policies/manifests/mtv-hub-settings/kubevirt-ca-exchange.yaml) | `decentralizedLiveMigration` in [virtualization-config/hyperconverged.yaml](policies/manifests/virtualization-config/hyperconverged.yaml); [docs/vm-migration-between-clusters.md](docs/vm-migration-between-clusters.md) |

**Virtual machines and OpenShift Virtualization**

| To | Edit | Also |
|---|---|---|
| HyperConverged (live migration limits, feature gates, CPU model) | [policies/manifests/virtualization-config/hyperconverged.yaml](policies/manifests/virtualization-config/hyperconverged.yaml) | Operator: [virtualization-operator/operator.yaml](policies/manifests/virtualization-operator/operator.yaml) |
| Add a VM namespace (both clusters) | [policies/manifests/vm-namespaces/vm-workloads.yaml](policies/manifests/vm-namespaces/vm-workloads.yaml) | Namespace prefix rule: `namespacePrefix` in [common/values.yaml](common/values.yaml) |
| Corp VM templates | [policies/manifests/vm-templates/](policies/manifests/vm-templates/) (copy [corp-rhel9-server-small.yaml](policies/manifests/vm-templates/corp-rhel9-server-small.yaml)) | [Guide 13.16](docs/gitops-operations-guide.md#1316-add-a-corp-template-for-another-os) |
| Required VM tags (keys, allowed values, Warn/Deny) | [policies/manifests/vm-tagging/vm-tagging.yaml](policies/manifests/vm-tagging/vm-tagging.yaml), report: [vm-tagging-report/](policies/manifests/vm-tagging-report/) | `vmTagEnforcement` in [policies/site-values/](policies/site-values/); [docs/vm-tagging.md](docs/vm-tagging.md) |
| Extra VM disk with a readable ONTAP name | [scripts/add-vm-disk.sh](scripts/add-vm-disk.sh) | Mapping report: [scripts/vm-storage-map.sh](scripts/vm-storage-map.sh) |
| VM rebalancing (descheduler) | [policies/manifests/descheduler-config/kubedescheduler.yaml](policies/manifests/descheduler-config/kubedescheduler.yaml) | `deschedulerMode` (Predictive / Automatic) in [policies/site-values/](policies/site-values/) |
| Control plane nodes run VMs | [policies/manifests/scheduler/masters-schedulable.yaml](policies/manifests/scheduler/masters-schedulable.yaml) | — |
| Applications deployed by Argo CD to the clusters | [apps/example-app/](apps/example-app/) | Targeting: [argocd-apps/workloads-appset.yaml](argocd-apps/workloads-appset.yaml), Placement in [hub/gitops/acm-integration.yaml](hub/gitops/acm-integration.yaml) |

**Clusters, hubs and nodes**

| To | Edit | Also |
|---|---|---|
| Add a node to ocp-a or ocp-b | `liveMigrationExclude` in [policies/site-values/](policies/site-values/), storage NNCP in [policies/manifests/storage-network/](policies/manifests/storage-network/) | [Guide 13.1](docs/gitops-operations-guide.md#131-add-a-node-to-a-production-cluster) |
| Add a production cluster | New folder under [clusters/](clusters/) (copy [clusters/ocp-b/](clusters/ocp-b/)), list it in [clusters/kustomization.yaml](clusters/kustomization.yaml) | New site values in [policies/site-values/](policies/site-values/) and [policies/kustomization.yaml](policies/kustomization.yaml). [Guide 13.10](docs/gitops-operations-guide.md#1310-add-a-third-production-cluster) |
| Cluster labels (env, dr-role, switches) | [clusters/&lt;cluster&gt;/managedcluster.yaml](clusters/ocp-a/managedcluster.yaml) **and** `extraLabels` in [clusterinstance.yaml](clusters/ocp-a/clusterinstance.yaml) | Keep both the same |
| A per-cluster value (banner, SVM, vCenter, alert name) | [policies/site-values/ocp-a.yaml](policies/site-values/ocp-a.yaml), [ocp-b.yaml](policies/site-values/ocp-b.yaml); hubs: [hubs/hub-a/site-values.yaml](hubs/hub-a/site-values.yaml), [hubs/hub-b/site-values.yaml](hubs/hub-b/site-values.yaml) | [Guide 13.7](docs/gitops-operations-guide.md#137-change-a-per-cluster-setting) |
| Hub components (MultiClusterHub, assisted service, image set, search, backup location, kubelet) | [hub/](hub/) ([acm/](hub/acm/), [backup/](hub/backup/), [node/kubeletconfig.yaml](hub/node/kubeletconfig.yaml)) | Per-hub additions: [hubs/hub-a/kustomization.yaml](hubs/hub-a/kustomization.yaml), [hubs/hub-b/kustomization.yaml](hubs/hub-b/kustomization.yaml) |
| Hub backup schedule / standby restore | [hubs/hub-a/backup-schedule.yaml](hubs/hub-a/backup-schedule.yaml), [hubs/hub-b/restore.yaml](hubs/hub-b/restore.yaml) | [hub/backup/README.md](hub/backup/README.md) |
| OpenShift release for new installs | [hub/acm/clusterimageset-4.22.yaml](hub/acm/clusterimageset-4.22.yaml), `osImages` in [hub/acm/agentserviceconfig.yaml](hub/acm/agentserviceconfig.yaml) | Upgrades: [clusters/&lt;cluster&gt;/clustercurator-upgrade.yaml.example](clusters/ocp-a/clustercurator-upgrade.yaml.example), [Guide 13.12](docs/gitops-operations-guide.md#1312-upgrade-openshift) |
| Install-time secrets (pull secret, BMC) | [bootstrap/secrets/install-secrets.yaml.example](bootstrap/secrets/install-secrets.yaml.example) | Never committed with values; copied by [policies/manifests/install-secrets/](policies/manifests/install-secrets/) |
| Node kernel arguments, virtual media boot | [scripts/set-node-kargs.py](scripts/set-node-kargs.py), [scripts/redfish-vmedia.sh](scripts/redfish-vmedia.sh) | [docs/bare-metal-provisioning.md](docs/bare-metal-provisioning.md) |

**Day-2 features on all four clusters (`common/`, switches 1–21)**

| To | Edit | Also |
|---|---|---|
| Switch a feature on or off for a cluster | Production: [clusters/&lt;cluster&gt;/managedcluster.yaml](clusters/ocp-a/managedcluster.yaml) (+ `clusterinstance.yaml`); hubs: [hubs/hub-a/local-cluster-labels.yaml](hubs/hub-a/local-cluster-labels.yaml), [hubs/hub-b/local-cluster-labels.yaml](hubs/hub-b/local-cluster-labels.yaml) | What each switch does: [common/README.md](common/README.md) |
| Values shared by every cluster (LDAP, groups, SMTP, schedules) | [common/values.yaml](common/values.yaml) | — |
| Add a new day-2 feature | New folder in [common/manifests/](common/manifests/), a policy in [common/policy-generator.yaml](common/policy-generator.yaml) | A switch in the cluster and hub label files; rows in [common/README.md](common/README.md) and the switch table below |
| Login (htpasswd, AD) | [common/manifests/oauth/oauth.yaml](common/manifests/oauth/oauth.yaml), placement [common/placements/oauth.yaml](common/placements/oauth.yaml) | LDAP values in [common/values.yaml](common/values.yaml); hub secrets `htpasswd`, `ldap-bind` ([common/hub-secrets.yaml.example](common/hub-secrets.yaml.example)) |
| AD groups synced, and their access | `ldapGroupDNs`, `group*` in [common/values.yaml](common/values.yaml) | Bindings: [common/manifests/rbac/rbac.yaml](common/manifests/rbac/rbac.yaml), Argo CD: [argocd-rbac/](common/manifests/argocd-rbac/). [Guide 13.9](docs/gitops-operations-guide.md#139-give-an-ad-group-access) |
| Alert e-mails (routes, receivers) | [common/alerting/alertmanager.yaml](common/alerting/alertmanager.yaml) | SMTP in [common/values.yaml](common/values.yaml); sender and cluster name in site values |
| Log forwarding to syslog (outputs, collector resources) | [common/manifests/log-forwarding/forwarder.yaml](common/manifests/log-forwarding/forwarder.yaml) | Operator: [log-forwarding-operator/operator.yaml](common/manifests/log-forwarding-operator/operator.yaml); switch 20 |
| etcd backup / defragmentation schedule | `etcdBackupSchedule`, `etcdBackupRetain`, `etcdDefragSchedule` in [common/values.yaml](common/values.yaml) | [common/manifests/etcd-backup/](common/manifests/etcd-backup/), [etcd-defrag/](common/manifests/etcd-defrag/); switches 14, 21 |
| Console logo, product name, banner | [common/manifests/console/](common/manifests/console/) | Banner text and colours in site values |
| Hub metrics (Observability) | [common/manifests/observability/multiclusterobservability.yaml](common/manifests/observability/multiclusterobservability.yaml) | Bucket secret: [hub/observability/thanos-object-storage.yaml.example](hub/observability/thanos-object-storage.yaml.example) |
| NTP, multipath, etcd encryption, namespace template, ingress certificate, DII collector | [ntp/](common/manifests/ntp/), [multipath/](common/manifests/multipath/), [etcd-encryption/](common/manifests/etcd-encryption/), [namespace-template/](common/manifests/namespace-template/), [ingress-cert/](common/manifests/ingress-cert/), [dii-collector/](common/manifests/dii-collector/) under [common/manifests/](common/manifests/) | [docs/dii-collector.md](docs/dii-collector.md) |

**Production platform policies (`policies/`)**

| To | Edit | Also |
|---|---|---|
| Add an operator to the production clusters | New folders in [policies/manifests/](policies/manifests/) (operator + config), two entries in [policies/policy-generator.yaml](policies/policy-generator.yaml) | [Guide 13.3](docs/gitops-operations-guide.md#133-add-an-operator) |
| Which clusters a policy reaches | Placement of that policy in [policies/policy-generator.yaml](policies/policy-generator.yaml) | Labels on the cluster (above) |
| Hardening, guardrails, compliance scans | [policies/manifests/hardening/](policies/manifests/hardening/), [guardrails/](policies/manifests/guardrails/), [compliance-scans/](policies/manifests/compliance-scans/) | — |
| Node Maintenance, nmstate operators | [policies/manifests/nodemaintenance-operator/](policies/manifests/nodemaintenance-operator/), [nmstate-operator/](policies/manifests/nmstate-operator/), [nmstate-config/](policies/manifests/nmstate-config/) | — |
| Site-specific settings (primary / failover) | [policies/manifests/site-primary/](policies/manifests/site-primary/), [site-failover/](policies/manifests/site-failover/) | Placeholders today |

**GitOps plumbing (Argo CD)**

| To | Edit | Also |
|---|---|---|
| Argo CD applications on hub-a | [argocd-apps/](argocd-apps/) | Root: [bootstrap/hub-a/root-app.yaml](bootstrap/hub-a/root-app.yaml) (applied once by hand) |
| Argo CD applications on hub-b | [argocd-apps-hub-b/](argocd-apps-hub-b/) | Root: [bootstrap/hub-b/root-app.yaml](bootstrap/hub-b/root-app.yaml) |
| Argo CD permissions, PolicyGenerator plugin | [bootstrap/argocd/](bootstrap/argocd/) | Hub Argo CD resources: [common/manifests/argocd-resources/](common/manifests/argocd-resources/) |
| Hub operators installed at build time (ACM, GitOps) | [bootstrap/operators/](bootstrap/operators/) | Phase 1 below |

**Reference**

| Need | File |
|---|---|
| Operating the platform, troubleshooting, worked examples | [docs/gitops-operations-guide.md](docs/gitops-operations-guide.md) |
| Migration guides | [docs/shift-operator.md](docs/shift-operator.md), [docs/vm-migration-warm-vddk.md](docs/vm-migration-warm-vddk.md), [docs/vm-migration-between-clusters.md](docs/vm-migration-between-clusters.md) |
| VM disk names, VM tags | [docs/vm-disk-naming.md](docs/vm-disk-naming.md), [docs/vm-tagging.md](docs/vm-tagging.md) |
| All scripts | [scripts/README.md](scripts/README.md) |


GitOps repository for the organization's OpenShift Virtualization platform (`https://github.com/CHANGEME/ocp-local.git`): two bare metal production clusters, built and configured from this repository by a Red Hat Advanced Cluster Management (RHACM) hub running OpenShift GitOps (Argo CD). Virtual machines run on NetApp ONTAP storage over NFS.

| Cluster | Site | Role | Built by |
|---|---|---|---|
| `hub-a` | DC1 | Main RHACM hub, single-node OpenShift | Assisted Installer (Phase 1), then `bootstrap/hub-a/` |
| `hub-b` | DC2 | Standby RHACM hub, single-node OpenShift | Assisted Installer (Phase 1), then `bootstrap/hub-b/`; takes over from hub backups if DC1 is lost |
| `ocp-a` | DC1 | Primary production (`dr-role: primary`) | Assisted Installer on console.redhat.com, then imported and configured from git like `ocp-b` (`clusters/ocp-a/managedcluster.yaml`); see docs/ocp-a-gitops.md. Built by hand from `manual/ocp-a/` until 12 Nov, adopted into GitOps on 12 Nov; every production policy now enforces on it |
| `ocp-b` | DC2 | Failover production (`dr-role: failover`) | Assisted Installer on console.redhat.com, then **imported and configured from git** (`clusters/ocp-b/managedcluster.yaml`, every policy); see docs/ocp-b-build.md |

**How it works.** Each hub is installed once with the Assisted Installer and given storage. From then on, Argo CD on the hub applies this repository to the hub, and RHACM turns it into running infrastructure: a `ClusterInstance` in git becomes a cluster, and the policies in git become enforced configuration on every cluster whose labels match. Removing a cluster means removing its `ClusterInstance`; redeploying means restoring it. Virtual machines are data rather than configuration: they are migrated with the Migration Toolkit for Virtualization (MTV) and the NetApp Shift Toolkit, then protected and replicated by Trident Protect, and are not stored in git.

The full step-by-step build, with every value and open question, is in the *RHACM Bare Metal Build Runbook (NetApp)*. This README is the condensed version that accompanies the repository. How `ocp-a` was actually built, with every as-built value, is in docs/ocp-a-as-built.md. VM migration between `ocp-a` and `ocp-b` from the hub: [docs/vm-migration-between-clusters.md](docs/vm-migration-between-clusters.md).

**Operating the platform** (plain-language guide, every Argo CD app and policy, console checks, worked examples for adding a node, a VM network, an operator, a vCenter or a storage backend, and troubleshooting from simple to advanced): [docs/gitops-operations-guide.md](docs/gitops-operations-guide.md). Live migration between the clusters (IP plan, CA exchange, operating rules): [docs/vm-migration-between-clusters.md](docs/vm-migration-between-clusters.md). Shift operator: [docs/shift-operator.md](docs/shift-operator.md). Warm migration with VDDK: [docs/vm-migration-warm-vddk.md](docs/vm-migration-warm-vddk.md). NetApp Data Infrastructure Insights collector: [docs/dii-collector.md](docs/dii-collector.md). VM disk names in ONTAP (MTV PVC name template, Corp VM templates, extra disks, mapping report): [docs/vm-disk-naming.md](docs/vm-disk-naming.md). Required VM tags (admission policy, report, template fields, tagging migrated VMs): [docs/vm-tagging.md](docs/vm-tagging.md).

Bastion kubeconfigs: use each cluster's installer admin kubeconfig (client certificate, downloaded from
console.redhat.com) as `~/hub-a.kubeconfig`, `~/hub-b.kubeconfig`, `~/ocp-a.kubeconfig`, `~/ocp-b.kubeconfig`
(`chmod 600`). A kubeconfig written by `oc login` holds a token that expires after 24 hours ("You must be logged in to
the server"). `oc whoami` with each should print `system:admin`.

## Architecture






### Network flows

The numbers match the arrows in the architecture diagram.

| # | From | To | Port | Why |
|---|---|---|---|---|
| 1 | Argo CD on `hub-a` | `github.com` | 443 (or 22) | Read ClusterInstances, policies and hub configuration |
| 2 | Argo CD on `hub-b` | `github.com` | 443 (or 22) | Same repository; `hub-b` syncs only its own hub configuration (`argocd-apps-hub-b/`) |
| 3 | Every hub and node | registry.redhat.io, quay.io, registry.connect.redhat.com, NetApp | 443 | Release images, operator catalogs, Trident images; direct, no proxy |
| 4 | Bastion | API of all four clusters | 6443 | `oc`, `argocd`, `virtctl`; also 443 to `*.apps` and 22 to the nodes |
| 5 | `hub-a` | Each blade's BMC (UCS Manager or CIMC) | 443 | Redfish power control and virtual media, to build from git |
| 5 | Blades booting the discovery image | `hub-a` ingress | 443 | Fetch the image, register the host, report install progress |
| 6 | `ocp-a`, `ocp-b` | `hub-a` API and ingress | 6443, 443 | Cluster registration, policy status, Search, Observability metrics |
| 6 | `hub-a` | `ocp-a`, `ocp-b` API | 6443 | Argo CD push of workloads and Trident Protect; console access |
| 7 | `hub-a` (OADP) | ONTAP S3 | 443 | Hub backups; `hub-b` reads the same bucket or its copy |
| 8 | Every node | Its SVM's NFS data address | 2049 | NFS v4.1 on the storage VLAN, `10.60.140.0/24` |
| 8 | Trident controller | Its SVM's management address (hubs: `SVM_TEST` `10.61.250.79`, `SVM_OCP_B` `10.61.250.126`; ocp-a: `SVM_OCP_A` `10.60.202.35`, `SVM_VMW_C` `10.61.250.204`, `SVM_VMW_B` `10.61.250.203` and `SVM_VMW_A` `10.61.250.202`; ocp-b: `SVM_OCP_B`) | 443 | Volume provisioning, snapshots, clones |
| 9 | ONTAP DC1 intercluster addresses | ONTAP DC2 intercluster addresses | 11104, 11105 | SnapMirror for Trident Protect (ONTAP defaults; confirm with the storage team) |
| 9 | Trident Protect, Observability | ONTAP S3 and AppVaults | 443 | VM backups and metadata, metrics |
| 10 | Shift Toolkit and MTV on `ocp-a` | vCenter, ONTAP management, `ocp-a` API | 443, 6443 | Cold migration: snapshot and convert VM disks in place on the same SVM |
| 11 | Users and applications | F5 / GTM, then the ingress VIP and the VMs | 443, 80, app ports | Routes and VM services at the active site |
| – | Node to node, same cluster | Node to node | TCP on VLAN 333 | Live migration of VM memory over `bond3` |
| – | Every hub and node | `clock1`–`clock3.example.com`, Corp DNS | 123/udp, 53 | Time and name resolution |
| 13 | Every hub and node (collector pods) | `siem-syslog.example.com` (10.62.8.57), `graylog.example.com` | 514/tcp | Infrastructure and audit logs, switch 20 (`log-forwarding`); checked open from all four clusters 24 Nov |

## Assumptions

The templates are built on these assumptions. Revisit the affected files if any of them change.

- **Direct internet access, no proxy.** Operators, release images and Helm charts are pulled directly from Red Hat and NetApp; nothing is mirrored.
- Base domain `example.com`. Node names `<cluster>-cp0N` and `<cluster>-wn0N` under `<cluster>.example.com`. NTP `clock1`, `clock2` and `clock3.example.com`. Default pod (`10.128.0.0/14`) and service (`172.30.0.0/16`) networks.
- The hubs are **separate** single-node clusters, not one of the production clusters.
- `ocp-a` is 3 control plane + 9 worker nodes and `ocp-b` 3 control plane + 3 worker nodes (Cisco UCS B200 M5 blades). The control plane nodes are schedulable and run VMs as well (`schedulable-control-plane` policy), so `ocp-a` has 12 nodes for workloads and `ocp-b` 6. Static IPs, Redfish virtual media through UCS Manager or CIMC, no PXE network. OpenShift 4.22 (both hubs run 4.22.18, and `hub/acm/clusterimageset-4.22.yaml` installs the production clusters at 4.22.18), UEFI.
- **Identical Cisco UCS blades with eight 20 Gbit vNICs at MTU 1500**, used as four bonds. Only `bond0` is configured at install time; the others are added afterwards with NNCPs:

  | Bond | UCS vNICs (PCI order) | Linux names | Carries | Added by |
  |---|---|---|---|---|
  | `bond0` | `MGMT_FI-A`, `MGMT_FI-B` (1, 2) | `ens5f0`, `ens5f1` | Management, VLAN 24, `10.64.55.0/24` | Install (`ClusterInstance`, Assisted Installer for the hubs) |
  | `bond2` | `VM_Uplink_FI-A`, `VM_Uplink_FI-B` (3, 4) | `ens5f2`, `ens5f3` | VM VLANs (OVS bridge `br-vm`): the Int VLANs plus the two former Pub VLANs | `node-network` policy (production only) |
  | `bond3` | `Storage_Uplink_FI-A`, `Storage_Uplink_FI-B` (5, 6) | `ens5f4`, `ens5f5` | Live migration, VLAN 333, `10.60.160.0/25` (ocp-a .10–.25, ocp-b .26–.35) | `migration-network` policy (production only) |
  | `bond1` | `INFRA_vmstor-A`, `INFRA_vmstor-B` (7, 8) | `ens5f6`, `ens5f7` | NFS, VLAN 222 (and 555 for VM in-guest NFS), `10.60.140.0/24` | `storage-network` policy; `hubs/<hub>/storage-network.yaml` on the hubs |

  **Why eight, not ten.** The UCS VIC presents at most eight vNICs per PCI device. With the ESXi profile's ten vNICs, the 9th and 10th (`INFRA_vmstor-A/B`) land on a second PCI device that reports the same slot, so Linux gives two NICs the same `ens5f0`/`ens5f1` name and the winner changes from boot to boot. On the hubs this put a storage vNIC into the management bond. The OpenShift blades therefore drop the `INFRA_Pub` pair (its two VLANs move to `VM_Uplink`) and place the remaining eight vNICs on vCon 1 in the fixed order above, so every name is stable. ESXi is not affected (it orders vmnics by PCI address). Both hubs were rebuilt on this layout and keep the same names across reboots and upgrades. The VM bond is active-backup, so two vNICs give the same bandwidth and FI-A/FI-B redundancy as four. All bonds are active-backup: the Fabric Interconnects in end-host mode do not support LACP towards the server.
- **UCS objects for OpenShift.** The OpenShift blades use their own LAN connectivity policy (the eight vNICs above, vCon 1, fixed order) and service profile template, not the shared ESXi ones, plus an OpenShift boot policy (local disk first, `\EFI\redhat\shimx64.efi`). Each blade is rebound to the OpenShift template when it is converted; a rebind reboots the blade and the vNIC MACs can change, so read the MACs from UCS afterwards, not from the host sheet.
- **Storage is ONTAP over NFS** (`ontap-nas` driver, certified Trident operator), which also gives ReadWriteMany for live migration. The backend starts from NetApp's basic `backend-tbc-ontap-nas.yaml` sample; the advanced fields wait for the storage session.
- **The SVM each production cluster uses must be the one that holds the VMware NFS datastores** of the VMs it receives, so the Shift Toolkit can convert disks in place. The DC1 and DC2 SVMs are peered for replication.
- The 25 VMs are migrated into `ocp-a` with MTV plans prepared by the platform team and run by NetApp with the Shift Toolkit (cold migration, no VDDK), then replicated to `ocp-b`. Warm migration with VDDK is available too (provider `vcenter01-vddk`, docs/vm-migration-warm-vddk.md).

## Layout

```
bootstrap/          Applied by hand, once per hub. Gets each hub to the point where git takes over.
  operators/          OpenShift GitOps and RHACM subscriptions (both hubs)
  argocd/             Argo CD RBAC and PolicyGenerator plugin patch (both hubs)
  secrets/            Example of the install secrets created on each hub (real values never committed)
  hub-a/             Main hub: hub-storage/ (Trident on the hub) and root-app.yaml
  hub-b/             Standby hub: hub-storage/ (Trident on the hub) and root-app.yaml
argocd-apps/        Applications for hub-a (app of apps), created by bootstrap/hub-a/root-app.yaml
argocd-apps-hub-b/ Applications for hub-b, created by bootstrap/hub-b/root-app.yaml
hub/                Configuration shared by both hubs: RHACM, assisted service, cluster set,
                    GitOps integration, NMState operator
hubs/               Per-hub configuration on top of hub/
  hub-a/             storage-network.yaml (the hub's storage NNCP), site-values.yaml and
                      local-cluster-labels.yaml (the hub's values and switches for common/)
  hub-b/             the same for hub-b
clusters/           One folder per managed cluster. The ClusterInstance in it defines the cluster.
  ocp-a/
  ocp-b/
common/             Day-2 configuration shared by the hubs and the production clusters, as RHACM policies,
                    switched per cluster by config.example.com labels (switches 1-20, see common/README.md): htpasswd,
                    AD and group sync, etcd encryption, NTP, console branding, namespace template, RBAC, ingress
                    certificate, multipath, LLDP, MetalLB, alerting, observability, image registry, etcd backup,
                    Tech Preview guard, routing via host, MTV provider, DII collector, MTV disk names, log forwarding;
                    plus hub Argo CD sizing and health (common-argocd-resources)
policies/           Day-2 configuration for the production clusters as RHACM policies, generated from plain manifests
  policy-generator.yaml
  site-values/        Per-cluster values (ONTAP addresses, SVM, live migration addresses) read by cluster name
  manifests/          One folder per policy (catalogue: docs/gitops-operations-guide.md, section 5), among them:
    storage-network/    bond1 and the NFS VLAN, one NNCP per node
    node-network/       bond2 and the VM bridge
    migration-network/  bond3, VLAN 333 and the live migration network
    trident-*/          Trident operator, backends and ontap-nas; shift-backends/ for the VMware SVMs
    virtualization-*/   OpenShift Virtualization; vm-templates/, vm-tagging/, vm-tagging-report/, vm-networks/
    mtv-*/, shift-*/    MTV, the VMware providers and maps (Shift and VDDK), the Shift operator
apps/               Workloads, fanned out to clusters by an ApplicationSet
migration/          Not synced. Per-wave MTV plans and the wave hand-off notes.
scripts/            Operator tools run from the bastion: tag-vm.sh, add-vm-disk.sh, vm-storage-map.sh,
                    datastore-ids.sh, build-vddk-image.sh, Remove-VMwareTools.ps1.txt (see scripts/README.md)
docs/               Runbooks and as-built notes: gitops-operations-guide.md (operations runbook), shift-operator.md,
                    vm-migration-warm-vddk.md, vm-migration-between-clusters.md, vm-disk-naming.md, vm-tagging.md,
                    dii-collector.md, bare-metal-provisioning.md
docs/images/        Architecture, GitOps and migration diagrams and screenshots used in the docs
docs/diagrams/      Mermaid sources of the GitOps diagrams (mmdc -c cfg.json -i <file>.mmd)
examples/           Not applied. Templates to adopt once the related decisions are made.
  vm-networks/        NAD, UDN and CUDN options side by side
  trident-protect/    VM protection and site-to-site replication objects
```

| Argo Application | Source | Auto-sync | Prune | Why |
|---|---|---|---|---|
| `root` | `argocd-apps/` on `hub-a`, `argocd-apps-hub-b/` on `hub-b` | yes | yes | Creates the others |
| `hub-config` | `hubs/hub-a/` or `hubs/hub-b/` | yes | no | Hub components are never deleted automatically |
| `clusters` | `clusters/` (`hub-a` only) | yes | **no** | Building is automatic; removal is a deliberate step |
| `policies` | `policies/` (`hub-a` only) | yes | yes | Git is the single source of truth for policy |
| `common-config` | `common/` (both hubs) | yes | yes | Shared day-2 configuration; on `hub-b` it applies only to `hub-b` itself |
| `trident-protect` | NetApp Helm chart (`hub-a` only) | yes | yes | Not an OLM operator, so Argo CD installs the chart on each cluster |
| `prod-workloads` | `apps/` (`hub-a` only) | yes | yes | Git is the single source of truth for workloads |

On `hub-b`, `clusters`, `policies`, `trident-protect` and `prod-workloads` are listed in `argocd-apps-hub-b/kustomization.yaml` but commented out; they are enabled only if `hub-b` takes over (see "Standby hub").

## Before you start

Node names, management and storage addresses, gateway, VIPs and the management MACs are filled in from the Corp host sheet (`Corp_Redhat_Hosts_Info.xlsm`): `ocp-a` has 3 control plane and 9 worker nodes, `ocp-b` 3 and 3. The remaining values that depend on the organization's environment are marked `CHANGEME`. List them with:

```
grep -rn CHANGEME .
```

| Values | Where | From |
|---|---|---|
| DNS servers (`10.60.190.12`, `10.60.190.20`, set) | `clusters/*/clusterinstance.yaml` | Corp IPAM |
| BMC Redfish path (the vKVM address and serial are filled in; confirm Redfish answers there) | `clusters/*/clusterinstance.yaml` | UCS Manager / Intersight |
| Root disk, ideally a `/dev/disk/by-path/` name | `clusters/*/clusterinstance.yaml` | First booted blade |
| SSH public key | `clusters/*/clusterinstance.yaml` | Platform team |
| NFS VLAN, and the `ens5f6`/`ens5f7` names (the MACs are noted beside each bond) | `policies/manifests/storage-network/`, `hubs/*/storage-network.yaml` | Corp network; `ip -br link` on a booted node |
| SVM names and management and NFS data addresses | `policies/site-values/*.yaml`, `bootstrap/*/hub-storage/04-backend.yaml` | NetApp storage session |
| Live migration range per cluster (must not overlap ESXi vMotion addresses) | `policies/site-values/*.yaml` | Corp IPAM |
| OpenShift 4.22 z-stream | `hub/acm/clusterimageset-4.22.yaml` | Platform team |
| VM namespaces and their VLAN labels | `policies/manifests/vm-namespaces/` | Application owners |

Secrets are never stored in this repository: the pull secret and the BMC, ONTAP and vCenter credentials are created on the hub by hand (Phase 1, step 7), and the files that hold them are git-ignored.

## Bastion host

All commands in this README run from a bastion on the management network, as a normal user with `sudo`. The hubs are installed with the Assisted Installer, so the bastion does not need `openshift-install`, and the environment is connected, so it does not need `oc-mirror` or a local registry.

### Sizing and access

| Item | Requirement |
|---|---|
| OS | RHEL 10, registered with an active Red Hat subscription (BaseOS and AppStream repositories enabled) |
| Size | 2 vCPU, 8 GB RAM, 40 GB disk minimum (Corp checklist); 100 GB is more comfortable for must-gathers and logs |
| Name | `<bastion>.example.com`, with A and PTR records |
| Time | Same NTP as the clusters: `clock1`–`clock3.example.com` |

| From the bastion to | Port | Why |
|---|---|---|
| `api.hub-a`, `api.hub-b`, `api.ocp-a`, `api.ocp-b` `.example.com` | 6443 | `oc` against each cluster |
| `*.apps.<cluster>.example.com` | 443 | Consoles, Argo CD, CLI downloads |
| Node management addresses, `10.64.55.0/24` | 22 | `ssh core@<node>` when a node needs inspecting |
| `github.com` | 443 (or 22) | Clone and push this repository |
| ONTAP SVM management and S3 endpoints | 443 | Checks against ONTAP and the S3 buckets |
| vCenter | 443 | Disk and inventory checks before each migration wave |
| console.redhat.com, mirror.openshift.com, github.com, registry.redhat.io, quay.io | 443 | Assisted Installer, client downloads, test images |

### Packages

```
sudo subscription-manager status                          # registered, BaseOS and AppStream enabled
sudo dnf upgrade --refresh -y
sudo dnf install -y git jq gettext bind-utils iputils curl wget tar unzip openssl \
  podman skopeo nmstate nfs-utils httpd-tools bash-completion vim tmux python3 python3-pyyaml
```

Every package above is in the RHEL 10 BaseOS and AppStream repositories; no EPEL or third-party repositories are needed.

| Package | Used for |
|---|---|
| `git` | This repository |
| `jq`, `python3-pyyaml`, `gettext` | Reading `oc ... -o json` output, checking YAML before a merge |
| `bind-utils` (`dig`) | DNS checks for `api`, `*.apps` and node names |
| `iputils`, `curl`, `openssl` | Reachability and certificate checks (`openssl s_client -connect api.ocp-a.example.com:6443`) |
| `podman`, `skopeo` | The etcd disk test (`quay.io/openshift-scale/etcd-perf`), inspecting operator and release images |
| `nmstate` | `nmstatectl` to validate NMState YAML (Assisted Installer, ClusterInstance, NNCPs) before using it |
| `nfs-utils` | Test-mounting an SVM export from the storage VLAN, if the bastion has a leg on it |
| `httpd-tools` | `htpasswd`, if a temporary HTPasswd identity provider is used before the real IdP |

### OpenShift and partner clients

Install everything into `/usr/local/bin`. Keep `oc` at the cluster minor version (4.22) and `virtctl` at the OpenShift Virtualization version. Use the `rhel9` build of `oc`; it runs on RHEL 10, which has a newer glibc. If mirror.openshift.com publishes a `rhel10` build for 4.22, either works.

| Client | Needed for | Source |
|---|---|---|
| `oc`, `kubectl` | Everything | mirror.openshift.com, `stable-4.22` |
| `helm` | Inspecting the Trident Protect chart that Argo CD installs | mirror.openshift.com |
| `argocd` | `argocd app sync clusters --prune` when removing a cluster; app diffs | OpenShift GitOps CLI download |
| `virtctl` | VM console, start/stop, live migration, image upload | OpenShift Virtualization CLI download (after Phase 4) |
| `kustomize` + PolicyGenerator plugin | Testing `policies/` locally before a merge | GitHub releases |
| `tridentctl` | Trident backend and volume troubleshooting | NetApp Trident release, same version as installed |
| `tridentctl-protect` | Trident Protect: AppVaults, snapshots, backups, mirror relationships | NetApp release |
| `yq` | Editing YAML in scripts | GitHub releases |
| `aws` (CLI v2) | Generic S3 client to check the ONTAP S3 buckets (Observability, hub backups, AppVaults) | AWS |

```
mkdir -p ~/bin-dl && cd ~/bin-dl

# oc and kubectl (OpenShift 4.22)
curl -LO https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable-4.22/openshift-client-linux-amd64-rhel9.tar.gz
tar xzf openshift-client-linux-amd64-rhel9.tar.gz oc kubectl && sudo install -m 0755 oc kubectl /usr/local/bin/

# helm
curl -L -o helm https://mirror.openshift.com/pub/openshift-v4/clients/helm/latest/helm-linux-amd64
sudo install -m 0755 helm /usr/local/bin/

# argocd (OpenShift GitOps build)
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/openshift-gitops/latest/argocd-linux-amd64.tar.gz
tar xzf argocd-linux-amd64.tar.gz && sudo install -m 0755 argocd /usr/local/bin/

# yq
curl -L -o yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo install -m 0755 yq /usr/local/bin/

# AWS CLI v2, used only as an S3 client against ONTAP S3
curl -L -o awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
unzip -q awscliv2.zip && sudo ./aws/install

# kustomize and the PolicyGenerator plugin (to run "kustomize build --enable-alpha-plugins policies/")
curl -s https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh | bash
sudo install -m 0755 kustomize /usr/local/bin/
PG=~/.config/kustomize/plugin/policy.open-cluster-management.io/v1/policygenerator
mkdir -p $PG
curl -L -o $PG/PolicyGenerator https://github.com/stolostron/policy-generator-plugin/releases/latest/download/linux-amd64-PolicyGenerator
chmod +x $PG/PolicyGenerator
```

If a download URL has moved, every cluster console lists the matching builds under **? → Command Line Tools** (`oc`, `helm`, `argocd` once GitOps is installed, `virtctl` once OpenShift Virtualization is installed). Pick a PolicyGenerator release that matches the ACM version (2.17).

After OpenShift Virtualization is running on `ocp-a` (Phase 4), take `virtctl` from the cluster so the versions match:

```
oc --kubeconfig ~/ocp-a.kubeconfig get consoleclidownloads virtctl-clidownloads-kubevirt-hyperconverged \
  -o jsonpath='{range .spec.links[*]}{.href}{"\n"}{end}' | grep -i linux
curl -kLO <the linux x86_64 link from above>
tar xzf virtctl.tar.gz && sudo install -m 0755 virtctl /usr/local/bin/
```

After Trident is on the hub (Phase 1, step 3), install the NetApp CLIs at the **same version** as the installed Trident:

```
TV=$(oc get tridentorchestrator trident -o jsonpath='{.status.version}' | sed 's/^v//'); echo $TV   # e.g. 25.06.0
curl -LO https://github.com/NetApp/trident/releases/download/v$TV/trident-installer-$TV.tar.gz
tar xzf trident-installer-$TV.tar.gz trident-installer/tridentctl && sudo install -m 0755 trident-installer/tridentctl /usr/local/bin/
curl -L -o tridentctl-protect https://github.com/NetApp/tridentctl-protect/releases/latest/download/tridentctl-protect-linux-amd64
sudo install -m 0755 tridentctl-protect /usr/local/bin/
```

### Shell and keys

```
# command completion
oc completion bash | sudo tee /etc/bash_completion.d/oc >/dev/null
for c in kubectl helm argocd virtctl; do command -v $c >/dev/null && $c completion bash | sudo tee /etc/bash_completion.d/$c >/dev/null; done

# SSH key for the cluster nodes: the public half goes into the Assisted Installer and each ClusterInstance (sshPublicKey)
ssh-keygen -t ed25519 -N '' -f ~/.ssh/ocp_ed25519 && cat ~/.ssh/ocp_ed25519.pub

# kubeconfigs are break-glass credentials: keep them private
mkdir -p ~/.kube && chmod 700 ~/.kube
```

### Check the bastion

```
oc version --client; kubectl version --client; helm version --short; argocd version --client --short
kustomize version; yq --version; aws --version; nmstatectl --version; podman --version
for h in api.ocp-a api.ocp-b api.hub-a api.hub-b; do dig +short $h.example.com; done
dig +short test.apps.ocp-a.example.com                    # wildcard resolves to the ingress VIP
```

Every client prints a version, and every DNS name returns an address (the hub names only once their records exist).

### Get the repository

Every command in this README runs from the repository root, cloned to `~/ocp-local` on the bastion. Until the repository is on `github.com`, unzip the delivered copy there instead.

```
git clone https://github.com/CHANGEME/ocp-local.git ~/ocp-local
cd ~/ocp-local
grep -rn CHANGEME . | grep -v '^./.git'                      # what is still to fill in
```

**Windows workstations.** When working from Windows instead of the bastion, the same clients exist as Windows builds on the Command Line Tools page; run them from Git Bash. VMware PowerCLI (for the vCenter disk alignment check before each migration wave) runs on the workstation, or on the bastion with PowerShell 7 from Microsoft (its RHEL package repository, or the Linux `tar.gz` release if no RHEL 10 repository is published yet).

## Phase 1: build the hub (by hand, once)

These steps build `hub-a`. The standby hub `hub-b` is built the same way with its own bootstrap folder; see "Standby hub" below. Run everything from the bastion (see "Bastion host" above), in `~/ocp-local`, as cluster-admin on the hub.

**1. Install the hub with the Assisted Installer.** On console.redhat.com: Bare Metal (x86_64), interactive, cluster name `hub-a`, base domain `example.com`, OpenShift 4.22, **single-node**, static network. In **Static network configurations** put **only the management network**. Network-wide: VLAN `24`, DNS `10.60.190.12,10.60.190.20`, subnet `10.64.55.0/24`, gateway `10.64.55.1`. Host-specific: **Use bond**, Active-Backup, port 1 the MGMT_FI-A MAC and port 2 the MGMT_FI-B MAC from the table below, and the hub's address (form view is enough; the result is `bond0` with VLAN 24 on top). Do not add the storage network here. Select no bundled operators. Add `clock1`–`clock3.example.com` as NTP sources if the host does not sync. Keep the default cluster and service networks, and choose `10.64.55.0/24` as the machine network. When it finishes, store the kubeconfig and the `kubeadmin` password in the organization's vault; they are break-glass credentials.

| Hub | Host | Management (`bond0.24`) | MGMT_FI-A (`ens5f0`) | MGMT_FI-B (`ens5f1`) | Storage (`bond1.222` on `ens5f6`/`ens5f7`) |
|---|---|---|---|---|---|
| `hub-a` | `hub-a01.hub-a.example.com` | `10.64.55.70/24`, gateway `10.64.55.1` | `02:00:00:00:00:4e` | `02:00:00:00:00:4f` | `10.60.140.50/24` |
| `hub-b` | `hub-b01.hub-b.example.com` | `10.64.55.71/24`, gateway `10.64.55.1` | `02:00:00:00:00:50` | `02:00:00:00:00:51` | `10.60.140.51/24` (vmstor `02:00:00:00:00:01`/`bb:00:7e`) |

The `hub-a` vmstor MACs are `02:00:00:00:00:03`/`be:00:4b`. Blade management (vKVM/Redfish) addresses: `hub-a01` `10.64.55.114` (ucs-fi-5-5, SERIAL0000), `hub-b01` `10.64.55.132` (ucs-chassis-1-7, SERIAL0000); the `OCP-Redfish` IPMI/Redfish access profile on the OpenShift template gives the hub its Redfish login. Before installing, bind the blade to the OpenShift service profile template (8 vNICs) and boot the discovery ISO once to check the names: all eight vNICs on one PCI bus as `ens5f0`–`ens5f7`, no `eth*` names (`for i in /sys/class/net/*; do [ -e $i/device ] && echo $(basename $i) $(cat $i/address) $(basename $(readlink -f $i/device)); done`). Install the version the other hub runs (4.22.18), or install 4.22 and upgrade; a 4.20 install reaches 4.22 only through 4.21.

A single-node cluster has no API or ingress VIPs: `api`, `api-int` and `*.apps` for each hub must resolve to the hub's own management address (`.70` for `hub-a`, `.71` for `hub-b`, as in the host sheet's DNS tab). Check before booting the discovery ISO: `for h in api api-int test.apps; do dig +short $h.hub-b.example.com; done`.

```
export KUBECONFIG=~/hub-a.kubeconfig
oc get nodes; oc get clusterversion
oc get co | awk 'NR==1 || $3!="True" || $4!="False" || $5!="False"'   # only the header if healthy
```

**2. Add the storage network with NMState.** The hub's storage address is already in `hubs/hub-a/storage-network.yaml` (`bond1` on `ens5f6`/`ens5f7`, VLAN 222). This file is what `hub-config` applies from git later, so it must match the node before Phase 2.

```
oc apply -f hub/network/nmstate-operator.yaml
oc get csv -n openshift-nmstate -w                        # wait for Succeeded
oc apply -f hub/network/nmstate.yaml
oc get pods -n openshift-nmstate                          # nmstate-handler Running
oc apply -f hubs/hub-a/storage-network.yaml
oc get nncp storage-network; oc get nnce                  # Available / SuccessfullyConfigured

# the hub can reach the SVM over the storage VLAN (replace the VLAN and the SVM data address)
oc debug $(oc get nodes -o name) -q -- chroot /host bash -c "ip -br addr show bond1.222; ping -c3 -I bond1.222 172.18.140.CHANGEME"
```

NMState rolls the change back automatically if the node loses its API connection. After Phase 2 the same three files are owned by `hub-config`, so make any later change in git.

**3. Storage for the hub: Trident on ONTAP.** The hub needs a default StorageClass before ACM can run its install service (about 160Gi of PVCs). This follows NetApp's guidance: the certified operator, a `vsadmin` account with the **http** and **ontapi** applications, and the four objects (secret, backend, StorageClass with `storagePools`, snapshot class).

The storage team checks the account on the hub's SVM:

```
security login show -vserver <hub-svm> -user-or-group-name vsadmin
security login create -vserver <hub-svm> -user-or-group-name vsadmin -application http   -authentication-method password -role vsadmin
security login create -vserver <hub-svm> -user-or-group-name vsadmin -application ontapi -authentication-method password -role vsadmin
```

Then, on the hub (fill in `bootstrap/hub-a/hub-storage/04-backend.yaml` first):

```
cd bootstrap/hub-a/hub-storage
oc get csv -A | grep -i trident                           # if a community Trident operator is installed, switch it first (NetApp procedure)
oc apply -f 01-trident-operator.yaml
oc get csv -n openshift-operators -w | grep -i trident    # wait for Succeeded
oc create namespace trident
oc apply -f 02-tridentorchestrator.yaml
oc get tridentorchestrator trident -o jsonpath='{.status.status}{"\n"}'   # Installed

cp 03-backend-secret.yaml.example 03-backend-secret.yaml  # git-ignored
vi 03-backend-secret.yaml
oc apply -f 03-backend-secret.yaml -f 04-backend.yaml
oc get tridentbackendconfig -n trident                    # Bound / Success
oc apply -f 05-storageclass.yaml
oc get sc                                                 # ontap-nas (default)
cd ~/ocp-local
```

Test it, and check the name template:

```
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: storage-smoke-test, namespace: default }
spec: { accessModes: [ReadWriteMany], resources: { requests: { storage: 1Gi } } }
EOF
oc get pvc storage-smoke-test -n default                  # Bound
oc get tridentvolume -n trident -o custom-columns=NAME:.metadata.name,INTERNAL:.config.internalName
oc delete pvc storage-smoke-test -n default
```

The ONTAP volume should be named `hub_a_default_storage-smoke-test`. If the storage team uses certificates instead of a password, the secret holds `clientCertificate`, `clientPrivateKey` and `trustedCACertificate`, and the logins use `-authentication-method cert`.

**4. Operators.** `installPlanApproval` is `Manual`, so approve the first install of each:

```
oc apply -f bootstrap/operators/
sleep 60; oc get installplan -n openshift-gitops-operator; oc get installplan -n open-cluster-management
oc patch installplan <name> -n openshift-gitops-operator --type merge -p '{"spec":{"approved":true}}'
oc patch installplan <name> -n open-cluster-management    --type merge -p '{"spec":{"approved":true}}'
oc get csv -n openshift-gitops-operator; oc get csv -n open-cluster-management   # both Succeeded
```

Check the ACM channel first: `oc get packagemanifest advanced-cluster-management -n openshift-marketplace -o jsonpath='{.status.defaultChannel}'`. Do not create the `MultiClusterHub` by hand; git creates it in Phase 2.

**5. Prepare Argo CD.** The PolicyGenerator plugin is copied out of an ACM image, so find that image and put it in the patch:

```
oc -n open-cluster-management get deploy multicluster-operators-application -o jsonpath='{..image}{"\n"}'
vi bootstrap/argocd/argocd-policygenerator-patch.yaml     # set the init container image
oc apply -f bootstrap/argocd/argocd-rbac.yaml
oc -n openshift-gitops patch argocd openshift-gitops --type merge \
  --patch-file bootstrap/argocd/argocd-policygenerator-patch.yaml
oc get pods -n openshift-gitops -w | grep repo-server
```

Wait for the `openshift-gitops-repo-server` pod to restart cleanly. If its init container fails, the image tag or binary name in the patch is wrong for this ACM version.

Argo CD has its own access control, separate from OpenShift's: only the `cluster-admins` groups (kubeadmin) see applications by default. Nothing to do here: once `common-config` runs (Phase 4), the `common-argocd-rbac` policy maps the break-glass group and the AD groups to Argo CD roles on each hub, from the same group names as the cluster RBAC in `common/values.yaml`. `break-glass` and `groupPlatformAdmins` become Argo CD admins, `groupPlatformReaders` read-only, and, with `readOnlyForAllUsers: "true"`, anyone else who logs in read-only. Users log out of Argo CD and back in to pick up a change.

**6. Repository access.** Give Argo CD a read-only credential for this repository on `github.com`:

```
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ocp-local-repo
  namespace: openshift-gitops
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/CHANGEME/ocp-local.git
  username: CHANGEME                            # read-only account
  password: CHANGEME                            # read-only token
EOF
```

If `github.com` uses an internal CA, add it to Argo CD's trusted certificates (`argocd-tls-certs-cm`) as well.

**7. Secrets on the hub.** Created once, never in git:

```
# pull secret and default BMC login, copied into each cluster namespace by the install-secrets policy
oc create namespace cluster-install-secrets --dry-run=client -o yaml | oc apply -f -
cp bootstrap/secrets/install-secrets.yaml.example bootstrap/secrets/install-secrets.yaml
vi bootstrap/secrets/install-secrets.yaml        # git-ignored
oc apply -f bootstrap/secrets/install-secrets.yaml

# ONTAP account per production cluster, read by the trident-config policy
oc create namespace policies --dry-run=client -o yaml | oc apply -f -
oc -n policies create secret generic ontap-credentials-ocp-a --from-literal=username=vsadmin --from-literal=password='CHANGEME'
oc -n policies create secret generic ontap-credentials-ocp-b --from-literal=username=vsadmin --from-literal=password='CHANGEME'
```

Each account needs the **http** and **ontapi** applications on that cluster's SVM, as in step 3. For a cluster with different BMC credentials, add a secret named `bmc-credentials-<cluster>` in `cluster-install-secrets`; it takes precedence over the default.

## Phase 2: hand the hub to git

Every Argo CD `repoURL` already points at `https://github.com/CHANGEME/ocp-local.git` (`grep -rn repoURL bootstrap argocd-apps*`). Push the repository there, then:

```
oc apply -f bootstrap/hub-a/root-app.yaml
```

This is the last manual `oc apply` against cluster configuration. Argo CD now creates the child Applications. `hub-config` brings up the `MultiClusterHub` (10 to 20 minutes), then the assisted service (its volumes on `ontap-nas`), the `ClusterImageSet`, the `prod` cluster set and the GitOps integration, and adopts the NMState objects from Phase 1 step 2. It retries while CRDs appear, so early sync errors are expected.

To bring the hub up without immediately building the production clusters, comment both clusters out of `clusters/kustomization.yaml` first.

Notes from the hub builds:

- **`oc get applications` returns ACM's resource once ACM is installed.** Use `applications.argoproj.io` for every Argo CD command.
- **A wave waits for the previous wave to be healthy.** If `hub-config` stops with resources `Missing`, look for an unhealthy object in an earlier wave first: a Degraded `storage-network` NNCP (wrong interface names in git) blocks everything after it.
- **`common-config` can run out of retries** before the MultiClusterHub has installed the policy CRDs (`Placement ... not found`). Sync it again once the MultiClusterHub is `Running`: `oc -n openshift-gitops patch applications.argoproj.io common-config --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'`.
- **AD groups appear after the first group sync** (every 30 minutes). Until then `common-rbac` is NonCompliant. Run it once: `oc create job ldap-sync-now --from=cronjob/ldap-group-sync -n ldap-sync`.
- **The NTP MachineConfig reboots the hub once** while `common-config` converges.
- **Leftover `installer-*` pods in Error** in the `openshift-kube-*` namespaces after an upgrade are failed retries of a revision that later succeeded; delete them once the matching cluster operator is Available and not Degraded.

Check before moving on:

```
oc get multiclusterhub -n open-cluster-management          # Running
oc get agentserviceconfig agent                            # conditions all True
oc get pods -n multicluster-engine | grep assisted         # Running
oc get pvc -n multicluster-engine                          # Bound on ontap-nas
oc get nncp storage-network                                # still Available, now synced by hub-config
oc get clusterimageset
oc get configmap -n open-cluster-management | grep ai-     # default ClusterInstance templates exist
oc get managedclusterset prod
oc get applications.argoproj.io -n openshift-gitops        # all Synced; clusters has nothing to build yet
oc get pvc -n open-cluster-management                      # ontap-nas-search Bound (hub/acm/search-storage.yaml)
```

### Common configuration on the hub

The `common-config` Application (created by the root Application) configures the hub itself with the shared day-2 features in `common/`: htpasswd, AD, etcd encryption, NTP, console branding, namespace template, RBAC, ingress certificate, multipath, LLDP and MetalLB. The hub manages itself as `local-cluster`, so the same policies that configure `ocp-a` and `ocp-b` also apply to it. `common/README.md` describes each feature.

**1. Choose the hub's features.** Edit `hubs/hub-a/local-cluster-labels.yaml`: `enabled` installs a feature, anything else skips it. As delivered, htpasswd, AD, etcd encryption, NTP, console, namespace template, RBAC, LLDP, alerting, image registry, etcd backup and the Technology Preview guard are on; ingress certificate, multipath, MetalLB and observability are off.

**2. Fill in the values.**

| File | Values |
|---|---|
| `common/values.yaml` | Product name, htpasswd user, namespace prefix, RBAC group names; for AD, the LDAP server, bind DN, base DNs and synced groups |
| `hubs/hub-a/site-values.yaml` | The hub's banner text and colours; the MetalLB range if MetalLB is on |
| `common/manifests/console/logo.svg` | the organization's logo (the delivered file is a placeholder) |

Merge the changes to `main`.

**3. Create the hub's secrets** in the `policies` namespace (Argo CD creates the namespace in Phase 2). Only the secrets for the features that are switched on are needed. They are never committed:

```
htpasswd -c -B -b users.htpasswd ocpadmin '<password>'      # user = htpasswdAdminUser in common/values.yaml
oc -n policies create secret generic htpasswd --from-file=htpasswd=users.htpasswd && rm users.htpasswd
# if ad is enabled
oc -n policies create secret generic ldap-bind --from-literal=bindPassword='<password>'
oc -n policies create configmap ldap-ca --from-file=ca.crt=ad-ca.pem
# if ingress-cert is enabled: the hub's own certificate is always named local-cluster-ingress-cert
oc -n policies create secret tls local-cluster-ingress-cert --cert=hub-a-apps-chain.pem --key=hub-a-apps.key
```

The same secrets also serve `ocp-a` and `ocp-b` later; their ingress certificates are added in Phase 4.

**4. Let it converge.** Argo CD syncs `common-config` within three minutes of the merge. To sync it at once, run `argocd app sync common-config`, or use the console. The `common-hub-labels` policy copies the switches onto `local-cluster` first, and the feature policies then bind to it. NTP (and multipath, if enabled) is a MachineConfig, so the single-node hub **reboots once**: the API and console are unavailable for about 10 to 15 minutes, while running workloads on other clusters are not affected.

**5. Check.**

```
oc get applications.argoproj.io common-config -n openshift-gitops                 # Synced, Healthy
oc get managedcluster local-cluster --show-labels | tr ',' '\n' | grep config.example.com
oc -n policies get policy | grep common-                             # Compliant where enabled
oc get mcp master                                                    # UPDATED True after the reboot
oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}{"\n"}'   # local (and corp-ad)
oc login -u ocpadmin https://api.hub-a.example.com:6443 --kubeconfig /tmp/bg.kubeconfig && rm /tmp/bg.kubeconfig   # break-glass admin works
oc get consolenotification cluster-identity
oc get openshiftapiserver -o jsonpath='{range .items[0].status.conditions[?(@.type=="Encrypted")]}{.reason}{"\n"}{end}'   # EncryptionCompleted
```

A policy that stays NonCompliant names the missing value or secret in its status: `oc -n policies describe policy <name>`. To change a feature later, edit `local-cluster-labels.yaml` and merge.

### Observability (hubs)

RHACM MultiClusterObservability collects metrics from every managed cluster, and from the hub itself, into Thanos on the hub, with long-term storage in an ONTAP S3 bucket. The observability operator is part of RHACM and runs on every hub as soon as the MultiClusterHub is up, and `hub/kustomization.yaml` always creates the `open-cluster-management-observability` namespace. Only the configuration, the `MultiClusterObservability` resource, is switched: it is common feature 12, `observability: enabled` in `hubs/<hub>/local-cluster-labels.yaml` (policy `common-observability`, hubs only), because it needs the hub's Trident storage (`ontap-nas`) and an S3 bucket. It is `disabled` on both hubs as delivered.

| Hub | Bucket | Collects from |
|---|---|---|
| `hub-a` | `acm-metrics-hub-a` | `local-cluster`, `ocp-a`, `ocp-b` |
| `hub-b` | `acm-metrics-hub-b` | itself while standby; all clusters after a takeover |

1. **Storage team:** S3 on `SVM_TEST`, one user, and the buckets `acm-metrics-hub-a`, `acm-metrics-hub-b` and `acm-backup-acm` (hub backups). The hubs reach the S3 endpoint on TCP 443, so the firewall rule to the SVM must cover it.
2. **On each hub, by hand** (never in git):
   ```
   oc create secret generic multiclusterhub-operator-pull-secret -n open-cluster-management-observability \
     --from-literal=.dockerconfigjson="$(oc extract secret/pull-secret -n openshift-config --to=-)" \
     --type=kubernetes.io/dockerconfigjson
   cp hub/observability/thanos-object-storage.yaml.example hub/observability/thanos-object-storage.yaml   # git-ignored
   vi hub/observability/thanos-object-storage.yaml        # bucket, endpoint, keys for this hub
   oc apply -f hub/observability/thanos-object-storage.yaml && rm hub/observability/thanos-object-storage.yaml
   ```
3. **Turn it on:** set `observability: enabled` in `hubs/<hub>/local-cluster-labels.yaml` and merge. `hub-config` updates the labels and the `common-observability` policy creates the resource.
4. **Check:**
   ```
   oc get mco observability -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'
   oc get pvc -n open-cluster-management-observability        # Bound on ontap-nas
   oc get managedclusteraddon -A | grep observability-controller
   ```
   Grafana is in the RHACM console under Fleet Management → Infrastructure → Clusters → **Grafana**, or at `https://grafana-open-cluster-management-observability.apps.<hub>.example.com`.

### Standby hub (`hub-b`)

`hub-b` has its own bootstrap so that it never builds or manages `ocp-a` and `ocp-b` while `hub-a` is active. Build it at DC2 with the same steps, using its own files:

| Step | `hub-a` | `hub-b` |
|---|---|---|
| 1. Assisted Installer | cluster name `hub-a` | cluster name `hub-b`, `10.64.55.71` |
| 2. Storage network | `hubs/hub-a/storage-network.yaml` | `hubs/hub-b/storage-network.yaml` |
| 3. Trident on the hub | `bootstrap/hub-a/hub-storage/`: SVM `SVM_TEST` (DC1), management `10.61.250.79`, data LIFs `.71`/`.72` pinned to `N03g`/`N03h`, prefix `hub_a` | `bootstrap/hub-b/hub-storage/`: SVM `SVM_OCP_B` (DC2), management `10.61.250.126`, data LIFs `.77`/`.78` pinned to `N04e_6tb_SSD_1`/`N04f_6tb_SSD_1`, prefix `hub_b`, export policy `SVM_Default` |
| 4–7. Operators, Argo CD, repository access, secrets | same commands | same commands |
| Common configuration | `hubs/hub-a/local-cluster-labels.yaml`, `site-values.yaml`; secrets on `hub-a` | `hubs/hub-b/local-cluster-labels.yaml`, `site-values.yaml`; the same secrets created again on `hub-b` (its ingress certificate is also named `local-cluster-ingress-cert`) |
| Root Application | `bootstrap/hub-a/root-app.yaml` → `argocd-apps/` | `bootstrap/hub-b/root-app.yaml` → `argocd-apps-hub-b/` |

**`SVM_OCP_B` export policy.** Trident gives new volumes the SVM's export policy named in the backend `defaults.exportPolicy` (otherwise `default`). On `SVM_OCP_B` the `default` policy is read-only (`rwrule never`) and read-write access is in `SVM_Default`, so the `hub-b` backends set `exportPolicy: SVM_Default`. Without it, volumes bind and mount but every write fails (`permission denied`; the assisted service and search crash-loop). To move an existing volume: `volume modify -vserver SVM_OCP_B -volume hub_b_* -policy SVM_Default`, then restart its pods. Check any SVM with `vserver export-policy rule show -vserver <svm> -fields policyname,clientmatch,rwrule,superuser`.

`argocd-apps-hub-b/` creates only `hub-config` from `hubs/hub-b/` and `common-config` from `common/`, which on `hub-b` configures only `hub-b` itself. Create its `common/` secrets on `hub-b` too (Phase 4). `hub-b` then follows the hub backups from `hub-a` (OADP to ONTAP S3) and stays passive.

**Hub backup and restore.** In place since 27 Oct: OADP on both hubs, backups every 2 hours from `hub-a` to `acm-backup-acm` on `SVM_OCP_B` (DC2); the passive restore on `hub-b` is enabled once the first scheduled backups complete. ONTAP S3 details, certificate and checksum requirements: `hub/backup/README.md`. `hub/backup/dpa.yaml` (both hubs) points the RHACM `cluster-backup` component at one S3 bucket on the DC2 SVM `SVM_OCP_B`; `hubs/hub-a/backup-schedule.yaml` writes backups every 2 hours and `hubs/hub-b/restore.yaml` restores them passively every 10 minutes (credentials and resources, not the managed clusters). Before syncing, create the `cloud-credentials` secret in `open-cluster-management-backup` on each hub, and label the hand-made secrets on `hub-a` for the credentials backup. Steps, failover and failback: `hub/backup/README.md`.

**Takeover.** Only one hub may manage the clusters at a time. If DC1 is lost: confirm `hub-a` is down, activate the restore on `hub-b` (runbook section 7.4), then uncomment `policies.yaml`, `trident-protect-appset.yaml` and `workloads-appset.yaml` in `argocd-apps-hub-b/kustomization.yaml` and push. Enable `clusters.yaml` only after a DR test has confirmed that the restored hub owns the cluster definitions.

## Phase 3: deploy the production clusters

> **As built:** `ocp-a` was not deployed this way. Redfish virtual media could not mount (the UCS out-of-band NAT has no outbound SNAT for CIMC-initiated traffic; RCA of 2 Nov), so `ocp-a` was installed through the Assisted Installer on console.redhat.com and configured from `manual/ocp-a/`. See docs/ocp-a-as-built.md. `ocp-b` is installed the same way, but imported from git (`clusters/ocp-b/managedcluster.yaml` + a hand-made `auto-import-secret`) so that every day-2 policy applies to it: see docs/ocp-b-build.md. The ClusterInstance procedure below stays for a later hub-driven rebuild.

For each of `ocp-a` and `ocp-b`:

0. **Blades, outside git.** Each blade is out of vSphere (the hub powers every listed blade as soon as the `ClusterInstance` syncs, and the install wipes the boot drive), has the `OCP-Redfish` access profile, and its boot policy has **CIMC Mounted vMedia > CIMC Mounted CD/DVD** after the local disk. The first install (`ocp-a`, 30 Oct) could not use Redfish virtual media: the blade CIMCs report "Mount failed" for every image URL (open item). It was installed from one shared discovery ISO through the KVM instead; that procedure, the problems it brings (Ironic power-offs, disk names, network at first boot) and the investigation are in `docs/bare-metal-provisioning.md`.
1. **Network prerequisites, outside git.** DNS for `api.<cluster>.example.com` and `*.apps.<cluster>.example.com` (done, CHG0000000) and the node hostnames (CHG0000000), plus the F5 virtual servers if used. See "Load balancer choice" below.
2. **Secrets on the hub.** Done once in Phase 1, step 7.
3. **Fill in the cluster's files:**
   - `clusters/<cluster>/clusterinstance.yaml`: VIPs, SSH key, and per node the BMC address, boot MAC (`MGMT_FI-A`), `MGMT_FI-B` MAC (both read from UCS after the blade is bound to the OpenShift template), root disk (`/dev/disk/by-path/pci-0000:04:00.0-ata-1.0`, the 240 GB boot drive on every `ocp-a` blade; `/dev/sdX` names shift with the KVM virtual drives) and management address. The node network is management only (`bond0` + `bond0.24`); do not add storage here.
   - `policies/site-values/<cluster>.yaml`: ONTAP management address, NFS data address, SVM, live migration subnets (`liveMigrationSubnets`, `liveMigrationExclude`).
   - `policies/manifests/storage-network/<cluster>.yaml`: the NFS VLAN and each node's storage address. Each NNCP's `kubernetes.io/hostname` must equal the node name as `oc get nodes` shows it.
4. **Merge.** Argo CD syncs the `ClusterInstance`; the SiteConfig operator renders `ClusterDeployment`, `AgentClusterInstall`, `InfraEnv`, `BareMetalHost` and `NMStateConfig`; the hub boots each server over Redfish, installs, and imports the cluster into ACM. Day-2 policies then add the storage network and Trident (Phase 4).

Watch it:

```
oc get secret -n ocp-a                                    # pull secret and BMC secret copied in
oc get clusterinstance -n ocp-a -o jsonpath='{.items[0].status.conditions}' | jq
oc get bmh,agent -n ocp-a
oc get agentclusterinstall -n ocp-a -o jsonpath='{.items[0].status.debugInfo.state}'
oc get agent -n ocp-a -o custom-columns=HOST:.spec.hostname,STATE:.status.debugInfo.state,STAGE:.status.progress.currentStage,PCT:.status.progress.installationPercentage
oc get managedcluster ocp-a --show-labels                  # env=prod, dr-role=primary, site=dc1
```

Save each cluster's admin kubeconfig to the bastion as a break-glass credential:

```
s=$(oc get clusterdeployment ocp-a -n ocp-a -o jsonpath='{.spec.clusterMetadata.adminKubeconfigSecretRef.name}')
oc extract secret/$s -n ocp-a --keys=kubeconfig --to=- > ~/ocp-a.kubeconfig && chmod 600 ~/ocp-a.kubeconfig
```

Deploy `ocp-a` first and validate it end to end before merging `ocp-b`. To stage that, comment `ocp-b` out of `clusters/kustomization.yaml`.

On the hub, `oc get applications` (and `oc patch application …`) resolves to ACM's `applications.app.k8s.io`; use `oc get applications.argoproj.io -n openshift-gitops` for Argo CD.

## Phase 4: day-2 configuration

No per-cluster steps are needed. When a cluster joins with `env: prod`, the policies bind to it and converge in this order (later ones wait on earlier ones):

| Policy | What it does |
|---|---|
| `install-secrets` | **Hub only.** Copies the pull secret and BMC credentials into every cluster namespace |
| `cluster-hardening` | Removes self-provisioning (the identity banner is now in `common-console`) |
| `compliance-operator`, `compliance-scans` | Installs the Compliance Operator, binds the STIG profiles (scan only) |
| `gitops-guardrails` | Admission policy that rejects hand edits to cluster config |
| `schedulable-control-plane` | Sets `mastersSchedulable: true`, so the control plane nodes also carry the worker role and run VMs |
| `nmstate-operator`, `nmstate-config` | NMState, so NNCPs can be applied |
| `storage-network` | `bond1` and the NFS VLAN on every node, one NNCP per node |
| `trident-operator`, `trident-config` | Certified Trident, the ONTAP NFS backend (waits for `storage-network`), and `ontap-nas` as the default and default-for-VMs storage class |
| `node-network` | VM uplink: `bond2` (`ens5f2`/`ens5f3`), OVS bridge `br-vm`, OVN mapping `vm-trunk` |
| `mtv-vmware-source` | Primary only (ocp-a): MTV provider `vcenter01` (Production vCenter; login from hub secret `vcenter-credentials-ocp-a`), network and storage maps `vcenter01-to-ocp` (port groups to NADs; Charlie datastores `ds_c_0`-`3` to `ontap-nas-vmw-c`, Bravo `ds_b_0`-`6` and Log `ds_l_0`-`2` to `ontap-nas-vmw-b`, Alpha `ds_a_0`-`2` to `ontap-nas-vmw-a`). Plans per wave stay in `migration/` |
| `trident-protect-prereqs` | Namespace `trident-protect` and service account `trident-protect-controller-manager` on every production cluster, so the Trident Protect chart's pre-upgrade hook (run by Argo CD even on a first install) can start |
| `shift-operator` | Primary only (ocp-a): NetApp Shift operator for MTV plans from VMware. Namespace `shift`, NetApp's bundle and PVCs, Shift annotations on `ontap-nas-vmw-c`, `-vmw-b` and `-vmw-a` (backend UUIDs read from the cluster), admin login from hub secret `shift-credentials-<cluster>`, TLS from the service CA. Steps: [docs/shift-operator.md](docs/shift-operator.md) |
| `mtv-hub-settings` | Hub only: `feature_ocp_live_migration: "true"` on the ForkliftController of the hub's MTV (installed by RHACM's add-on), and the CronJob `kubevirt-ca-exchange` that keeps ocp-a and ocp-b trusting each other's KubeVirt CA (every 6 h). Together: cross-cluster live migration |
| `mtv-hub-providers`, `mtv-hub-maps`, `mtv-provider-access` | Hub only (first two): each `env=prod` cluster registered as an MTV provider on the hub (ManagedServiceAccount token, no credentials in git), plus network and storage maps both ways. `mtv-provider-access` gives that service account cluster-admin on the clusters. VMs move between ocp-a and ocp-b from the hub: Migration > Plans |
| `descheduler-operator`, `descheduler-config` | Kube Descheduler Operator with the `KubeVirtRelieveAndMigrate` profile: VMs on busy nodes are live-migrated to quieter ones. Adds `psi=1` to every node (one rolling reboot on first apply). `deschedulerMode` in the site values: `Predictive` logs only, `Automatic` acts |
| `shift-backends` | Trident backends and StorageClasses on the VMware SVMs, for Shift Toolkit imports: `ontap-nas-vmw-c` (SVM_VMW_C, Charlie datastores) `ontap-nas-vmw-b` (SVM_VMW_B, Bravo datastores) and `ontap-nas-vmw-a` (SVM_VMW_A, Alpha datastores); hub secrets `ontap-credentials-vmw-c`, `-vmw-b`, `-vmw-a` |
| `migration-network` | `bond3` (`ens5f4`/`ens5f5`), OVS bridge `br-lm`, OVN mapping `lm-trunk`, and the `live-migration` NAD on VLAN 333 limited to the cluster's block (`liveMigrationExclude`: ocp-a .10–.25, ocp-b .26–.35); waits for the virtualization operator. `virtualization-config` points HyperConverged at it |
| `virtualization-operator`, `virtualization-config` | OpenShift Virtualization, its `HyperConverged` settings, and the `ontap-nas` StorageProfile (RWX, Filesystem, `csi-clone`) |
| `vm-namespaces` | Namespaces the VMs live in, on both clusters |
| `mtv-operator`, `mtv-config` | Migration Toolkit for Virtualization, on the primary only |
| `shift-toolkit-access` | **Temporary, primary only.** Cluster-admin service account token for the NetApp Shift Toolkit |
| `node-maintenance-operator` | Node Maintenance Operator on both clusters; `NodeMaintenance` CRs are created per window, never in git |
| `vm-templates` | Corp VM templates in `openshift`: root disk `<vm>-disk-0` without the CDI populator (ONTAP volume named after the VM), every Corp tag key; `mustonlyhave` |
| `vm-tagging`, `vm-tagging-report` | Admission policy `vm-tags`: the 11 vCenter tags on every new VM (`Warn`/`Deny` from `vmTagEnforcement`; MTV exempt); inform-only report of untagged VMs. [docs/vm-tagging.md](docs/vm-tagging.md) |
| `site-primary`, `site-failover` | Placeholders for configuration that differs between the two sites |

Operators install from the standard `redhat-operators` and `certified-operators` catalogs. Trident Protect arrives separately through the `trident-protect` ApplicationSet once Trident is healthy.

Check a cluster after its policies converge (20 to 40 minutes):

```
oc get policy -n ocp-a                                    # every policy Compliant
K="--kubeconfig $HOME/ocp-a.kubeconfig"
oc $K get nodes                                            # cp01-cp03 show ROLES control-plane,master,worker
oc $K get nncp; oc $K get nnce | grep storage              # SuccessfullyConfigured on every node
oc $K get tbc -n trident                                   # Bound / Success
oc $K get sc; oc $K get storageprofile ontap-nas -o jsonpath='{.status.claimPropertySets}{" "}{.status.cloneStrategy}{"\n"}'
```

**Trident settings still to settle.** `trident-config/trident.yaml` is NetApp's basic sample plus the name template; the advanced fields (NFS mount options, aggregate limit, space and snapshot defaults, encryption) are commented out until the NetApp storage session answers them. Change them here and in `bootstrap/*/hub-storage/04-backend.yaml` together. `trident-config/storageclass.yaml` also has a commented line for the annotation NetApp's Shift Toolkit expects on the target StorageClass; fill it in before the first migration wave.

**To add configuration:** add a plain manifest under `policies/manifests/<name>/`, add a `policies:` entry in `policy-generator.yaml`, merge. For values that differ per cluster, add a key to `policies/site-values/<cluster>.yaml` and read it with a hub template, as `trident-config/trident.yaml` does.

**To test the generator locally** before merging (needs the PolicyGenerator plugin installed, at the same version as Argo CD's; the bastion's copy is older and fails on `recordDiff` / `policySetDefaults`, so until it is updated the `policies` app in Argo CD is the build check: a generator error shows as a red app with the message):

```
kustomize build --enable-alpha-plugins policies/
kustomize build --enable-alpha-plugins common/
```

Every policy is bound through its own Placement (`env: prod`, `dr-role`, `local-cluster` or a `config.example.com` label). Policy sets only group policies for reporting and have no Placement of their own.

### Shared day-2 configuration (`common/`)

`common/` configures the hubs and the production clusters with the same policies. Each feature is switched on per cluster with a label, `config.example.com/<feature>: enabled`; anything else skips it. `common/README.md` has the full table, what each feature needs, and what happens when one is switched off.

| # | Switch | What it does | Default on `ocp-a`, `ocp-b` | Default on the hubs |
|---|---|---|---|---|
| 1 | `htpasswd` | Local break-glass admin (`htpasswd` provider) | enabled | enabled |
| 2 | `ad` | Active Directory login (read-only for every user), LDAP group sync CronJob | enabled | enabled |
| 3 | `etcd-encryption` | AES-GCM encryption of etcd | enabled | enabled |
| 4 | `ntp` | Chrony to `clock1`–`clock3.example.com` (MachineConfig) | enabled | enabled |
| 5 | `console` | Logo, product name, identity banner | enabled | enabled |
| 6 | `namespace-template` | Project template and required namespace prefix | enabled | enabled |
| 7 | `rbac` | AD groups to cluster-admin, cluster-reader, VM admin; break-glass group; the same groups in the hub Argo CD (`common-argocd-rbac`) | enabled | enabled |
| 8 | `ingress-cert` | Corp certificate on `*.apps` | disabled | disabled |
| 9 | `multipath` | `multipathd` and `/etc/multipath.conf` (MachineConfig) | disabled (no SAN LUNs) | disabled |
| 9 | `lldp` | LLDP on every vNIC (NNCP) | enabled | enabled |
| 10 | `metallb` | MetalLB operator, layer 2 pool and advertisement | disabled | disabled |
| 11 | `alerting` | Alertmanager e-mails **critical** alerts to `alertEmailTo` through `smtp.example.com` (`common/alerting/alertmanager.yaml`) | enabled | enabled |
| 12 | `observability` | RHACM MultiClusterObservability on the hub (metrics in ONTAP S3) | – | enabled |
| 13 | `image-registry` | Internal image registry `Managed`, on a ReadWriteMany `ontap-nas` volume (`imageRegistrySize`) | enabled | enabled |
| 14 | `etcd-backup` | Daily etcd backup CronJob (`cluster-backup.sh`) to an `ontap-nas` volume, keeps `etcdBackupRetain` copies. Not the Technology Preview automated backup | enabled | enabled |
| 15 | `techpreview-guard` | Inform only: NonCompliant if the cluster `FeatureGate` uses `TechPreviewNoUpgrade`, `DevPreviewNoUpgrade` or `CustomNoUpgrade` | enabled | enabled |
| 16 | `routing-via-host` | Pod egress through the host routing table, so pods reach ONTAP S3 on the storage subnet over `bond1.222` | enabled | enabled |
| 17 | `mtv-provider` | Cluster registered as an MTV provider on the hub, for VM migration between the clusters | enabled | – |
| 18 | `dii-collector` | Read-only service account for the NetApp DII collector (token created by hand) | enabled | disabled |
| 19 | `mtv-pvc-naming` | MTV plans name disks `<vm>-disk-<n>`, so ONTAP volumes carry the VM name | ocp-a enabled, ocp-b disabled | enabled |
| 20 | `log-forwarding` | Infrastructure and audit logs forwarded to Corp syslog (siem-syslog.example.com (10.62.8.57) and graylog.example.com, TCP 514, RFC5424, APP-NAME `ocp-<cluster>-infra-…` / `ocp-<cluster>-audit-…`) through the OpenShift Logging operator; nothing stored on the cluster | enabled | enabled |
| 21 | `etcd-defrag` | Weekly etcd defragmentation CronJob on the single-node hubs, only when the database is fragmented (at least 100 MiB, under 55% in use); three-node clusters are defragmented by the etcd operator | – | enabled |

**Switches:** `clusters/<cluster>/managedcluster.yaml` (and `extraLabels` in `clusterinstance.yaml` for a rebuild from git) for the production clusters; `hubs/<hub>/local-cluster-labels.yaml` for each hub. **Values:** `common/values.yaml` (same everywhere: LDAP, group names, namespace prefix, product name), plus banner and MetalLB range in `policies/site-values/<cluster>.yaml` and `hubs/<hub>/site-values.yaml`.

**Secrets, on each hub, in the `policies` namespace, before switching the feature on** (shapes in `common/hub-secrets.yaml.example`, never committed):

```
htpasswd -c -B -b users.htpasswd ocpadmin '<password>'          # user = htpasswdAdminUser in common/values.yaml
oc -n policies create secret generic htpasswd --from-file=htpasswd=users.htpasswd
oc -n policies create secret generic ldap-bind --from-literal=bindPassword='<password>'      # when enabling ad
oc -n policies create configmap ldap-ca --from-file=ca.crt=ad-ca.pem                    # when enabling ad
oc -n policies create secret tls ocp-a-ingress-cert --cert=ocp-a-apps-chain.pem --key=ocp-a-apps.key   # when enabling ingress-cert
oc -n policies create secret tls local-cluster-ingress-cert --cert=hub-a-apps-chain.pem --key=hub-a-apps.key
rm users.htpasswd
```

`ntp` and `multipath` are MachineConfigs: each pool reboots one node at a time when they are first applied, and the single-node hubs reboot once. Check:

```
oc -n policies get policy | grep common-                        # on the hub
oc get managedcluster -L config.example.com/ad,config.example.com/ingress-cert,config.example.com/metallb
oc --kubeconfig ~/ocp-a.kubeconfig get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}{"\n"}'
oc --kubeconfig ~/ocp-a.kubeconfig get mcp                     # UPDATED True after ntp and multipath
```

## VM networking

Whichever of NAD, UDN or CUDN is chosen, a VM that sits on a datacenter VLAN needs the same node plumbing first: an NNCP that maps a physical uplink to an OVN network name. That is `policies/manifests/node-network/vm-uplink.yaml`: `bond2` on the two VM vNICs (`ens5f2`/`ens5f3`, `VM_Uplink_FI-A/B`, active-backup, MTU 1500), bridge `br-vm`, OVN mapping `vm-trunk`. It is switched off until the names are confirmed on the first production blade; then uncomment `node-network` in `policy-generator.yaml` and merge. Active-backup uses one link at a time; to use both without LACP, the bond can be built as an OVS bond with `balance-slb` instead.

**Live migration network.** `policies/manifests/migration-network/` follows Red Hat's dedicated migration network pattern, as built on `ocp-a` on 6 Nov: `bond3` on `ens5f4`/`ens5f5` (`Storage_Uplink_FI-A/B`) in OVS bridge `br-lm`, mapped to localnet `lm-trunk`, and an OVN localnet NAD `live-migration` on VLAN 333. The nodes get no address on VLAN 333; the `virt-handler` pods take theirs from `liveMigrationSubnets` minus `liveMigrationExclude` in the site values, which leave each cluster its own block of the range Corp reserved in IPAM on 17 Nov (`10.60.160.10`–`.35`): `ocp-a` `.10`–`.25` (16: 12 nodes, 2 synchronization controllers, 2 spare), `ocp-b` `.26`–`.35` (10: 6 + 2 + 2). DNS: `site-a-pool-01…16-vm` and `site-b-pool-01…10-vm.example.com`. Addresses are taken by pods, not pinned to nodes. To turn it on: uncomment `migration-network` in `policy-generator.yaml`, set `network: live-migration` under **`spec.virtualization.liveMigrationConfig`** in `virtualization-config/hyperconverged.yaml` (OpenShift Virtualization 4.22 ignores the old `spec.liveMigrationConfig`), and make `virtualization-config` depend on `migration-network`.

The three options are side by side in `examples/vm-networks/`, with a comparison table. In short:

- **CUDN with Localnet topology** if the VMs keep their existing VLANs and IP addresses. This is Red Hat's recommended way to connect a VM to a physical network in 4.22, and it fits GitOps best: one cluster-scoped object per VLAN, and namespaces opt in with a label.
- **NAD** is the form the migration tooling expects (see below), and is needed for Linux bridge or SR-IOV.
- **Primary UDN (Layer2)** for new, isolated namespace networks where VMs take cluster-assigned addresses. It does not suit migrated VMs that keep their addresses.

The migration determines part of the choice: MTV and the Shift Toolkit map each VMware port group to a NetworkAttachmentDefinition, so the networks must exist as NADs **before** the plans are written. A plain NAD satisfies that directly, so that is what the repository uses.

**VM networks in this repository (`vm-networks` policy).** `policies/manifests/vm-networks/vm-networks.yaml` has one localnet NAD per VMware port group with VMs, taken from the RVTools export of the Production vCenter (20 October 2026, `migration/vmware-port-groups.csv`): 49 port groups on 47 VLANs, so 49 NADs. **Each NAD is named after its port group**, with `_` and `.` changed to `-` because the Multus admission webhook accepts only DNS-1123 labels: `vm-vlan101` → `default/vm-vlan101`. Two VLANs carry two port groups each (222 and 3060), so they have two NADs on the same VLAN. `vm-vlan101` (untagged on the DVS) is tagged VLAN 88; remove its `vlanID` if UCS carries 88 as the native VLAN on the VM_Uplink vNICs. The 31 port groups with no VMs are left out. Every NAD reaches the physical network through `physicalNetworkName`: `vm-trunk` (`br-vm` on `bond2`) for every VLAN except 222 and 555, and `storage-trunk` for the VLAN 222 and 555 port groups, the in-guest NFS networks (147 VMs), which stay on the storage uplinks as on VMware. For that, the production storage NNCPs build `bond1` as a port of the OVS bridge `br-storage`: the node's NFS address sits on the internal port `nfs222` (access VLAN 222) and the bridge maps `storage-trunk`. All NADs use MTU 1500 and no IPAM, and live in the `default` namespace so that a VM in any namespace can use them. The policy applies to both clusters, so a VM replicated to `ocp-b` finds the same names. `migration/networkmap.yaml` maps all 49 port groups to these NADs.

Before VMs use them:

- `node-network` (the `vm-trunk` bridge mapping) is on; `storage-network` provides `storage-trunk`.
- The UCS VM vNICs must carry every VLAN on `vm-trunk`, including VLAN 308 (`DVS01` on VMware), 24 and 88. VLANs 222 and 555 stay on the storage vNICs (`bond1`), which must carry VLAN 555 as well as 222.
- VLAN 88 is confirmed tagged (or native, see above) on the VM_Uplink vNICs, and VLAN 1 is checked to be carried tagged.
- NADs in `default` are open to every namespace. To limit a VLAN to certain namespaces later, move its NAD into those namespaces (one copy each) or use a localnet CUDN with a namespace selector.

## VM migration from VMware: MTV with Shift or VDDK

VMs move from vCenter `vcenter01` to `ocp-a` with MTV plans, created per wave in the ocp-a console (or from `migration/`). Two paths, chosen per plan:

| Path | Provider and maps | How | Disks land on |
|---|---|---|---|
| **Shift (cold)** | `vcenter01`, maps `vcenter01-to-ocp` | VM powered off; the NetApp Shift operator clones the datastore on its own SVM and Trident imports the clone | `ontap-nas-vmw-c` / `-vmw-b` / `-vmw-a`, then a storage migration to `ontap-nas` (SVM-DR) |
| **VDDK (warm)** | `vcenter01-vddk`, maps `vcenter01-vddk-to-ocp` / `vcenter01-vddk-storagemap` | Disks copied over the network while the VM runs, short cutover | `ontap-nas` directly |

Mapped datastores (both maps, each entry by vCenter id and name, `mustonlyhave`; ids from `scripts/datastore-ids.sh`): Charlie `ds_c_0`-`3`, Bravo `ds_b_0`-`6` and Log `ds_l_0`-`2`, Alpha `ds_a_0`-`2`. Change the maps in git only: the policy reverts console edits. `migration/README.md` has the per-wave steps; `docs/shift-operator.md` and `docs/vm-migration-warm-vddk.md` the details and troubleshooting.

What this repository sets up for it:

- **MTV on the primary**, by policy. NetApp asks for the latest MTV and OpenShift Virtualization supported on 4.22 (2.9.4 or later for the toolkit).
- **A service account with a cluster-admin token** (`shift-toolkit` in `openshift-mtv`), because the toolkit's documentation asks for one. Retrieve it with:
  ```
  oc -n openshift-mtv get secret shift-toolkit-token -o jsonpath='{.data.token}' | base64 -d
  ```
  This is a standing cluster-admin credential held by another team. Remove the `shift-toolkit-access` entry from `policy-generator.yaml` when the migration is done; that deletes the account and revokes the token.
- **The vCenter provider and its maps** (`vcenter01`, `vcenter01-to-ocp`) come from the policy `mtv-vmware-source`, and the Shift operator from the policy `shift-operator` (since 13/16 Nov). **One `Plan` per wave** stays in `migration/` (`plan-wave-1.yaml`), applied by hand or created in the console for each wave.

Agreed with NetApp:

- The Shift Toolkit runs in its **own namespace** `shift` (two pods: `shift-toolkit`, `shift-toolkit-listener`), deployed by the `shift-operator` policy from NetApp's bundle.
- The target StorageClasses `ontap-nas-vmw-c`, `-vmw-b` and `-vmw-a` (on the datastore SVMs) carry NetApp's **Shift annotations**, set by the `shift-operator` policy with the backend UUID read from the cluster.
- **Two providers for one vCenter.** `vcenter01` (cold, Shift, no VDDK) for VMs that can be off during the run; `vcenter01-vddk` (warm, VMware VDDK 8.0.3, disks copied to `ontap-nas`) is for large VMs or VMs that should land straight on SVM-DR-covered storage. First warm run 17 Nov: [docs/vm-migration-warm-vddk.md](docs/vm-migration-warm-vddk.md).
- **Shift plans are cold**, because Shift takes a snapshot: every Shift Plan is `warm: false` and VMs are powered off for the run. Warm plans use the VDDK provider.
- **Disk names.** Switch 19 (`common-mtv-pvc-naming`) gives every new plan the PVC name template `{{.TargetVmName}}-disk-{{.DiskIndex}}`, so ONTAP volumes are named after the VM; VMware names with dots or capitals get their short host name (`app-vm01.corp.example.com` → `app-vm01-disk-0`): [docs/vm-disk-naming.md](docs/vm-disk-naming.md).
- **Tags.** Migrated VMs are not checked by the tag policy and are tagged per wave with `scripts/tag-vm.sh --csv` (or one by one: `scripts/tag-vm.sh` lists the VMs still missing tags): [docs/vm-tagging.md](docs/vm-tagging.md).
- The target namespace can be any VM namespace.
- **Shift converts in place on the SVM that holds the datastore**, so the cluster needs a Trident backend on that SVM. As built on `ocp-a`, the VMware SVMs (SVM_VMW_A, SVM_VMW_B, SVM_VMW_C, SVM_VMW_T) each get their own backend and StorageClass used only by Shift (SVM_VMW_C first, `manual/ocp-a/13.storage-trident/05-backend-vmw-c.yaml`; SVM_VMW_B and SVM_VMW_A added through git on 23 Nov, `policies/manifests/shift-backends/`). A VM on a non-NFS datastore needs a Storage vMotion to NFS first.

The VM networks must also exist on the cluster before the plans are written.

## VMs and git

Git owns the platform the VMs run on: namespaces, networks, storage classes, RBAC, operators. Git does **not** own the 25 migrated VMs. The migration creates them in the cluster, their definitions change at runtime, and their disks are data. They are protected by Trident Protect instead.

- **Protection and replication.** `examples/trident-protect/` has the `AppVault`, `Application`, `Schedule` and `AppMirrorRelationship` objects and says which cluster each goes on. One field (`sourceApplicationUID`) is a runtime value, so the relationship cannot be fully declared ahead of time.
- **Net-new VMs** built after the migration can be declared in git under `apps/` like any other workload, if Corp wants that.
- **What git does own for VMs:** the Corp VM templates (`policies/manifests/vm-templates/`: disk `<vm>-disk-0` named after the VM, every Corp tag key), the tag rules (`vm-tagging`: the 11 vCenter tags are checked on every new VM, `Warn` or `Deny` per cluster from `vmTagEnforcement`), and the report of untagged VMs (`vm-tagging-report`, inform only). Tags on existing VMs are set with `scripts/tag-vm.sh`.

## Remove and redeploy a cluster

Because the clusters carry VMs, tearing one down is a failover first and a rebuild second.

**Remove `ocp-a`:**

1. Fail the VMs over: on `ocp-b`, set each `AppMirrorRelationship` to `desiredState: Promoted` and confirm the VMs are running there.
2. Move traffic at the GTM and take `ocp-a` out of the pool.
3. Comment `- ocp-a` out of `clusters/kustomization.yaml` and merge.
4. Argo CD shows `clusters` as OutOfSync but does nothing, because prune is off. Review the diff, then:
   ```
   argocd app sync clusters --prune
   ```
   ACM detaches the cluster, deprovisions the hosts (wiping local disk metadata) and powers them off.
5. The cluster's volumes are **still on the ONTAP SVM**, since nothing told Trident to delete them. They are prefixed with the cluster name (`ocp_a_`). Remove them on the array once they are no longer needed.

**Redeploy `ocp-a`:**

1. Wait until the `ocp-a` namespace is gone (`oc get ns ocp-a`), then restore the line in `clusters/kustomization.yaml` and merge. If Argo CD keeps failing with `namespaces "ocp-a" not found`, create the namespace and Terminate/Sync the `clusters` app (seen 30 Oct; `docs/bare-metal-provisioning.md`). No secret step: the `install-secrets` policy refills the recreated namespace from `cluster-install-secrets`, and the ONTAP secret in `policies` was never deleted.
2. The cluster reinstalls, re-imports, and converges: Trident, networking, Virtualization and Trident Protect all come back by label, with no manual steps. It has no VMs yet.
3. Re-establish replication from `ocp-b` back to `ocp-a` (reverse the relationship), let it sync, then fail back and restore the GTM.

Removing `ocp-b` needs no failover or traffic move (skip steps 1 and 2 of the removal), and replication is simply re-created towards it afterwards.

## The failover model

Both clusters carry `env: prod`, so they get identical platform configuration. They differ only by `dr-role` (`primary` or `failover`) and `site`.

- **Platform configuration:** identical on both, by design, so that failover is predictable. VM namespaces and networks exist on both sides ahead of time.
- **VM data:** Trident Protect replicates each VM namespace from `ocp-a` to `ocp-b` over SnapMirror. Failover is promoting the relationship on `ocp-b`.
- **Traffic:** the GTM decides which cluster receives users. This sits outside Kubernetes and can be automated with Ansible Automation Platform (AAP).
- **Addresses:** for VMs to keep their IPs after failover, the same VLANs must be reachable at both sites. If they are not, failover requires re-addressing or DNS changes, which must be designed before the first failover test.

## Upgrades

Copy `clusters/<name>/clustercurator-upgrade.yaml.example` to `clustercurator-upgrade.yaml`, set the version, list it in that folder's `kustomization.yaml`, and merge. The AAP pre-hook drains the cluster from the GTM and the post-hook restores it. Upgrade `ocp-b` first, then `ocp-a`. Add a matching `ClusterImageSet` for the new release first. Check the Trident and Trident Protect support matrix before each OpenShift minor upgrade.

## Load balancer choice

The templates use the **default cluster-managed VIPs**: `apiVIPs` and `ingressVIPs` are spare addresses on the node network, held by keepalived on the cluster. Point the F5 virtual servers at those two addresses (or pool the nodes directly).

If Corp prefers the F5 to own the VIPs, with no keepalived on the clusters, the setting is `loadBalancer.type: UserManaged` on the `AgentClusterInstall`. Check whether `ClusterInstance` exposes this field in the installed RHACM release (`oc explain clusterinstance.spec`). If it does not, create a copy of the `ai-cluster-templates-v1` ConfigMap, add the field to its `AgentClusterInstall` template, and reference the copy in `templateRefs`. This choice must be made before the first install; it cannot be changed afterwards.

## Items to confirm on the installed releases

The following were prepared from product documentation and should be confirmed on the first live cluster:

- **Install secret copy.** The `install-secrets` policy assumes the hub is the managed cluster `local-cluster` in the `default` cluster set (`oc get managedcluster local-cluster --show-labels`). On the first install, confirm the two secrets appear in the cluster namespace and that the `ClusterInstance` picks them up; if it reports missing secrets because it was created moments before the copy completed, the condition clears on its own.
- **`ClusterInstance` field names.** `oc explain clusterinstance.spec` and `oc explain clusterinstance.spec.nodes`.
- **PolicyGenerator init container.** Image tag and binary name in `bootstrap/argocd/argocd-policygenerator-patch.yaml`.
- **Operator channels.** ACM is set to `release-2.17` and MTV to `release-v2.12`; check both with `oc get packagemanifest <name> -n openshift-marketplace`.
- **Hub memory reservation.** `hub/node/kubeletconfig.yaml` (`autoSizingReserved`) is held: enable it per hub in a maintenance window (one reboot) to clear `SystemMemoryExceedsReservation`.
- **Argo CD and duplicate finalizers.** If `hub-config` shows sync status `Unknown` with `duplicate entries for key ["cluster.open-cluster-management.io/submariner-cleanup"]`, remove the duplicate from the `prod` ManagedClusterSet (`jq '.metadata.finalizers | unique'`); it blocks every sync of the app.
- **Release image.** Both hubs and `ocp-a` run **4.22.20** (updated 5 Nov). `hub/acm/clusterimageset-4.22.yaml` installs 4.22.20 (`img4.22.20-x86-64`), referenced by both ClusterInstances. The discovery ISO (`osImages` in `hub/acm/agentserviceconfig.yaml`) must be the RHCOS build of that same release: an older ISO is the probable cause of nodes losing their static network after the reboot onto disk. Read the build and ISO URL from a hub that runs 4.22.20 and put them in `osImages`:
  ```
  oc -n openshift-machine-config-operator get configmap coreos-bootimages -o jsonpath='{.data.stream}' \
    | jq -r '.architectures.x86_64.artifacts.metal | .release, .formats.iso.disk.location'
  ```
  Move all three (hub release, ClusterImageSet, `osImages`) together on every z-stream update.
- **Trident Protect.** Chart version and Helm values are from the 26.06 install page. The `AppVault` credential layout and which cluster each object belongs on should be checked against the NetApp documentation for the installed version.
- **MTV objects in `migration/`.** `oc explain plan.spec`, and the same for `provider`, `networkmap` and `storagemap`, on the MTV version installed.
- **Shift Toolkit prerequisites.** The list in `migration/README.md` is from NetApp's documentation; have the NetApp team confirm it for the version they run.
- **CUDN and UDN field placement.** `oc explain clusteruserdefinednetwork.spec.network.localnet`.
- **Redfish.** Verified 28 Oct on all 18 blades: blade KVM address, system ID = serial, login through the `OCP-Redfish` access profile, DVD virtual media and CD boot available. **Virtual media does not mount** (30 Oct): every `InsertMedia` on the CIMC DVD ends in "Mount failed" within a second, for the hub's URL and for test servers on ports 80 and 6180. Investigation, workaround and the production SVM template: `docs/bare-metal-provisioning.md`.
- **BareMetalHosts of `ocp-a`.** Paused since 30 Oct (Ironic powered blades off during the manual-ISO install). Decide how to hand them back before removing the pause: they are still in `inspecting`.
- **`disableVirtualMediaTLS`** in `hub/acm/provisioning.yaml` (set 30 Oct): keep or revert once the virtual media cause is known.
- **Hub DR.** Passive restore on `hub-b` excludes Argo CD resources after the 28 Oct incident; run the checks in `hub/backup/README.md` after any restore.
- **NIC names and service profiles.** `ens5f0`–`ens5f7` with the 8-vNIC OpenShift template (confirmed on both hubs). The `ocp-a` blades were installed on 30 Oct while still on their ESXi service profiles (`bl-esx-*`), with the MACs from the host sheet; VLAN 24 is tagged (`bond0.24`). Before the day-2 NNCPs apply (`ens5f2`–`ens5f7`), check `ip -br link` on the installed nodes and decide whether the blades move to the OpenShift template (that changes their MACs).
- **Export policy of each production SVM.** It must allow read-write and superuser from `10.60.140.0/24`; set `ontapExportPolicy` in `policies/site-values/<cluster>.yaml` (on `SVM_OCP_B` that is `SVM_Default`).
- **`Storage_Uplink` carries VLAN 333** (live migration, `bond3`), and **`VM_Uplink` carries the former `INFRA_Pub` VLANs** (`bond2`).
- **NNCP node selectors.** `kubernetes.io/hostname` in `storage-network/` must match the node names exactly (short name or FQDN).
- **Admission guardrail.** Ships in Warn and Audit mode. Review audit logs before switching it to Deny. The same applies to the `namespace-prefix` policy in `common/` and to the VM tag policy `vm-tags` (`vmTagEnforcement`).
- **Template parameters and the 4.22 wizard.** The Create VirtualMachine wizard cannot process templates whose parameters are `required: true` without a value (it stops at *Customization*): keep Corp template parameters with `value: ''`.
- **`recordDiff` in manifests.** The managed clusters' ConfigurationPolicy rejects `spec.recordDiff` (*unknown field*); set it in the generator only.
- **Console logos field.** `common/manifests/console/console.yaml` uses `spec.customization.logos`; confirm with `oc explain console.spec.customization.logos`.
- **Hub templates in `common/`.** `.ManagedClusterLabels`, `fromSecret` and `autoindent` are used in hub templates; check `oc -n policies get policy common-oauth -o yaml` for template errors on the first sync.

## Not yet included

- **ACS.** Central on the hub and `SecuredCluster` on each production cluster by policy.
- **Removal of `kubeadmin`** once the AD provider and the break-glass `htpasswd` admin are proven (`common/`).
- **Secrets management.** External Secrets Operator and the vault connection.
- **AAP job templates** for F5, GTM, DNS, and the Trident Protect failover steps.
- **A second Trident backend** (`ontap-nas-economy`), needed only if the Shift Toolkit finds VMDKs laid out in qtrees.
- **The OpenShift Update Service** instance on the hub.
- **Trident on the hubs under git.** `bootstrap/*/hub-storage/` is applied by hand once; it can be moved under `hubs/<hub>/` if the hubs' storage should also be enforced from git (the secret stays out).
