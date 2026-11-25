# Corp OpenShift GitOps Runbook

16 Nov 2026

Operations guide for this repository: how it works, worked examples for adding nodes, networks, operators and vCenters, console checks, and troubleshooting. Diagram sources: `docs/diagrams/*.mmd` (render with `mmdc -c cfg.json`).

How the Corp OpenShift Virtualization platform is built, configured and operated from git: every Argo CD application, every RHACM policy, the order they run in, where the values and secrets come from, how VMs move between clusters and from VMware, and what to do when something goes wrong. Repository: `https://github.com/CHANGEME/ocp-local.git` (branch `main`), working copy on the bastion `vm-openshift-tools` at `~/ocp-local/ocp-local`.

## Start here: the platform in plain language

Think of the platform as a **building managed from a blueprint**. The blueprint is the git repository. Nobody walks into the building and moves walls by hand: they change the blueprint, and a team of robots reads the blueprint and makes the building match it, then keeps checking every few minutes that nobody has changed anything behind their backs.

| Term | In plain words | Where to see it |
| --- | --- | --- |
| **Cluster** | A group of servers that act as one big computer and run applications and virtual machines (VMs) | Hub console → *Fleet Management* → *Infrastructure* → *Clusters* |
| **Hub (hub-a, hub-b)** | The control tower. It does not run the organization's VMs; it manages the clusters that do. hub-b is the spare control tower at the other data centre | Hub console |
| **Production clusters (ocp-a, ocp-b)** | Where the VMs actually run. ocp-a at DC1 is the main one, ocp-b at DC2 is the backup site | Each cluster's own console |
| **Git / the repository** | The blueprint: text files that describe exactly how everything should be set up, with a full history of who changed what and why | github.com → CHANGEME/ocp-local |
| **Commit / push** | Saving a change to the blueprint and sending it to github.com | github.com → *Commits* |
| **Argo CD** | The robot that watches git. When the blueprint changes, it copies the change onto the hub | Hub console → app launcher (grid icon, top right) → *Cluster Argo CD* |
| **RHACM (Advanced Cluster Management)** | The manager in the control tower that hands instructions to every cluster and collects their reports | Hub console → *Fleet Management* |
| **Policy** | One instruction for the clusters, e.g. “install the storage driver” or “use these time servers”. Each policy is either **Compliant** (done and still true) or **Not compliant** (not done, or someone changed it) | Hub console → *Fleet Management* → *Governance* → *Policies* |
| **Label** | A sticker on a cluster, like “production” or “primary site”. Policies are addressed to stickers, not names, so a new cluster with the right stickers automatically gets the right setup | *Clusters* → a cluster → *Labels* |
| **Site values** | A small per-cluster settings sheet (IP addresses, storage names, banner text) kept in git | git: `policies/site-values/` |
| **Secret** | A password or key. Never stored in git; typed in once on the hub and handed to the clusters encrypted | Hub console → project *policies* → *Workloads* → *Secrets* (names only) |
| **Operator** | An add-on that installs and looks after a product (storage driver, virtualization, migration tools) | Cluster console → *Ecosystem* / *Operators* → *Installed Operators* |
| **NetApp ONTAP / Trident** | The storage arrays that hold the VM disks, and the driver that lets OpenShift create disks on them | Cluster console → *Storage* → *PersistentVolumeClaims* |
| **VM migration (MTV)** | Moving a VM from one place to another: from VMware into OpenShift, or between the two production clusters | Hub console → *Migration* → *Migration plans* |
| **Live vs cold migration** | Live = the VM keeps running while it moves (like moving house while the family is still inside). Cold = the VM is shut down, moved, then started | Plan details → *Migration progress* |
| **Backup of the hub** | A copy of the control tower's memory, taken every 2 hours and stored at the other data centre so hub-b can take over | Hub console → *Installed Operators* → OADP → *Backup* |

### The three things to remember

1. **Every change starts in git.** If it is not in git, it will either be undone automatically or be lost on the next rebuild.
2. **Green means done.** A change is finished when Argo CD shows *Synced / Healthy* and the policy shows *Compliant* for every cluster.
3. **Passwords never go in git.** They are typed in once on the hub and the policies pass them on.

## Where to look: a tour of the web consoles

Every check in this runbook can be done by clicking, without the command line. The command-line versions are given too for people who prefer them.

| Console | How to open it | What to check there | What “good” looks like |
| --- | --- | --- | --- |
| **Git (github.com)** | Browser → github.com → CHANGEME/ocp-local | *Commits*: the latest change, author, message; *Files*: the blueprint | Your commit is at the top of `main` |
| **Argo CD (on hub-a)** | hub-a console → grid icon top right → *Cluster Argo CD* → log in with OpenShift | The tiles: `root`, `hub-config`, `clusters`, `policies`, `common-config`, `trident-protect-*` | Every tile green: **Healthy** + **Synced**; *Last Sync* shows your commit |
| **Clusters (RHACM)** | hub-a console → perspective switcher (top left) → *Fleet Management* → *Infrastructure* → *Clusters* | Status of ocp-a and ocp-b, their labels, add-ons | Status **Ready**; labels match git |
| **Governance (RHACM)** | *Fleet Management* → *Governance* → *Policies* (and *Policy sets*) | Each policy and its status per cluster; click a policy → *Results* for the exact message | **No violations**; every cluster **Compliant** |
| **Grafana (Observability)** | *Fleet Management* → *Overview* → *Grafana* link | CPU, memory, storage of each cluster | ocp-a and ocp-b both listed with data |
| **Migration (MTV on the hub)** | hub-a console → *Core platform* perspective → *Migration* → *Providers* / *Migration plans* | Providers ocp-a and ocp-b; plans and their progress | Providers **Ready**; plan **Succeeded**, each step with a green tick |
| **Cluster console (ocp-a / ocp-b)** | https://console-openshift-console.apps.\<cluster>... (red PRODUCTION banner at top) | *Compute → Nodes*, *Virtualization → VirtualMachines*, *Networking*, *Storage*, *Installed Operators* | Nodes **Ready**, VMs **Running**, operators **Succeeded** |
| **ONTAP System Manager** | Storage team | Volumes created by Trident, SnapMirror relationships | Volumes **Online**; relationships **Healthy** |

Figure 0 — Argo CD on hub-a: every tile green (Healthy, Synced) means git and the hub agree.


&#91;image: Argo CD tiles all green\]

## 1. The platform at a glance

> **In plain words:** two control towers (the hubs) and two sets of servers that run the VMs (the production clusters), one of each at each data centre. The NetApp arrays hold the VM disks. Each server has four separate network connections: one for management, one for storage, one for VM traffic and one only for moving VMs.
>
> **Check it in the console:** hub-a → *Fleet Management* → *Infrastructure* → *Clusters* shows ocp-a and ocp-b as **Ready**; in each cluster's console *Compute* → *Nodes* shows 12 (ocp-a) and 6 (ocp-b) nodes **Ready**.

| Cluster | Site | Role | Nodes | Version | How it is managed |
| --- | --- | --- | --- | --- | --- |
| `hub-a` | DC1 (Site A) | Main RHACM hub, single-node OpenShift. Runs Argo CD, RHACM governance, MTV (hub integration), Observability, hub backups | 1 | 4.22 | Assisted Installer, then `bootstrap/hub-a/` |
| `hub-b` | DC2 | Standby hub. Restores hub-a's backups passively; takes over if DC1 is lost | 1 | 4.22 | Assisted Installer, then `bootstrap/hub-b/` |
| `ocp-a` | DC1 | Primary production (`dr-role: primary`). Runs VMs, MTV, NetApp Shift operator, vCenter source | 12 | 4.22.20, Virtualization 4.22.16 | Assisted Installer, adopted into GitOps 12 Nov |
| `ocp-b` | DC2 | Failover production (`dr-role: failover`) | 6 | 4.22.20, Virtualization 4.22.16 | Assisted Installer, then imported and configured 100% from git (rebuilt from scratch) |

Storage is NetApp ONTAP over NFS v4.1 through Trident: SVM `SVM_OCP_A` serves ocp-a, `SVM_OCP_B` serves ocp-b, and the VMware datastore SVMs `SVM_VMW_C`, `SVM_VMW_B` and `SVM_VMW_A` have Trident backends on the production clusters for the Shift migration path. Every blade has four bonds: `bond0` management, `bond1 → br-storage` (storage VLAN, 10.60.140.0/24), `bond2 → br-vm` (VM VLANs), `bond3 → br-lm` (live migration, VLAN 333).

Figure 1 — Architecture: hubs, production clusters, ONTAP and the numbered network flows.


&#91;image: Architecture: hub-a and ocp-a at DC1, hub-b and ocp-b at DC2, ONTAP at both sites\]

Figure 2 — Node networking on every blade.


&#91;image: Node networking: bond0 management, bond1 storage, bond2 VM, bond3 live migration\]

### Core principle

Nothing on the production clusters is configured by hand. A change is a commit; Argo CD on the hub picks up the commit; RHACM turns the YAML into Policies; the policy framework enforces them on every cluster whose labels match, and keeps enforcing them (drift is reverted within seconds). The console banner on both clusters says it: *PRODUCTION - changes are made through git only*.

## 2. How the GitOps loop works

> **In plain words:** someone edits the blueprint and saves it to git. Argo CD notices within about 3 minutes and copies it to the hub. The hub turns it into instructions (policies) and sends them to the clusters, which carry them out and report back “done”. If anyone changes something by hand later, the cluster puts it back.
>
> **Check it in the console:** Argo CD tiles green → *Governance* → *Policies* shows no violations → the setting is visible on the cluster (e.g. the red PRODUCTION banner at the top of each cluster console comes from a policy).

Figure 3 — The GitOps loop: git → Argo CD on the hub → RHACM policies → clusters.


&#91;image: GitOps loop\]

1. An engineer edits YAML on the bastion and pushes to `main`.
2. Argo CD on `hub-a` polls the repository (about every 3 minutes) or is synced by hand.
3. The app-of-apps `root` (path `argocd-apps/`) creates the child applications below.
4. The `policies` and `common-config` applications run the **PolicyGenerator** kustomize plugin, which turns plain manifests into RHACM `Policy`, `PolicySet`, `Placement` and `PlacementBinding` objects in the hub namespace `policies`.
5. RHACM's governance framework copies each policy into the namespace of every matching cluster and the config-policy-controller on that cluster enforces it.
6. Status flows back: each policy shows Compliant / NonCompliant per cluster in *Governance* on the hub and in `oc get policy -A`.

### Argo CD applications on hub-a

| Application | Source path | Sync | What it does |
| --- | --- | --- | --- |
| `root` | `argocd-apps/` | auto, prune | App of apps: creates every application in this table. Created once by hand from `bootstrap/hub-a/root-app.yaml` |
| `hub-config` (wave 0) | `hubs/hub-a` → `hub/` | auto, no prune, ServerSideApply | The hub itself: MultiClusterHub (with `cnv-mtv-integrations` patched on), AgentServiceConfig, ClusterImageSet, ClusterSet `prod`, OADP DPA + BackupSchedule, KubeletConfig (maxPods 500), NMState storage network, GitOps ↔ ACM integration, site-values ConfigMap for the hub |
| `clusters` (wave 1) | `clusters/` | auto, **no prune** | One folder per production cluster: Namespace, ManagedCluster (labels drive everything), KlusterletAddonConfig. Prune is off so a commented-out line never detaches a cluster by accident |
| `policies` (wave 1) | `policies/` | auto, prune | PolicyGenerator for production: policy sets `prod-baseline`, `prod-virtualization`, `prod-site`, `hub-services`; plus the site-values ConfigMaps |
| `common-config` (wave 1) | `common/` | auto, prune | PolicyGenerator for day-2 platform settings switched on per cluster with `config.example.com/*` labels (OAuth/AD, NTP, console, RBAC, etcd encryption, alerting, image registry, etcd backup …) |
| `trident-protect` ApplicationSet (wave 2) | Helm chart `trident-protect` 100.2606.0 from `netapp.github.io` | auto, prune | One Application per cluster in Placement `prod-clusters`, pushed by Argo CD directly to the cluster |
| `example-app` ApplicationSet | `apps/example-app` | auto | Pattern for future workloads pushed to the clusters |

Why Trident Protect is an ApplicationSet and not a policy: it ships as a Helm chart with pre-install/pre-upgrade hooks and CRDs; Argo CD renders and orders Helm hooks, the policy framework does not. Its prerequisites (namespace and the `trident-protect-controller-manager` ServiceAccount the hook needs) *are* a policy: `trident-protect-prereqs`.

`hub-b` has its own folder `argocd-apps-hub-b/`: on the standby only `hub-config` and `common-config` are active (the hub's own day-2 settings), so the standby never fights the main hub for the production clusters. All application objects carry `velero.io/exclude-from-backup: "true"`, so a restore never brings hub-a's applications onto hub-b.

**Argo CD sizing and health (policy `common-argocd-resources`, both hubs).** The application controller runs with a 2Gi memory request and a 6Gi limit: at the operator default (2Gi limit) it was OOMKilled on hub-a on 19 Nov while syncing a large change. The same policy adds a health rule for RHACM policies:

| Policy state | Argo CD shows |
| --- | --- |
| Compliant | Healthy |
| NonCompliant | Degraded |
| Placed, waiting for the first result | Progressing |
| Placed on no cluster (a `common/` switch that is off everywhere) | Healthy, "Not placed on any cluster (switch off)" |
| Annotated `example.com/argocd-health: report-only` (`vm-tagging-report`) | Healthy, with the compliance in the message |

Changing that health rule in git leaves the old version next to the new one on the ArgoCD CR (`musthave` adds list items, it never removes them). After the sync, remove the list once and the policy writes back only the current version: `oc $H -n openshift-gitops patch argocd openshift-gitops --type json -p '[{"op":"remove","path":"/spec/resourceHealthChecks"}]'` (same on hub-b).

Figure 4 — Argo CD on hub-a: all applications Synced and Healthy.


&#91;image: Argo CD applications on hub-a\]

## 3. Repository layout

> **In plain words:** the repository is organised like a filing cabinet: one drawer for the hubs, one for the list of clusters, one for production instructions (policies), one for shared platform settings (common), and one for documents and migration plans.
>
> **Check it in the console:** github.com → ocp-local → browse the folders; each Argo CD tile shows which folder (*Path*) it reads.

| Path | Purpose |
| --- | --- |
| `bootstrap/` | One-time, by hand: GitOps and ACM operator subscriptions, the Argo CD PolicyGenerator patch, RBAC, the `root` app per hub, hub storage, example install secrets |
| `argocd-apps/`, `argocd-apps-hub-b/` | The child applications for each hub (see section 2) |
| `hub/` | Shared hub configuration: `acm/` (MultiClusterHub, AgentServiceConfig, ClusterImageSet, ClusterSet, search storage), `backup/` (DPA with the S3 CA, README), `gitops/`, `network/` (NMState), `node/` (KubeletConfig), `observability/` |
| `hubs/hub-a`, `hubs/hub-b` | Per-hub kustomize overlays on `hub/`: storage network, site values, local-cluster labels, BackupSchedule (hub-a) or passive Restore (hub-b), and the JSON patch that turns `cnv-mtv-integrations` on only on hub-a |
| `clusters/` | `kustomization.yaml` (one line per cluster) and `clusters/<name>/`: namespace, `managedcluster.yaml`, `clusterinstance.yaml` (for a future bare-metal-from-git build), upgrade curator example |
| `policies/` | `policy-generator.yaml`, `manifests/<policy>/` (one folder per policy), `site-values/<cluster>.yaml` |
| `common/` | `policy-generator.yaml`, `manifests/`, `values.yaml` (LDAP, NTP servers, alert mail), `placements/`, `hub-secrets.yaml.example` |
| `apps/`, `examples/` | Workload pattern; examples for Trident Protect AppVault/backup and VM networks |
| `migration/` | MTV wave plans (`plan-wave-1.yaml`), vCenter CA chain, the VMware port-group list |
| `docs/` | As-built and how-to: `gitops-operations-guide.md` (this guide), `ocp-a-gitops.md`, `ocp-b-build.md`, `vm-migration-between-clusters.md`, `vm-migration-warm-vddk.md`, `shift-operator.md`, `vm-disk-naming.md`, `vm-tagging.md`, `dii-collector.md`, `diagrams/`, images |
| `scripts/` | `tag-vm.sh` (Corp tags on existing VMs: interactive, one line, or a CSV wave), `add-vm-disk.sh` (extra disk named `<vm>-disk-<n>`), `vm-storage-map.sh` (VM → disk → PVC → ONTAP volume), `build-vddk-image.sh` (VDDK init image for warm migration), `Remove-VMwareTools.ps1.txt` (post-migration clean-up on Windows guests) |

## 4. Policies: how they are generated

> **In plain words:** each instruction is written as a normal settings file. A tool called the PolicyGenerator wraps each file into a policy and says who gets it (by sticker/label), in what order (“install storage before virtualization”), and how strict to be (“enforce” = fix it, not just report it). Passwords are looked up from the hub at the last moment, so they are never written in git.
>
> **Check it in the console:** *Governance* → *Policies* → click any policy → *Details* shows its placement (which clusters) and *Results* shows the status per cluster. *Clusters* → a cluster → *Overview* → *Labels* shows the stickers that decide what it gets.

`policies/policy-generator.yaml` is the heart of the repository. Each entry names a folder of plain Kubernetes YAML; the generator wraps it into a `ConfigurationPolicy` inside a `Policy`.

Defaults that apply to every production policy:

| Setting | Value | Why |
| --- | --- | --- |
| `remediationAction` | `enforce` | Create and correct, not just report |
| `namespace` | `policies` | All generated objects live in one hub namespace |
| `pruneObjectBehavior` | `None` | Deleting a policy never deletes cluster objects (VM data is safe) |
| `recordDiff` | `None` on secret-bearing policies | Never write secret values into policy status |
| `consolidateManifests` | `false` where one template depends on another (shift-operator) | One ConfigurationPolicy per manifest, so one failed template does not block the rest |
| `complianceType` | `musthave`; `mustonlyhave` for the MTV maps and `vm-templates` | `musthave` only adds and updates: a field or list entry removed in git stays on the cluster. `mustonlyhave` makes the object match git exactly (merged map entries lost `accessMode`; a removed `required: true` stayed on the template) |
| default placement | `env In [prod]` | Both production clusters |

Figure 5 — Labels on the ManagedCluster decide which policy sets reach a cluster.


&#91;image: Labels to policy sets\]

### Placement by labels

Every production cluster carries these labels in `clusters/<name>/managedcluster.yaml`:

| Label | Values | Used by |
| --- | --- | --- |
| `env` | `prod` | All production policies (default placement), Trident Protect ApplicationSet |
| `dr-role` | `primary` (ocp-a), `failover` (ocp-b) | `prod-site`: MTV operator, Shift operator, vCenter source only on the primary |
| `site` | `dc1`, `dc2` | Site-specific values |
| `vendor`, `cloud` | `OpenShift`, `Other` | Observability add-on (without `vendor` the cluster never appears in Grafana) |
| `config.example.com/<switch>` | `enabled` / `disabled` | One common policy each: htpasswd, ad, etcd-encryption, ntp, console, namespace-template, rbac, ingress-cert, multipath, lldp, metallb, alerting, image-registry, etcd-backup, techpreview-guard, routing-via-host, mtv-provider, dii-collector (18), mtv-pvc-naming (19), log-forwarding (20), etcd-defrag (21, hubs only). On the hubs the same switches are set in `hubs/<hub>/local-cluster-labels.yaml` |
| `cluster.open-cluster-management.io/clusterset` | `prod` | ClusterSet bound to the `policies` and `openshift-gitops` namespaces |

### Values and secrets

Figure 6 — Values come from git (site values); secrets come from hub secrets; templates resolve them on the hub.


&#91;image: Values and secrets flow\]

- **Site values** — `policies/site-values/<cluster>.yaml` becomes ConfigMap `<cluster>-site-values` in `policies`. Manifests read it with hub templates: `{{hub fromConfigMap "policies" (printf "%s-site-values" .ManagedClusterName) "ontapSVM" hub}}`. Keys include `ontapManagementLIF`, `ontapDataLIF`/`ontapDataLIF2`, `ontapAggregate`/`2`, `ontapSVM`, `ontapExportPolicy`, `liveMigrationSubnets`, `liveMigrationExclude`, `deschedulerMode`, `vcenterFQDN`, `vddkInitImage` (ocp-a, pinned by digest), `vmTagEnforcement` (`Warn` or `Deny`), console banner, `alertClusterName`, `metallbAddresses`.
- **Secrets** — never in git. Created on the bastion with `read -s` prompts into the hub namespace `policies`: `ontap-credentials-<cluster>`, `ontap-credentials-vmw-c`, `-vmw-b`, `-vmw-a`, `shift-credentials-ocp-a`, `vcenter-credentials-ocp-a`, `<cluster>-ingress-cert`, LDAP bind. Templates read them with `{{hub fromSecret "policies" "ontap-credentials-ocp-a" "password" hub}}`; the value is copied encrypted into the policy and decrypted only on the cluster. Hub secrets carry the backup label so they reach hub-b.
- **Managed-cluster templates** — `{{ lookup … }}` / `{{ fromSecret … }}` without `hub` run on the cluster itself; used where the value only exists there (e.g. the Trident backend UUID for the Shift StorageClass, the service-CA certificate for Shift TLS).

## 5. Policy catalogue

> **In plain words:** this is the full list of instructions and what each one sets up. They are grouped into bundles: basic security, everything needed to run VMs, extra tools only for the main site (VMware migration), tools on the hub itself, and general platform settings switched on per cluster.
>
> **Check it in the console:** *Governance* → *Policy sets* shows each bundle with a count of compliant clusters; click a bundle to see its policies. On a cluster, the result is visible where the thing lives: operators under *Installed Operators*, networks under *Networking* → *NodeNetworkConfigurationPolicy*, storage under *Storage* → *StorageClasses*.

Figure 7 — Dependency chain: a policy waits until every policy it depends on is Compliant.


&#91;image: Policy dependency chain\]

### Policy set `prod-baseline` (env=prod)

| Policy | What it enforces | Depends on |
| --- | --- | --- |
| `cluster-hardening` | Baseline security settings | — |
| `compliance-operator` / `compliance-scans` | Compliance Operator and scheduled CIS/moderate scans | operator → scans |
| `gitops-guardrails` | Guards against hand edits of managed objects | — |
| `schedulable-control-plane` | Control-plane nodes accept workloads where the design requires | — |

### Policy set `prod-virtualization` (env=prod)

| Policy | What it enforces | Depends on |
| --- | --- | --- |
| `trident-operator` | NetApp Trident operator | — |
| `trident-config` | TridentOrchestrator, backend secrets and `TridentBackendConfig`s (two LIFs, two aggregates), StorageClass `ontap-nas` (default, RWX), VolumeSnapshotClass | trident-operator, storage-network |
| `shift-backends` | Backends + StorageClasses on the VMware datastore SVMs for the Shift clone-in-place path: `ontap-nas-vmw-c` (SVM_VMW_C), `ontap-nas-vmw-b` (SVM_VMW_B), `ontap-nas-vmw-a` (SVM_VMW_A) | trident-config |
| `trident-protect-prereqs` | Namespace `trident-protect`, ServiceAccount `trident-protect-controller-manager` (needed by the Helm pre-upgrade hook) | — |
| `nmstate-operator` / `nmstate-config` | Kubernetes NMState operator and instance | operator → config |
| `storage-network` | NNCP: `bond1` → `br-storage`, storage VLAN address per node | nmstate-config |
| `node-network` | NNCP: `bond2` → `br-vm` bridge for VM VLANs | nmstate-config |
| `migration-network` | NNCP `bond3` → `br-lm` (VLAN 333) and NAD `live-migration` (whereabouts IPAM, `liveMigrationSubnets` minus `liveMigrationExclude`) | nmstate-config, virtualization-operator |
| `virtualization-operator` | OpenShift Virtualization operator | trident-config |
| `virtualization-config` | HyperConverged: `decentralizedLiveMigration: true`, liveMigrationConfig (network `live-migration`, 800 s/GiB completion timeout, 5 parallel per cluster / 2 per node); StorageProfiles for `ontap-nas` and the three `ontap-nas-vmw-*` Shift classes (RWX, Filesystem, csi-clone) | virtualization-operator, migration-network |
| `descheduler-operator` / `descheduler-config` | Kube Descheduler with the `KubeVirtRelieveAndMigrate` profile; PSI enabled by MachineConfig (`psi=1`, rolling reboot); mode from site value `deschedulerMode` (Predictive = log only, Automatic = rebalance) | virtualization-config |
| `vm-namespaces` | VM project namespaces | — |
| `vm-networks` | 49 `NetworkAttachmentDefinition`s, one per VMware port group (same names on both clusters, so maps are 1:1) | — |
| `mtv-provider-access` | ClusterRoleBinding `mtv-provider-cluster-admin` for the hub's ManagedServiceAccount (only where `config.example.com/mtv-provider=enabled`) | — |
| `node-maintenance-operator` | Node Maintenance Operator (namespace `openshift-workload-availability`, channel stable). `NodeMaintenance` CRs are created per maintenance window, never in git | virtualization-config |
| `vm-templates` | Corp VM templates in `openshift` (Template catalog → "Corp …"): root disk `<vm>-disk-0` created without the CDI populator (ONTAP volume named after the VM), every Corp tag key on the VM. `mustonlyhave` | virtualization-config |
| `vm-tagging` | ValidatingAdmissionPolicy `vm-tags` + binding: every new VM must carry the 11 Corp tags and valid Environment / SupportLevel / DRTier values. `Warn` or `Deny` from site value `vmTagEnforcement`. MTV, `openshift-cnv`, `openshift-*` and namespaces labelled `example.com/vm-tags=exempt` are not checked | virtualization-config |
| `vm-tagging-report` | **Inform only**: one entry per VM missing tags (labels or annotations), including migrated VMs. Argo CD shows it Healthy (`report-only`) | virtualization-config |

### Policy set `prod-site` (by dr-role)

| Policy | Placement | What it enforces | Depends on |
| --- | --- | --- | --- |
| `mtv-operator` / `mtv-config` | primary | Migration Toolkit for Virtualization operator and ForkliftController on ocp-a | virtualization-config |
| `shift-operator` | primary | NetApp Shift operator 2.0.0 in namespace `shift`: credentials, Shift StorageClass annotations (backend UUID via lookup), filedb and logs PVCs, NetApp bundle (SCC, `shift-toolkit`, `shift-toolkit-listener`, service on 3698/3704), service-CA TLS | mtv-operator, shift-backends |
| `mtv-vmware-source` | primary | Secret `vcenter-credentials` (user/password from hub, CA chain), Provider `vcenter01` (`https://vcenter01.example.com/sdk`), NetworkMap and StorageMap `vcenter01-to-ocp` (Shift, cold: vm\_char\_0–3 → `ontap-nas-vmw-c`, vm\_brav\_0–6 and vm\_log\_0–2 → `ontap-nas-vmw-b`, vm\_alpha\_0–2 → `ontap-nas-vmw-a`). Warm (VDDK): Provider `vcenter01-vddk` (`vddkInitImage` from site values, pinned by digest), StorageMap `vcenter01-vddk-storagemap` (vm\_char\_0–3, vm\_brav\_0–6, vm\_log\_0–2 and vm\_alpha\_0–2 → `ontap-nas`), NetworkMap `vcenter01-vddk-to-ocp`, RoleBinding `system:image-puller` so MTV pods pull the VDDK image | mtv-operator, shift-operator |
| `shift-toolkit-access` | primary | RBAC for the Shift toolkit | mtv-operator |
| `site-primary` / `site-failover` | by role | Role-specific settings | — |

### Policy set `hub-services` (local-cluster = true)

| Policy | What it enforces | Depends on |
| --- | --- | --- |
| `install-secrets` | Pull secret and install secrets for cluster builds | — |
| `mtv-hub-providers` | Per cluster labelled `mtv-provider=enabled`: ManagedServiceAccount `mtv-provider`, token Secret and MTV `Provider` (`ocp-a`, `ocp-b`) in `openshift-mtv` on the hub | — |
| `mtv-hub-maps` | NetworkMaps and StorageMaps `ocp-a-to-ocp-b` and `ocp-b-to-ocp-a` (pod network + 49 NADs; storage → `ontap-nas`, ReadWriteMany, Filesystem), `mustonlyhave` | mtv-hub-providers |
| `mtv-hub-settings` | ForkliftController `feature_ocp_live_migration: "true"`; KubeVirt CA exchange (ServiceAccount, Role, RoleBinding, CronJob `17 */6 * * *` copying each cluster's `kubevirt-ca` into the other's `kubevirt-external-ca`) | — |

### Common policies (`common/`, switched by `config.example.com/*`)

| Policy | Switch | What it enforces |
| --- | --- | --- |
| `common-hub-labels` | local-cluster | Labels on the hub's own ManagedCluster |
| `common-oauth` | htpasswd / ad | OAuth: local break-glass htpasswd admin + Active Directory LDAP |
| `common-ldap-sync` | ad | Group sync CronJob from AD (`DeleteIfCreated`) |
| `common-etcd-encryption` | etcd-encryption | APIServer encryption aescbc |
| `common-ntp` | ntp | Chrony MachineConfig (`clock1-3.example.com`), rolling reboot |
| `common-console` | console | Corp logo, product name, red PRODUCTION banner |
| `common-namespace-template` | namespace-template | Project request template and naming prefix |
| `common-rbac`, `common-argocd-rbac` | rbac | AD groups → cluster roles; Argo CD RBAC |
| `common-ingress-cert` | ingress-cert | Custom wildcard certificate (disabled until the hub secret exists) |
| `common-multipath` | multipath | Disabled: no SAN LUNs |
| `common-lldp` | lldp | LLDP for switch-port discovery |
| `common-metallb-*` | metallb | Disabled until `metallbAddresses` is set |
| `common-alerting` | alerting | Alertmanager e-mail receiver |
| `common-observability` | local-cluster | MultiClusterObservability (Thanos on ONTAP S3) |
| `common-image-registry` | image-registry | Internal registry on `ontap-nas` |
| `common-etcd-backup` | etcd-backup | Daily etcd backup CronJob |
| `common-etcd-defrag` | etcd-defrag (21) | Hubs only: weekly etcd defragmentation when the database is fragmented (single-node clusters are not defragmented by the etcd operator); RCA HUB-16 |
| `common-techpreview-guard` | techpreview-guard | Inform-only: flags any TechPreview feature set |
| `common-routing-via-host` | routing-via-host | OVN `routingViaHost` so pods reach the storage subnet over `bond1` |
| `common-dii-collector` | dii-collector (18) | Read-only ServiceAccount `acq-readonly-cluster-user` for the NetApp Data Infrastructure Insights collector (cluster-reader, cluster-monitoring-view); token created by hand (`docs/dii-collector.md`) |
| `common-mtv-pvc-naming` | mtv-pvc-naming (19) | Every MTV plan in `openshift-mtv` that has not started gets a PVC name template naming disks `<vm>-disk-<n>` (no random suffix); VMware names with dots, capitals or underscores get their host name (`app-vm01.corp.example.com` → `app-vm01-disk-0`). Opt-out: plan annotation `example.com/pvc-names=manual`. On ocp-a, hub-a, hub-b |
| `common-log-forwarding-operator`, `common-log-forwarding` | log-forwarding (20) | OpenShift Logging operator and `ClusterLogForwarder` `collector`: infrastructure + audit logs to Corp syslog (siem-syslog.example.com (10.62.8.57), graylog.example.com, TCP 514, RFC5424) |
| `common-argocd-resources` | local-cluster | Hub Argo CD: application controller 2Gi/6Gi memory; Policy health rule (switched-off policies and report-only policies Healthy) |

## 6. Bringing a cluster under GitOps

> **In plain words:** a new cluster is installed with Red Hat's installer, then it is “introduced” to the hub. As soon as it has the right stickers, the hub sends it every instruction and it sets itself up, in order, with no manual configuration. ocp-b was rebuilt this way from nothing; ocp-a was already running and was brought under the same rules.
>
> **Check it in the console:** *Clusters* → the new cluster shows **Ready** and its add-ons **Available**; *Governance* filtered by that cluster turns from many violations to none over 1–2 hours as the policies finish.

Figure 8 — Onboarding flow, from Assisted Installer to validated cluster.


&#91;image: Onboarding flow\]

### Import a new cluster (how ocp-b was rebuilt)

1. Install with the Assisted Installer on console.redhat.com (static network per node from the blade inventory). Download the admin kubeconfig; on the bastion `chmod 600 ~/ocp-b.kubeconfig` and check `oc --kubeconfig ~/ocp-b.kubeconfig whoami` prints `system:admin`.
2. Create the hub secrets for the cluster (`ontap-credentials-ocp-b` etc.) with `read -s` prompts.
3. Uncomment the cluster in `clusters/kustomization.yaml`, commit, push. Argo CD `clusters` creates the namespace, ManagedCluster and KlusterletAddonConfig.
4. Create the `auto-import-secret` in the cluster's namespace on the hub from the kubeconfig (by hand, never in git). RHACM installs the klusterlet; `oc get managedcluster` shows JOINED and AVAILABLE True.
5. Placements match the labels; policies enforce in dependency order. NTP and PSI MachineConfigs roll the nodes one at a time (about 10–15 min per node).
6. Validate: `oc get policy -n ocp-b` all Compliant; a PVC on `ontap-nas` binds; a test VM on a VLAN NAD gets an address; a live migration between nodes; AD login; the cluster appears in Grafana; the MTV provider is Ready on the hub.

### Adopt an existing cluster (how ocp-a was adopted)

ocp-a was first built by hand (by hand). Adoption (Option B) labelled it into the same policies. Collisions that had to be cleared by hand, once:

| Collision | Fix |
| --- | --- |
| Hub secret `ontap-credentials-ocp-a` missing | Copied from the cluster's existing `trident/ontap-credentials` |
| StorageClass parameters are immutable | Deleted the hand-made StorageClass; the policy recreated it (PVs unaffected) |
| `TooManyOperatorGroups` | Deleted the console-created OperatorGroups; the policy's one remains |
| Manually created objects | Become policy-managed in place (`musthave`); nothing is deleted (`pruneObjectBehavior: None`) |

### Remove or rebuild a cluster

Comment the line in `clusters/kustomization.yaml` and push (nothing happens: prune is off), then detach in the console or sync `clusters` with prune. To rebuild, reinstall and import again: every setting comes back from git; only VMs (data) need restoring.

## 7. Moving VMs between ocp-a and ocp-b (from the hub)

> **In plain words:** a VM can be moved between DC1 and DC2 from the hub with a few clicks. *Cold* moves shut the VM down first; *live* moves keep it running. For live moves the two sites share a private network (VLAN 333) and each server needs its own address on it, so the address list must grow when servers are added.
>
> **Check it in the console:** hub-a → *Migration* → *Providers*: ocp-a and ocp-b **Ready**. *Migration plans* → a plan → *Virtual machines* tab → expand the VM: every step has a green tick (Figure 10). On the target cluster: *Virtualization* → *VirtualMachines* shows the VM **Running** on a node of that cluster (Figure 11).

Figure 9 — Cross-cluster migration: providers, maps and the live-migration path.


&#91;image: Cross-cluster migration\]

Everything is driven from the hub console: *Migrate → Migration plans* (or the VM's *Migrate* action under *Infrastructure → Virtual machines* in the fleet view). The pieces, all from git:

| Piece | Where | From |
| --- | --- | --- |
| `cnv-mtv-integrations` | MultiClusterHub on hub-a | `hub/acm/multiclusterhub.yaml` (false) + JSON patch in `hubs/hub-a/kustomization.yaml` (true) |
| Providers `ocp-a`, `ocp-b` | `openshift-mtv` on the hub | policy `mtv-hub-providers` (ManagedServiceAccount tokens, rotated by RHACM) |
| Cluster-admin for the token | each cluster | policy `mtv-provider-access` |
| Maps both directions | hub | policy `mtv-hub-maps` |
| Live migration feature | ForkliftController on the hub | policy `mtv-hub-settings` |
| Decentralized live migration | HyperConverged | policy `virtualization-config` (GA since 4.21.1) |
| CA trust between clusters | `kubevirt-external-ca` on each cluster | CronJob from `mtv-hub-settings` |
| Shared migration network | `bond3`/`br-lm`, VLAN 333 stretched, 10.60.160.0/25 | policy `migration-network` + site values |

### Cold vs live

|  | Cold | Live |
| --- | --- | --- |
| Downtime | VM is shut down, disks copied, started on target | None: memory and disk copied while running |
| Path | Export/import of the disks over HTTPS | virt-handler to virt-handler over VLAN 333, coordinated by `virt-synchronization-controller` (port 9185, TLS) on both sides |
| Requirements | Providers and maps | Plus: shared L2 network, non-overlapping IP pools, CA trust, same CPU model family |
| Source VM after success | Stays (stopped) unless deleted | Removed from the source |

### Live-migration IP plan (10.60.160.0/25, VLAN 333)

Each cluster's whereabouts pool is the whole /25 minus its `liveMigrationExclude`, so the two pools never overlap. Each node's virt-handler needs one address, plus one per synchronization controller, plus spare.

| Cluster | Usable addresses | Needs (nodes + 2) | Spare |
| --- | --- | --- | --- |
| ocp-a | .10–.25 (16) | 14 | 2 |
| ocp-b | .26–.35 (10) | 8 | 2 |

Adding a node? Free another address from the exclude list first, otherwise the new virt-handler sticks at `Init:0/1` with *subnet address pool exhausted*.

### Running a migration

1. Hub console → *Migrate* → *Create plan* → source provider `ocp-a`, namespace, VM(s) → target provider `ocp-b` → maps `ocp-a-to-ocp-b` → type Cold or Live → target power state *On* → Start.
2. Watch progress in the plan (Initialize, PrepareTarget, Synchronization, Completed) or with `oc --kubeconfig ~/hub-a.kubeconfig -n openshift-mtv get migration,plan`.
3. On the clusters: `oc get vmim -A` shows the source and target VirtualMachineInstanceMigration.

Figure 10 — Live migration plan test1 completed (Initialize, PrepareTarget, Synchronization) in the hub console, 16 Nov.


&#91;image: Live migration plan completed\]

Figure 11 — The migrated VM vm-test01-linux running on the target cluster.


&#91;image: VM running after migration\]

Figure 12 — virt-handler and synchronization-controller addresses on the migration network, both clusters.


&#91;image: Live migration IPs\]

### Operating rules learnt the hard way

- One plan per VM at a time. A cold plan and a live plan on the same VM compete and both fail with *connection reset*.
- After any change to the live-migration network (subnet, excludes, NAD), restart all virt-handlers and both synchronization controllers on **both** clusters: they keep the old address until restarted.
- After a map change, create a fresh plan; existing plans keep the copy of the map they started with.
- Clean up leftover `vmim` objects before retrying (*in-flight migration* errors).
- Every new node needs one more live-migration IP.

## 8. Migrating from VMware: MTV + NetApp Shift

> **In plain words:** VMware VMs are brought over without copying their disks. Because the VMware disks already sit on the NetApp array, the Shift tool asks the array to make an instant copy in place, and OpenShift starts the VM from that copy. A move that would take hours of copying takes minutes.
>
> **Check it in the console:** ocp-a → *Migration* → *Providers*: `vcenter01` **Ready**; *Migration plans* → the wave plan → **Succeeded**; *Virtualization* → *VirtualMachines* → the VM **Running**; *Storage* → *PersistentVolumeClaims* shows its disk on `ontap-nas-vmw-c`.

Figure 13 — Shift path: clone the VMDK in place on SVM_VMW_C instead of copying it.



&#91;image: Shift path\]

&#91;image: Shift flow in the policies\]

MTV on ocp-a with the NetApp Shift operator converts VMs without copying disks: each VMware datastore and the new PVCs live on the same SVM, so Shift asks ONTAP to clone the VMDK file in place (about a minute) and Trident imports it as a PVC on that SVM's Shift class: Charlie `ds_c_0`–`3` (SVM_VMW_C) → `ontap-nas-vmw-c`, Bravo `ds_b_0`–`6` and Log `ds_l_0`–`2` (SVM_VMW_B) → `ontap-nas-vmw-b`, Alpha `ds_a_0`–`2` (SVM_VMW_A) → `ontap-nas-vmw-a` (Bravo and Alpha added 23 Nov; Alpha datastores are 10–11 TB, above NetApp's 5 TB guidance, so test one VM first; warm VDDK works for Alpha too).

| Step | What happens | Defined in |
| --- | --- | --- |
| 1 | MTV plan from provider `vcenter01`, maps `vcenter01-to-ocp`, Cold, target power on | `migration/plan-wave-1.yaml`, policy `mtv-vmware-source` |
| 2 | MTV creates PVCs on the Shift StorageClass; the listener sees them | `shift-operator` (StorageClass annotations, listener) |
| 3 | `shift-toolkit` calls ONTAP to clone the VMDK and Trident imports the volume | `shift-backends`, `shift-credentials` |
| 4 | MTV converts the guest (virt-v2v), creates the VM, boots it | MTV |
| 5 | Post-migration: remove VMware Tools (`scripts/Remove-VMwareTools.ps1.txt` on Windows), clone split, storage live migration to `ontap-nas` on `SVM_OCP_A` so the VM is covered by SVM-DR | by hand per wave |

Shift TLS: the service annotation `service.beta.openshift.io/serving-cert-secret-name: shift-toolkit-tls` makes OpenShift issue the certificate; three ConfigMaps are built from that secret and from `openshift-service-ca.crt`. The policy is split per manifest (`consolidateManifests: false`) because the ConfigMaps wait for a secret that the service annotation creates.

### Warm migration (VDDK)

> **In plain words:** for VMs that cannot be off for long, MTV copies the disks while the VM keeps running in VMware, then stops it only for a final short copy. Tested 18 Nov: 36 GiB copied in about 3 minutes, 3–4 minutes of downtime.

| Item | Where |
| --- | --- |
| Provider `vcenter01-vddk`, VDDK init image | `mtv-vmware-source/provider-vddk.yaml`; image in `policies/site-values/ocp-a.yaml` → `vddkInitImage: …/openshift-mtv/vddk@sha256:a4ab33df…` |
| Storage map (Shift StorageClass cannot do warm) | `storagemap-vddk.yaml`: vm\_char\_0–3, vm\_brav\_0–6, vm\_log\_0–2 and vm\_alpha\_0–2 → `ontap-nas`, ReadWriteMany, Filesystem |
| Network map | `networkmap-vddk.yaml` (same port groups as the Shift map) |
| Image pull permission | `vddk-image-pullers.yaml`: `system:image-puller` for `system:serviceaccounts` in `openshift-mtv` |
| Building a new VDDK image | `scripts/build-vddk-image.sh` with the VDDK tarball from the Broadcom portal (licensed: never in git); it prints the digest to put in `vddkInitImage` |
| Source VM requirement | Changed Block Tracking (CBT) enabled in vSphere |

Choose the provider per plan: `vcenter01` (Shift, cold, clone in place) or `vcenter01-vddk` (warm, copy). Details: `docs/vm-migration-warm-vddk.md`.

### Disk names in ONTAP

Figure 13a — VM standards: how each way of creating a VM sets its ONTAP disk name and its Corp tags.


Trident names each ONTAP volume after the PVC it was asked for: `<cluster>_<namespace>_<pvc>_<suffix>`. Disks filled through a temporary PVC (`prime-<uuid>`) end up as `prime_<uuid>`. Never rename Trident volumes in ONTAP.

| Disk created by | ONTAP volume | Set by |
| --- | --- | --- |
| MTV plan | `ocp_a_<ns>_<vm>_disk_<n>_<suffix>` | switch 19 `common-mtv-pvc-naming` stamps `{{.TargetVmName}}-disk-{{.DiskIndex}}` on each new plan (plan *Details* → *PVC name template*); VMware names with dots, capitals or underscores get their short host name (`app-vm01.corp.example.com` → `app-vm01-disk-0`) |
| VM from a Corp template | `ocp_a_<ns>_<vm>_disk_0_<suffix>` | `vm-templates` (`cdi.kubevirt.io/storage.usePopulator: "false"`) |
| Extra disk | `ocp_a_<ns>_<vm>_disk_<n>_<suffix>` | `scripts/add-vm-disk.sh <vm> <n> <size>` (the console's *Add disk* gives `prime_`) |
| Storage migration, Red Hat template, InstanceTypes page | `prime_<uuid>` | cannot be changed: use `scripts/vm-storage-map.sh` |

Details: `docs/vm-disk-naming.md`.

### After the migration: Corp tags

MTV is never blocked by the tag check, so migrated VMs arrive untagged and appear in `vm-tagging-report`. Tag each wave from the vSphere tag export: `OC="oc $W" scripts/tag-vm.sh --csv wave-N-tags.csv`, or one VM interactively: `OC="oc $W" scripts/tag-vm.sh virtual-machines <vm>`. Details: `docs/vm-tagging.md`.

## 9. Hub services

> **In plain words:** the main control tower copies its memory to the other data centre every 2 hours, and the spare control tower keeps reading those copies so it is always ready to take over. Grafana shows health graphs for both clusters in one place.
>
> **Check it in the console:** hub-a → *Installed Operators* → *OADP Operator* → *Backup* tab: recent backups **Completed**; *BackupStorageLocation* **Available**. *Fleet Management* → *Overview* → *Grafana*: both clusters listed.

### Hub backup and the standby hub

Figure 14 — hub-a backs up to ONTAP S3 at DC2; hub-b restores passively and can take over.


&#91;image: Hub backup and standby\]

- `hubs/hub-a/backup-schedule.yaml`: BackupSchedule every 2 hours via OADP/Velero to bucket `acm-backup-acm` on ONTAP S3 (`svm-ocp-b-s3`). `hub/backup/dpa.yaml` carries the S3 CA (`caCert`, the SVM_OCP_B `SVM_SYSMGR_CA`; each SVM has its own CA of that name).
- `hubs/hub-b/restore.yaml`: passive Restore with sync, so hub-b always holds the latest managed-cluster, policy and credential objects but does not act on them.
- Failover: activate the restore on hub-b, enable its `clusters`/`policies` applications and `cnv-mtv-integrations`; the clusters re-register to hub-b. Thanos secrets are per hub: hub-b keeps its own `thanos-object-storage`.

### Observability

MultiClusterObservability on hub-a (Thanos on ONTAP S3). A cluster appears in Grafana only when its ManagedCluster carries `vendor: OpenShift` (an imported YAML does not get it automatically).

### Hub sizing

`hub/node/kubeletconfig.yaml`: maxPods 500 and auto-sized reserved resources. The single hub node ran out of pod slots (MTV integration pods Pending, *Too many pods*) at the default 250.

## 10. Disaster recovery design

> **In plain words:** if DC1 is lost: the configuration comes back from git, the control tower comes back from its backup at DC2, VM disks are copied to DC2 by the NetApp arrays, and VM definitions are saved by Trident Protect so the VMs can be started again at DC2.
>
> **Check it in the console:** ONTAP System Manager → *Protection* → *Relationships* (storage team); cluster console → *Installed Operators* → Trident Protect present on both clusters; Argo CD tiles `trident-protect-ocp-a` and `trident-protect-ocp-b` green.

| Layer | Mechanism | Status |
| --- | --- | --- |
| Configuration | Git + policies: any cluster rebuilt from git (proven with ocp-b) | Done |
| Hub | OADP backup to DC2 S3, passive restore on hub-b | Done |
| VM data | ONTAP SVM-DR: `SVM_OCP_A → SVM_OCP_A_SM`, `SVM_OCP_B → SVM_OCP_B_SM` (storage team) | Target SVMs created |
| VM definitions | Trident Protect (AppVault on S3) for VM objects and PVC mapping | Installed on both clusters |
| Targets | RTO 4 h Tier 1, 12 h others | Agreed 12 Nov |
| Planned moves | MTV live/cold migration between clusters from the hub | Working both directions |

## 11. Day-2 operations

> **In plain words:** the everyday routine for any change: edit the file, check it builds, save it to git, wait for (or press) Sync in Argo CD, and confirm the policy turns green.
>
> **Check it in the console:** Argo CD → tile → *Sync* (to apply now instead of waiting) → green; *Governance* → the policy → **Compliant** on each cluster; then look at the result on the cluster itself.

Figure 15 — Change workflow: edit, build locally, push, sync, verify.


&#91;image: Change workflow\]

### Bastion setup

Add these four lines to `~/.bashrc` of the account that holds the admin kubeconfigs on the bastion, so every shell has them. Always write `applications.argoproj.io` in `oc` commands for Argo CD apps: on the hub, plain `application` resolves to RHACM's older `applications.app.k8s.io` and fails with *"policies" not found*.

```bash
H="--kubeconfig $HOME/hub-a.kubeconfig"   # main hub
A="--kubeconfig $HOME/hub-b.kubeconfig"   # standby hub
W="--kubeconfig $HOME/ocp-a.kubeconfig"   # DC1 production
C="--kubeconfig $HOME/ocp-b.kubeconfig"   # DC2 production
cd ~/ocp-local/ocp-local && git pull
```

### Making a change

```bash
# 1. edit, then check the YAML parses (the bastion's PolicyGenerator plugin is older than Argo CD's and
#    fails on recordDiff/policySetDefaults, so Argo CD is the real build check: see step 3)
python3 -c "import yaml,sys;[list(yaml.safe_load_all(open(f))) for f in sys.argv[1:]]" policies/policy-generator.yaml && echo OK
# 2. commit and push
git add -A && git commit -m "<what and why>" && git push
# 3. sync now instead of waiting
oc $H -n openshift-gitops patch applications.argoproj.io policies --type merge \
  -p '{"operation":{"sync":{}}}'
# 4. watch the app (Synced/Healthy; a red app shows the generator error) and compliance
oc $H -n openshift-gitops get applications.argoproj.io policies
oc $H get policy -n policies
oc $H get policy -n ocp-b
```

### Common tasks

| Task | How |
| --- | --- |
| Change a per-cluster value | Edit `policies/site-values/<cluster>.yaml`, push |
| Turn a platform feature on/off | Change the `config.example.com/<switch>` label in `clusters/<name>/managedcluster.yaml` |
| Rotate ONTAP / vCenter credentials | Re-create the hub secret with `read -s`; the policy re-templates within minutes |
| Add a VM network | Add the NAD to `vm-networks` and the entry to both MTV network maps |
| Add live-migration IPs | Shrink `liveMigrationExclude` in site values; then restart virt-handlers and sync controllers |
| New Trident Protect version | Change `targetRevision` in `argocd-apps/trident-protect-appset.yaml` |
| Descheduler to Automatic | `deschedulerMode: "Automatic"` in site values |
| Which VMs are missing tags | `OC="oc $W" scripts/tag-vm.sh --list` |
| Tag an existing VM | `OC="oc $W" scripts/tag-vm.sh virtual-machines <vm>` (asks for each tag) |
| Tag a migration wave | `OC="oc $W" scripts/tag-vm.sh --csv wave-N-tags.csv` |
| VM tag check to blocking | `vmTagEnforcement: "Deny"` in site values |
| Add an extra VM disk with a readable name | `OC="oc $W" scripts/add-vm-disk.sh <vm> <n> <size>`, then attach it in the console |
| Which ONTAP volume belongs to which VM | `OC="oc $W" scripts/vm-storage-map.sh` |
| New VDDK image | `scripts/build-vddk-image.sh`, then the printed digest into `vddkInitImage` |

### Useful checks

```bash
oc $H get managedcluster                                  # JOINED / AVAILABLE
oc $H get policy -A | grep -v Compliant                   # anything not compliant
oc $H get policy -n ocp-a <policy> -o jsonpath='{.status.details[*].history[0].message}'
oc $H -n openshift-gitops get applications.argoproj.io                # Synced / Healthy
oc $H -n openshift-mtv get provider,plan,migration        # MTV on the hub
oc $W get vmim -A ; oc $C get vmim -A                     # live migrations
oc $W -n openshift-cnv get pods -o wide | grep -E 'virt-handler|synchron'
oc $W get vm -A -L example.com/environment,example.com/support-level,example.com/dr-tier,example.com/os   # VM tags
oc $W get pv -o custom-columns=PVC:.spec.claimRef.name,ONTAP:.spec.csi.volumeAttributes.internalName  # ONTAP names
oc $H -n openshift-gitops adm top pod openshift-gitops-application-controller-0                # Argo CD memory
```

## 12. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `policies` app fails to build | Generator entry pushed without its manifests folder, or the path in the entry does not match the folder name (`node-maintenance-operator` vs `nodemaintenance-operator`) | Push the folder / fix the path; the app's message names the missing path |
| Policy *template-error*, never compliant | A template waits for an object the same policy creates | `consolidateManifests: false`; or create the prerequisite in an earlier policy |
| Hub backup BSL *Unavailable* | `caCert` missing from the DPA | Restore `caCert` (SVM\_SYSMGR\_CA of SVM_OCP_B) in `hub/backup/dpa.yaml` |
| hub-b Thanos crash-looping | Passive restore brought hub-a's Thanos secret | Give hub-b its own `thanos-object-storage` secret |
| Cluster missing in Grafana | ManagedCluster without `vendor: OpenShift` | Add `vendor`/`cloud` labels in git |
| MTV integration pods Pending | Hub at maxPods 250 | KubeletConfig maxPods 500 |
| `cnv-mtv-integrations` on hub-b | MCH copied the component into spec | Set it explicitly false in `hub/acm/multiclusterhub.yaml` |
| Adoption: StorageClass update refused | StorageClass parameters immutable | Delete and let the policy recreate |
| Adoption: `TooManyOperatorGroups` | Console-created OperatorGroup | Delete the extra OperatorGroup |
| virt-handler `Init:0/1`, *subnet address pool exhausted* | No free live-migration IP for a new node | Free IPs in `liveMigrationExclude` |
| Live migration times out on :9185 | Sync controllers still on old addresses | Restart virt-handlers and sync controllers on both clusters |
| *x509* between clusters | CA not exchanged | Run the CA-exchange CronJob by hand (`oc create job --from=cronjob/…`) |
| PrepareTarget *spec.accessModes required* | Map list merged, second entry lost `accessMode` | `mustonlyhave` on the maps; recreate maps and plan |
| *connection reset* during live migration | Competing plan on the same VM, or a stale virt-handler | One plan per VM; restart the stale virt-handler (or all) |
| Trident Protect stuck on pre-upgrade hook | ServiceAccount missing | `trident-protect-prereqs` policy |
| `applications.app.k8s.io "policies" not found` | `oc … application` resolves to RHACM's resource | Write `applications.argoproj.io` (and `subscriptions.operators.coreos.com`) |
| Argo CD application controller *CrashLoopBackOff*, `OOMKilled` (exit 137) | Large sync at the 2Gi default limit | `common-argocd-resources` (2Gi/6Gi); by hand: `oc $H -n openshift-gitops patch argocd openshift-gitops --type merge -p '{"spec":{"controller":{"resources":{"limits":{"memory":"6Gi"}}}}}'` |
| `common-config` stuck **Progressing** | A policy with no compliance result: placed on no cluster | Health rule in `common-argocd-resources`; if it still shows, the ArgoCD CR has two Policy health rules: remove `/spec/resourceHealthChecks` once |
| `policies` app **Degraded** only because of `vm-tagging-report` | Report is NonCompliant by design | Annotation `example.com/argocd-health: report-only` + health rule |
| Policy *template-error*: `unknown field "spec.recordDiff"` | Managed clusters' ConfigurationPolicy has no `recordDiff` | Leave `recordDiff` out of manifests (set it in the generator only) |
| A field removed in git is still on the cluster | `musthave` never removes | `mustonlyhave` for that policy, or delete the object once and let the policy recreate it |
| Create VirtualMachine wizard stuck at *Customization* | Template parameters `required: true` without a value | Parameters with `value: ''`; check with `oc $W process openshift//<template> -p NAME=x` |
| ONTAP volume called `prime_<uuid>` | Disk filled through a temporary PVC | Corp template, MTV switch 19, `add-vm-disk.sh`; map existing ones with `vm-storage-map.sh` |
| Deleted VM's volume still in ONTAP | The `ontap-nas-vmw-*` Shift classes have reclaim policy Retain | Patch the PV to Delete, then delete it |
| PVC stuck *Terminating* | `kubernetes.io/pvc-protection` finalizer while still in use | Check nothing uses it, then `oc patch pvc <pvc> --type merge -p '{"metadata":{"finalizers":null}}'` (resource type `pvc` is required) |
| Warm plan: *VDDK init image is invalid* / *authentication required* | Bad image or no pull permission | Rebuild with `build-vddk-image.sh`; `vddk-image-pullers` RoleBinding |
| Plan *Not Ready* / *VM PVC name template is invalid* | VMware name with capitals or dots (`app-vm01.corp.example.com`): the disk name is checked as a label | Switch 19 writes the host name into the template for those VMs; wait 15 s after adding VMs and refresh the plan |
| Plan *VMStorageNotMapped* | The VM's datastore is not in the plan's storage map (23 Nov: Bravo `ds_b_*` in the VDDK map) | Add the datastore to `storagemap.yaml` (Shift) or `storagemap-vddk.yaml` (warm) in git |
| Shift backend `ontap-nas-vmw-*` *Failed* | `trident_admin` missing on that SVM or without `ontapi`, hub secret `ontap-credentials-<svm>` missing, or 443 to the management LIF blocked | `security login show -vserver <SVM>`; create the hub secret before pushing; curl the LIF from a node (`docs/shift-operator.md`) |

## 13. Worked examples: adding and changing things

Each example lists **what changes in git**, **what is done by hand once** (never secrets in git), **what happens automatically**, and **how to verify**. Values in `[brackets]` are placeholders to fill from the host sheet or the storage team. All commands run on the bastion with the `$H $A $W $C` variables from section 11.

| Example | Git files touched | By hand |
| --- | --- | --- |
| 13.1 Add a node to a production cluster | `policies/site-values/<cluster>.yaml`, `policies/manifests/storage-network/<cluster>.yaml` | UCS service profile, DNS, Add hosts, CSR approval, pod restarts |
| 13.2 Add a VM network (VLAN) | `vm-networks/vm-networks.yaml`, `mtv-hub-maps/maps.yaml`, `mtv-vmware-source/networkmap.yaml` | Switch / UCS VLAN trunking |
| 13.3 Add an operator | new `manifests/<op>-operator/`, `<op>-config/`, entries in `policy-generator.yaml` | — |
| 13.4 Add a vCenter as an MTV source | new `manifests/mtv-vmware-source-<vc>/`, generator entry, site values | Hub secret with the vCenter login |
| 13.5 Add a storage backend / StorageClass | `trident-config` or a new policy, `virtualization-config/storageprofile.yaml`, MTV storage maps | Hub secret, SVM + export policy (storage team) |
| 13.6 Turn a platform feature on | label in `clusters/<name>/managedcluster.yaml` (+ site value) | Hub secret if the feature needs one |
| 13.7 Change a per-cluster setting | `policies/site-values/<cluster>.yaml` | — |
| 13.8 Rotate a credential | none | Re-create the hub secret |
| 13.9 Add an AD group with access | `common/manifests/rbac/rbac.yaml` | AD group exists |
| 13.10 Add a third production cluster | `clusters/<new>/`, `clusters/kustomization.yaml`, site values, storage-network file, maps | Install, hub secrets, auto-import-secret |
| 13.11 Run a VMware migration wave | `migration/plan-wave-N.yaml` (record) | Plan started from the console |
| 13.12 Upgrade OpenShift | `clusters/<name>/clustercurator-upgrade.yaml` (optional) | Change window |
| 13.13 Create a VM from the Corp template | none | Tag values on the wizard's Customization step |
| 13.14 Add an extra disk to a VM | none | `scripts/add-vm-disk.sh`, attach in the console |
| 13.15 Tag existing or migrated VMs | none | `scripts/tag-vm.sh` (interactive or CSV) |
| 13.16 Add a Corp template for another OS | `policies/manifests/vm-templates/corp-<os>-<flavor>.yaml` | Clone the Red Hat template once to export it |
| 13.17 Change the tag rules or move to blocking | `vm-tagging/vm-tagging.yaml`, `vm-tagging-report`, `scripts/tag-vm.sh`, site values | — |

### 13.1 Add a node to a production cluster

> **In plain words:** a new server needs two lines added to the blueprint (its storage address, and one more address on the VM-moving network), then it is installed with Red Hat's installer. Everything else (networks, time servers, the VM software) is set up on it automatically.
>
> **Check it in the console (cluster console):** *Compute* → *Nodes*: new node **Ready** → *Compute* → *MachineConfigPools*: worker **Updated** → *Networking* → *NodeNetworkConfigurationPolicy*: `storage-ocp-b-wn04` **Available** → *Workloads* → *Pods*, project `openshift-cnv`, filter `virt-handler`: one **Running** on the new node → *Virtualization* → a VM → *Actions* → *Migrate* to the new node succeeds. Hub: *Governance* still no violations.

Example: worker `ocp-b-wn04` joins ocp-b. The same steps apply to ocp-a with its own files.

**Before the node exists (once, outside git)**

1. UCS: service profile from the 8-vNIC OpenShift template (ens5f0–ens5f7: management A/B, VM A/B, live migration A/B, storage A/B), same VLANs as the other blades.
2. IP plan from the host sheet: management IP + DNS A/PTR `ocp-b-wn04.ocp-b.example.com`, storage IP on 10.60.140.0/24 (`[172.18.140.__]`), a free live-migration address on 10.60.160.0/25.
3. Storage: the SVM export policy must allow the new storage IP. `SVM_OCP_B` / `SVM_OCP_A` `default` export rules allow 10.60.140.0/24, so no change is needed unless the rule was narrowed.

**Step 1 — give the cluster one more live-migration IP (git)**

Every node runs a virt-handler that takes one address from the whereabouts pool. ocp-b today has 10 usable addresses (.26–.35) for 6 nodes + 2 sync controllers + 2 spare. Get the next address reserved in IPAM first (e.g. `.36`), then remove it from `liveMigrationExclude`:

```diff
# policies/site-values/ocp-b.yaml
-  liveMigrationExclude: "10.60.160.0/28,10.60.160.16/29,10.60.160.24/31,10.60.160.36/30,10.60.160.40/29,10.60.160.48/28,10.60.160.64/26"
+  liveMigrationExclude: "10.60.160.0/28,10.60.160.16/29,10.60.160.24/31,10.60.160.37/32,10.60.160.38/31,10.60.160.40/29,10.60.160.48/28,10.60.160.64/26"
```

Check the address is not in ocp-a's pool (it must stay excluded there). The two pools must never overlap.

**Step 2 — add the node's storage network (git)**

Copy the last block in `policies/manifests/storage-network/ocp-b.yaml` and change three things: the policy name, the hostname and the storage IP.

```yaml
---
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: storage-ocp-b-wn04                                   # 1
spec:
  nodeSelector:
    kubernetes.io/hostname: ocp-b-wn04.ocp-b.example.com   # 2 = oc get nodes
  desiredState:
    interfaces:
      - name: bond1
        type: bond
        state: up
        mtu: 1500
        ipv4: { enabled: false }
        ipv6: { enabled: false }
        link-aggregation:
          mode: active-backup
          options: { miimon: "100" }
          port: [ens5f6, ens5f7]
      - name: br-storage
        type: ovs-bridge
        state: up
        bridge:
          allow-extra-patch-ports: true
          options: { stp: false }
          port:
            - name: bond1
            - name: nfs222
              vlan: { mode: access, tag: 222 }
      - name: nfs222
        type: ovs-interface
        state: up
        mtu: 1500
        ipv4:
          enabled: true
          dhcp: false
          address: [{ ip: "[172.18.140.__]", prefix-length: 24 }]   # 3
        ipv6: { enabled: false }
    ovn:
      bridge-mappings:
        - localnet: storage-trunk
          bridge: br-storage
          state: present
```

An NNCP whose hostname matches no node does nothing, so this can be pushed before the node joins. Build, commit, push (section 11).

**Step 3 — install the node (by hand)**

1. console.redhat.com → *Clusters* → `ocp-b` → *Add hosts* → static network configuration for `bond0` (same YAML pattern as the original install, the new management IP) → *Generate Discovery ISO*.
2. Boot the blade from the ISO through UCS vKVM. When the host shows *Ready*, set its hostname and click *Install ready hosts*.
3. Approve the certificate requests (twice: client, then serving):

```bash
oc $C get csr | grep Pending
oc $C get csr -o name | xargs oc $C adm certificate approve
oc $C get nodes -w        # ocp-b-wn04 Ready
```

**Step 4 — what happens automatically**

| Applied by | What the new node gets |
| --- | --- |
| `node-network` (worker selector) | `bond2` → `br-vm`, VM VLANs available |
| `migration-network` | `bond3` → `br-lm` (VLAN 333) |
| `storage-network` (step 2) | `bond1` → `br-storage`, storage IP |
| MachineConfigs (`common-ntp`, `descheduler-operator` psi) | Chrony and PSI; the node reboots once as it joins the worker pool |
| DaemonSets | virt-handler, Trident node plugin, NMState handler, observability, LLDP |

**Step 5 — restart the migration pods and verify**

The new pool only takes effect after a restart (operating rule, section 7). Do it on both clusters when nothing is migrating:

```bash
for K in "$W" "$C"; do
  oc $K -n openshift-cnv delete pod -l kubevirt.io=virt-handler
  oc $K -n openshift-cnv delete pod -l app=virt-synchronization-controller   # check the label: oc $K -n openshift-cnv get pods --show-labels | grep synchron
done
oc $C get nncp | grep wn04                        # Available
oc $C get mcp worker                              # UPDATED True
oc $C -n openshift-cnv get pods -o wide | grep wn04   # virt-handler Running
oc $C get node ocp-b-wn04 -o jsonpath='{.status.allocatable.devices\.kubevirt\.io/kvm}'
```

Then live-migrate a test VM onto the node (`virtctl migrate`, or cordon the others) and run a cross-cluster live migration. Finally record the blade in the host sheet and `docs/images/corp-blade-inventory.png`.

**Removing a node** is the reverse: drain (`oc adm drain --ignore-daemonsets --delete-emptydir-data`), `oc delete node`, delete its NNCP block in git, and put its live-migration address back into the exclude list only after the virt-handler is gone.

### 13.2 Add a VM network (VLAN)

> **In plain words:** a new VLAN is like adding a new socket on the wall: the network team wires it, git describes it once so both clusters get it, and the migration “translation table” is updated so VMs on that VLAN land on the same VLAN at the other side.
>
> **Check it in the console:** cluster console → *Networking* → *NetworkAttachmentDefinitions*, project `default`: the new network listed on both clusters; hub → *Migration* → *NetworkMaps* → `ocp-a-to-ocp-b`: the new pair listed; *Virtualization* → a test VM → *Configuration* → *Network* → add a NIC on it → the VM gets an address.

Example: new VLAN 412, subnet 10.65.30.0/24, port group in VMware `vm-vlan101`. Using the same name everywhere keeps MTV maps 1:1.

1. Network team: trunk VLAN 412 to the VM vNICs (VM\_Uplink\_FI-A/B) on every blade at both sites.
2. `policies/manifests/vm-networks/vm-networks.yaml` — add a NAD (both clusters get it):

```yaml
---
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: vm-vlan101
  namespace: default
spec:
  config: '{"cniVersion":"0.4.0","name":"vm-vlan101","type":"ovn-k8s-cni-overlay","topology":"localnet","physicalNetworkName":"vm-trunk","netAttachDefName":"default/vm-vlan101","vlanID":412,"mtu":1500}'
```

3. `policies/manifests/mtv-hub-maps/maps.yaml` — add the pair to **both** NetworkMaps (`ocp-a-to-ocp-b` and `ocp-b-to-ocp-a`):

```yaml
    - source: { name: vm-vlan101, namespace: default, type: multus }
      destination: { name: vm-vlan101, namespace: default, type: multus }
```

4. If VMs on that port group will come from VMware, add it to `mtv-vmware-source/networkmap.yaml` (source = the vCenter port group name, destination = the NAD), and to `migration/vmware-port-groups.csv`.
5. Push. Verify: `oc $W get net-attach-def -n default | grep vlan412`; start a test VM with that NIC and ping the gateway. Existing migration plans keep their old map copy: create new plans.

### 13.3 Add an operator

> **In plain words:** instead of clicking *Install* in OperatorHub on each cluster, the install is written once in git: one file says “install this add-on”, a second says “and set it up like this”, and the second waits for the first.
>
> **Check it in the console:** hub → *Governance* → `nhc-operator` and `nhc-config` **Compliant**; cluster console → *Installed Operators* → the operator **Succeeded**; click it to see the configured resources. Do **not** install it from OperatorHub by hand as well (two installs conflict).

Pattern: one policy installs the operator, a second configures it and depends on the first. Example: Node Health Check operator on both production clusters.

1. `policies/manifests/nhc-operator/operator.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-workload-availability
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: workload-availability
  namespace: openshift-workload-availability
spec: {}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: node-healthcheck-operator
  namespace: openshift-workload-availability
spec:
  channel: stable                  # check: oc $W get packagemanifest node-healthcheck-operator -o jsonpath='{.status.defaultChannel}'
  name: node-healthcheck-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```

2. `policies/manifests/nhc-config/` — the operator's custom resources (e.g. a `NodeHealthCheck`). Use `{{hub fromConfigMap ... hub}}` for anything that differs per cluster and add the key to both site-values files.
3. `policies/policy-generator.yaml`:

```yaml
  - name: nhc-operator
    policySets: [prod-virtualization]          # env=prod: both clusters
    manifests:
      - path: manifests/nhc-operator/
  - name: nhc-config
    policySets: [prod-virtualization]
    dependencies:
      - name: nhc-operator
    manifests:
      - path: manifests/nhc-config/
```

Placement choices: no `placement` = both clusters; `dr-role In [primary]` = ocp-a only (like MTV); a new `config.example.com/<switch>` label in `common/` = per-cluster opt-in.

4. Local build, push, verify:

```bash
oc $H get policy -n policies | grep nhc
oc $W get csv -n openshift-workload-availability     # Succeeded
```

Rules: only one OperatorGroup per namespace (a console-created one gives `TooManyOperatorGroups`); a CR whose CRD is not there yet fails until the operator policy is Compliant — that is what `dependencies` are for; if one manifest's template needs an object another manifest creates, add `consolidateManifests: false`.

### 13.4 Add a vCenter as an MTV source

> **In plain words:** to migrate from another vCenter, the migration tool needs its address, a login (kept as a secret on the hub), its certificate so the connection can be trusted, and translation tables saying which VMware network and datastore go where.
>
> **Check it in the console:** ocp-a → *Migration* → *Providers*: the new provider **Ready** and its VM count shown; click it → *Virtual machines* tab lists the vCenter's VMs; *NetworkMaps* / *StorageMaps*: the new maps with no warnings.

Example: a second vCenter `[vcenter02.example.com]` on ocp-a, datastores on a different SVM.

1. Hub secret with the login (never in git):

```bash
read -p "vCenter user: " VCU; read -s -p "vCenter password: " VCP; echo
oc $H -n policies create secret generic vcenter-vc02-credentials-ocp-a \
  --from-literal=user="$VCU" --from-literal=password="$VCP"
oc $H -n policies label secret vcenter-vc02-credentials-ocp-a cluster.open-cluster-management.io/backup=""
unset VCU VCP
```

2. The vCenter CA chain, saved in `migration/vc02-chain.pem`:

```bash
openssl s_client -connect [vcenter02.example.com]:443 -showcerts </dev/null 2>/dev/null \
  | awk '/BEGIN CERT/,/END CERT/' > migration/vc02-chain.pem
base64 -w0 migration/vc02-chain.pem     # goes into cacert below
```

3. Site value: `vcenterFQDN2: "[vcenter02.example.com]"` in `policies/site-values/ocp-a.yaml`.
4. Copy `policies/manifests/mtv-vmware-source/` to `mtv-vmware-source-vc02/` and change: secret name `vcenter-vc02-credentials`, hub secret name `vcenter-vc02-credentials-%s`, `cacert`, Provider name `ocp-a-vc02`, URL key `vcenterFQDN2`, map names `ocp-a-vc02-to-ocp`, map sources (that vCenter's port groups and datastores).
5. Storage map destination: if the new datastores are on an SVM ocp-a already has a Shift backend for, use that StorageClass; otherwise either add a Shift backend for that SVM (13.5) or map to `ontap-nas` (MTV then copies the disks instead of cloning — slower but no new backend).
6. Generator entry, a copy of `mtv-vmware-source` with the new path and the same dependencies. Push.
7. Verify: `oc $W -n openshift-mtv get provider ocp-a-vc02` shows Ready; the inventory lists VMs in the console under *Migration → Providers*.

### 13.5 Add a storage backend or StorageClass

> **In plain words:** a new storage area on the NetApp arrays is connected by giving Trident its address and a login, and creating a “storage class” — the name users pick when they ask for a disk.
>
> **Check it in the console:** cluster console → *Storage* → *StorageClasses*: the new class listed; create a test PVC on it (*Storage* → *PersistentVolumeClaims* → *Create*) → **Bound**; ONTAP System Manager shows a new volume named `trident_pvc_...`.

Example: a new SVM `[NEWSVM]` for a tier of VMs on ocp-a.

1. Storage team: SVM, data LIFs on 10.60.140.0/24, export policy for 10.60.140.0/24, a vsadmin-type account for Trident.
2. Hub secret `ontap-credentials-newsvm` (username/password) via `read -s`.
3. Site values: management LIF, data LIF, aggregate, SVM name.
4. New folder (e.g. `trident-newsvm/`): backend Secret from `{{hub fromSecret ...}}`, `TridentBackendConfig`, `StorageClass` (immutable once created — get the parameters right first), and a StorageProfile entry in `virtualization-config/storageprofile.yaml` (RWX, Filesystem, csi-clone). Generator entry depending on `trident-config`.
5. If VMs on it must move between clusters, add it to the StorageMaps in `mtv-hub-maps`; if it is a Shift source, add the Shift annotations as in `shift-operator/10-storageclass-shift.yaml`.
6. Verify: `oc $W -n trident get tbc` Bound/Success; a test PVC binds; a VM boots from it.

### 13.6 Turn a platform feature on for a cluster

> **In plain words:** many platform features are switches. Flip the sticker on the cluster from *disabled* to *enabled* in git and the matching policy starts applying to that cluster.
>
> **Check it in the console:** hub → *Clusters* → ocp-b → *Labels* shows `config.example.com/ingress-cert=enabled`; *Governance* → `common-ingress-cert` now lists ocp-b as **Compliant**; open the ocp-b console in a browser and check the certificate (padlock) shows the Corp certificate.

Example: the custom ingress certificate on ocp-b.

```bash
oc $H -n policies create secret tls ocp-b-ingress-cert --cert=ocp-b-wildcard.crt --key=ocp-b-wildcard.key
oc $H -n policies label secret ocp-b-ingress-cert cluster.open-cluster-management.io/backup=""
```

Then in `clusters/ocp-b/managedcluster.yaml` change `config.example.com/ingress-cert: disabled` to `enabled` and push. The `common-ingress-cert` policy now matches ocp-b. MetalLB is the same: set `metallbAddresses` in site values first, then the label. Turning a label back to `disabled` stops enforcement but leaves the objects (prune is None).

### 13.7 Change a per-cluster setting

> **In plain words:** each cluster has a settings sheet in git. Change a value there and the policies that use it update the cluster.
>
> **Check it in the console:** hub → project `policies` → *Workloads* → *ConfigMaps* → `<cluster>-site-values` shows the new value; the related policy is **Compliant**; the effect is visible on the cluster (e.g. the banner text at the top of the console).

| Change | Edit in `policies/site-values/<cluster>.yaml` | Note |
| --- | --- | --- |
| Descheduler from log-only to rebalancing | `deschedulerMode: "Automatic"` | Start with one cluster; watch VM moves |
| Console banner text or colour | `bannerText`, `bannerBackground` | Cosmetic, immediate |
| Alert sender | `alertEmailFrom` |  |
| ONTAP data LIF moved | `ontapDataLIF` / `ontapDataLIF2` | New PVCs only; existing mounts keep the old IP until remount |

Hub templates are re-resolved when the policy is re-evaluated (about every 10 minutes); to force it now:

```bash
oc $H -n policies annotate policy <policy> policy.open-cluster-management.io/trigger-update="$(date +%s)" --overwrite
```

### 13.8 Rotate a credential

> **In plain words:** when a password changes, only the copy on the hub is updated. The policies pass the new password to the clusters; git is not touched.
>
> **Check it in the console:** hub → project `policies` → *Secrets* → the secret's *Created / Updated* time is new; the policy using it is **Compliant**; on ocp-a *Installed Operators* → Trident → *TridentBackendConfig* status **Success** (for ONTAP), or *Migration* → *Providers* **Ready** (for vCenter).

No git change. Recreate the hub secret with the same name and keys, then trigger an update of the policies that read it:

```bash
read -s -p "New ONTAP password: " P; echo
oc $H -n policies create secret generic ontap-credentials-ocp-a \
  --from-literal=username=[user] --from-literal=password="$P" --dry-run=client -o yaml | oc $H apply -f -
unset P
oc $H -n policies annotate policy trident-config policy.open-cluster-management.io/trigger-update="$(date +%s)" --overwrite
oc $W -n trident get tbc     # phase Bound, status Success
```

Same pattern for `shift-credentials-ocp-a` (policy `shift-operator`), `vcenter-credentials-ocp-a` (policy `mtv-vmware-source`) and the LDAP bind secret (policy `common-ldap-sync`).

### 13.9 Give an AD group access

> **In plain words:** access is given to Active Directory groups, not individual people. Add the group to the RBAC file and anyone in that AD group gets the access on both clusters.
>
> **Check it in the console:** cluster console → *User Management* → *Groups*: the AD group appears with its members after the next sync; *RoleBindings*: the new binding; log in as a member to confirm.

Add a binding in `common/manifests/rbac/rbac.yaml` (e.g. group `[CORP-OCP-VM-Operators]` → ClusterRole `kubevirt.io:edit` in the VM namespaces, or `view` cluster-wide). The group must exist in AD and be inside the LDAP sync filter in `common/values.yaml`; check with `oc $W get groups`.

### 13.10 Add a third production cluster

> **In plain words:** a third cluster is set up exactly like ocp-b was: install it, copy ocp-b's folder and settings sheet and change the values, then introduce it to the hub.
>
> **Check it in the console:** as in section 6: *Clusters* → **Ready**; *Governance* → no violations for it; *Migration* → *Providers* → a new provider **Ready**.

1. Install with the Assisted Installer; admin kubeconfig to the bastion.
2. `clusters/<new>/` — copy `ocp-b/`, change names and labels (`dr-role`, `site`), keep `vendor`/`cloud`.
3. `policies/site-values/<new>.yaml` — copy and change every value, including a **non-overlapping** `liveMigrationExclude` (shrink the others' pools if needed).
4. `policies/manifests/storage-network/<new>.yaml` — one NNCP per node.
5. Hub secrets `ontap-credentials-<new>` etc.
6. MTV maps for the new pairs in `mtv-hub-maps` (`<new>-to-ocp-a`, ...).
7. Add the line to `clusters/kustomization.yaml`, push, create the `auto-import-secret`. Follow the import validation in section 6.

### 13.11 Run a VMware migration wave

> **In plain words:** a wave is a group of VMware VMs moved together during an agreed window. The plan lists the VMs; the migration tool does the rest and starts them on OpenShift.
>
> **Check it in the console:** ocp-a → *Migration* → *Migration plans* → the plan → **Succeeded**; *Virtualization* → *VirtualMachines* → each VM **Running**, *Console* tab shows the login screen, *Network* shows its IP; vCenter shows the source VM powered off.

1. Copy `migration/plan-wave-1.yaml` to `plan-wave-N.yaml`, list the VMs. Cold with Shift: provider `vcenter01`, maps `vcenter01-to-ocp`. Warm: provider `vcenter01-vddk`, maps `vcenter01-vddk-storagemap` / `vcenter01-vddk-to-ocp`, `warm: true`. `targetPowerState: on`.
2. Pre-checks per VM: disks on a mapped datastore (Shift: `ds_c_*`, `ds_b_*`, `ds_l_*`, `ds_a_*`; warm: all of these too), no snapshots, network adapters on mapped port groups, Windows guests have the VirtIO drivers path covered by MTV; for warm, CBT enabled.
3. Create the plan from the console (or `oc $W apply -f` the file). Before *Start*, open the plan's *Details*: *PVC name template* shows `{{.TargetVmName}}-disk-{{.DiskIndex}}` (switch 19 fills it within about 15 seconds). VMware names with dots, capitals or underscores get their host name in the template automatically (`app-vm01.corp.example.com` → `app-vm01-disk-0`). Start it, watch *Migration progress*.
4. Tag the wave: `OC="oc $W" scripts/tag-vm.sh --csv wave-N-tags.csv` (13.15).
5. After the VM is validated: run `scripts/Remove-VMwareTools.ps1.txt` (rename to `.ps1`) on Windows; for Shift VMs, clone split and storage live migration to `ontap-nas` so SVM-DR covers it (warm VMs are already on `ontap-nas`).

### 13.12 Upgrade OpenShift

> **In plain words:** upgrade the backup site first, check it, then the main site. VMs move off each server automatically while it is updated, so they keep running.
>
> **Check it in the console:** cluster console → *Administration* → *Cluster Settings*: progress bar, then the new version; *Compute* → *MachineConfigPools*: all **Updated**; *Virtualization* → *VirtualMachines*: all **Running**. Hub → *Clusters* shows the new version.

1. Check the channel and the target version is supported by the installed OpenShift Virtualization, MTV, Trident and Shift versions.
2. Upgrade ocp-b first (failover) and validate, then ocp-a. Either from the cluster console, or from the hub with `clusters/<name>/clustercurator-upgrade.yaml.example` (rename, set `desiredUpdate`, push).
3. VMs live-migrate off each node as it drains (OpenShift Virtualization `workloadUpdateStrategy`); confirm with `oc $C get vmim -A` and `oc $C get mcp`.

### 13.13 Create a VM from the Corp template

> **In plain words:** the Corp template builds the VM with a disk named after it and with every Corp tag ready to fill in. Fill the tags in before clicking Create.
>
> **Check it in the console:** the VM appears with no yellow *Admission Webhook Warning*; *Configuration* → *Storage* shows the disk `<vm>-disk-0`; *Governance* → `vm-tagging-report` does not list it.

1. ocp-a console → *Virtualization* → *VirtualMachines* → *Create* → *From template* → **Corp RHEL 9 VM (small)**.
2. Name, project (`virtual-machines`), then *Customization* → *Metadata* (or the *YAML* tab): fill the labels `example.com/environment` (sbx/dev/tst/prd), `example.com/support-level` (24x7/9x5/Unmanaged), `example.com/dr-tier` (1/2/3) and the seven `example.com/*` annotations. `example.com/os` is already `Linux`.
3. Create. A missing or wrong value gives a warning (Warn) or a refusal (Deny) naming the tag.
4. Verify:

```bash
oc $W -n virtual-machines get vm <vm> -L example.com/environment,example.com/support-level,example.com/dr-tier,example.com/os
oc $W get pv -o custom-columns=PVC:.spec.claimRef.name,ONTAP:.spec.csi.volumeAttributes.internalName | grep <vm>
# expect <vm>-disk-0   ocp_a_virtual_machines_<vm>_disk_0_<suffix>
```

Use the Template catalog, not the *InstanceTypes* page, for production VMs: that page builds its own disk (`prime_` name) and adds no tag keys.

### 13.14 Add an extra disk to a VM

> **In plain words:** a disk added from the console gets a meaningless name in NetApp. Create it with the script so the storage team sees which VM it belongs to, then attach it.
>
> **Check it in the console:** VM → *Configuration* → *Storage* lists `<vm>-disk-<n>`; ONTAP System Manager → *Volumes* → search `<vm>_disk_<n>`.

```bash
OC="oc $W" scripts/add-vm-disk.sh <vm> 1 50Gi        # namespace virtual-machines, ontap-nas by default
```

Then VM → *Configuration* → *Storage* → *Add* → use an existing PVC → `<vm>-disk-1`, interface virtio; restart the VM if it is running. Number extra disks from 1 (disk-0 is the root disk).

### 13.15 Tag existing or migrated VMs

> **In plain words:** VMs brought in by MTV, or created before the tag rules, need their tags added afterwards. The script asks for each one and checks the values.
>
> **Check it in the console:** *Governance* → *Policies* → `vm-tagging-report` → *Results*: the VM disappears from the list within a minute.

```bash
OC="oc $W" scripts/tag-vm.sh --list                           # list only: every VM missing tags, and which tags
OC="oc $W" scripts/tag-vm.sh                                  # same list, numbered: pick one, answer, repeat; Enter quits
OC="oc $W" scripts/tag-vm.sh virtual-machines <vm>             # asks for each tag of this VM
OC="oc $W" scripts/tag-vm.sh --csv wave-N-tags.csv             # a wave, from the vSphere tag export
```

The CSV header: `namespace,vm,Environment,SupportLevel,DRTier,OS,Application,ChargingAccount,CreatedBy,OwnerDepartment,OwnerDepartmentContact,SupportDepartment,SupportDepartmentContact`. Use the OpenShift VM name (lower case). Tagging never restarts the VM. A single tag can also be edited on the VM's *Details* → *Labels* / *Annotations* in the console, but the script is the only path that checks the values.

### 13.16 Add a Corp template for another OS

1. Console → *Virtualization* → *Templates* → the Red Hat template (e.g. `windows2k22-server-medium`) → *Actions* → *Clone* → `corp-<os>-<flavor>` in project `openshift`; export its YAML, then delete the clone (git owns the real one).
2. In the YAML: DataVolume name `'${NAME}-disk-0'` with annotation `cdi.kubevirt.io/storage.usePopulator: 'false'`; the `rootdisk` volume pointing to `'${NAME}-disk-0'`; the `example.com/*` labels and annotations and the ten tag parameters from `corp-rhel9-server-small.yaml` (parameters with `value: ''`, never `required: true`); `example.com/os` fixed to the OS; `openshift.io/display-name: Corp …`.
3. Remove `uid`, `resourceVersion`, `creationTimestamp`, `managedFields`, the `app.kubernetes.io/*` labels and `operator-sdk/*` annotations (otherwise the SSP operator treats it as its own).
4. Save as `policies/manifests/vm-templates/corp-<os>-<flavor>.yaml`, push, sync `policies`.
5. Verify: `oc $W process openshift//corp-<os>-<flavor> -p NAME=x | head -3` prints JSON (no *is required*); create a test VM (13.13).

### 13.17 Change the tag rules or move to blocking

- **Move to blocking** when the Corp templates are in use and the report lists no VMs created by people: `vmTagEnforcement: "Deny"` in `policies/site-values/ocp-a.yaml` and `ocp-b.yaml`, push, sync. Check: `oc $W get validatingadmissionpolicybinding vm-tags -o jsonpath='{.spec.validationActions}'` → `["Deny","Audit"]`. Back to `Warn` the same way.
- **A new allowed value** (environment, support level, DR tier): validations 2–4 in `policies/manifests/vm-tagging/vm-tagging.yaml`, `check()` in `scripts/tag-vm.sh`, the parameter descriptions in the Corp templates.
- **A new required tag**: `missingLabels` / `missingAnnotations` in the admission policy, `$reqL` / `$reqA` in `vm-tagging-report`, `KEY` and `ORDER` in `scripts/tag-vm.sh`, a parameter and a `example.com/*` line in each Corp template.
- **Exempt a namespace** (tests): `oc $W label namespace <ns> example.com/vm-tags=exempt`.

## 14. Troubleshooting playbook: simple to advanced

> **In plain words:** follow the change down the chain and find where it stopped: did git get it → did Argo CD take it → did the hub turn it into a policy → did the cluster apply it. The first red item in that chain is where the problem is.

### Troubleshooting by clicking (no command line)

| Step | Where | Good | If not |
| --- | --- | --- | --- |
| 1. Is the change in git? | github.com → *Commits* | Your commit is on `main` | Push it |
| 2. Did Argo CD take it? | Argo CD → tile (`policies`, `clusters`, `hub-config`…) | **Synced** + **Healthy** | Click the tile → red object or the message at the top (usually a typo in the YAML); fix in git |
| 3. Is the policy compliant? | *Fleet Management* → *Governance* → *Policies* → the policy → *Results* | **Compliant** on each cluster | Read the message: it names the object and what is wrong (missing secret, waiting for another policy, field cannot be changed) |
| 4. Is the cluster healthy? | *Clusters* → the cluster | **Ready** | Cluster console → *Home* → *Overview* → alerts |
| 5. Did the thing appear on the cluster? | Cluster console, where the thing lives | Present and healthy | *Events* tab of the object, or the operator's page in *Installed Operators* |
| 6. Migration failed? | *Migration* → *Migration plans* → plan → *Virtual machines* → expand the VM | All steps green | The first red step and its message: see the table in Level 2 *MTV migrations* |
| 7. VM not starting? | *Virtualization* → VM → *Events* and *Diagnostics* | No warnings | Disk (PVC not **Bound**), network (NAD missing), node (not enough memory) |

Screenshots of real failures and their fixes are in the appendix (Figures 16 and 17).

Work top-down: **is the commit in Argo CD → is the policy generated → is it compliant → what does the cluster say**. Most problems are found in the first two levels.

### Level 1 — quick checks (5 minutes)

| Question | Command | Healthy answer |
| --- | --- | --- |
| Are the clusters connected? | `oc $H get managedcluster` | JOINED True, AVAILABLE True |
| Did Argo CD take my commit? | `oc $H -n openshift-gitops get applications.argoproj.io` | Synced, Healthy; revision = your commit |
| Did the generator build? | `oc $H -n openshift-gitops get applications.argoproj.io policies -o jsonpath='{.status.conditions}'` | empty |
| Is anything not compliant? | `oc $H get policy -A \| grep -v Compliant` | only headers |
| Why is a policy NonCompliant? | `oc $H get policy -n ocp-b policies.<policy> -o jsonpath='{range .status.details[*]}{.templateMeta.name}{": "}{.history[0].message}{"\n"}{end}'` | the message names the object and the field |
| Is a policy waiting on another? | same command | *Pending: dependencies not satisfied* — fix the dependency first |
| Is a node or MachineConfigPool stuck? | `oc $C get nodes; oc $C get mcp` | all Ready; UPDATED True |
| Are the networks applied? | `oc $C get nncp` | every policy Available |
| Storage OK? | `oc $C -n trident get tbc; oc $C get pvc -A \| grep -v Bound` | Bound/Success; no Pending PVCs |
| MTV OK? | `oc $H -n openshift-mtv get provider` | every provider Ready |

Common level-1 fixes:

| Message | Meaning | Fix |
| --- | --- | --- |
| Argo CD *ComparisonError* / kustomize error | YAML or generator error in the commit | Run the local build, fix, push |
| Policy *template-error* `secret not found` | Hub secret missing or misspelled | Create it in `policies` on the hub |
| Policy *violation: ... not found* for a CR | Operator not installed yet | Wait for, or add, the dependency |
| *field is immutable* | Object created by hand with other values (StorageClass, Service selector) | Delete the object; the policy recreates it |
| `TooManyOperatorGroups` | Extra OperatorGroup created from the console | Delete the extra one |
| ManagedCluster *Unknown* | Klusterlet lost the hub (network, expired import) | `oc $C -n open-cluster-management-agent get pods`; re-create the auto-import-secret |

### Level 2 — component checks (30 minutes)

**Policy engine on the cluster** — the controller that enforces policies logs every create/update and every error:

```bash
oc $C -n open-cluster-management-agent-addon logs deploy/config-policy-controller --since=30m | grep -i -E 'error|<policy>'
```

Hub template errors (`{{hub ... hub}}`) show on the hub's root policy, managed-cluster template errors in the replicated policy. Force a fresh evaluation with the `trigger-update` annotation (13.7).

**Networking (NMState)** — a failed NNCP is rolled back automatically, so the node stays reachable; the reason is on the enactment:

```bash
oc $C get nnce | grep -v Available
oc $C get nnce ocp-b-wn04.storage-ocp-b-wn04 -o jsonpath='{.status.conditions[?(@.type=="Failing")].message}'
```

Typical causes: wrong interface name (check `oc $C get nns <node> -o yaml`), hostname not equal to the node name, VLAN not trunked.

**Storage (Trident)**

```bash
oc $C -n trident get tbc -o wide
oc $C -n trident logs deploy/trident-controller -c trident-main --since=30m | grep -i error
oc $C describe pvc <pvc> -n <ns>        # events: provisioning errors from ONTAP
```

Permission denied on mount = export policy; *no such host / timeout* = management LIF or route via `bond1` (routing-via-host).

**Virtualization**

```bash
oc $C get hco -n openshift-cnv kubevirt-hyperconverged -o jsonpath='{.status.conditions}' | jq
oc $C get vmi -A -o wide
oc $C describe vmi <vm> -n <ns>          # scheduling, network attach errors
oc $C -n openshift-cnv get pods | grep -v Running
```

**MTV migrations**

```bash
oc $H -n openshift-mtv get plan,migration                   # cluster-to-cluster plans live on the hub
oc $H -n openshift-mtv get plan <plan> -o jsonpath='{.status.conditions}' | jq
oc $H -n openshift-mtv logs deploy/forklift-controller -c main --since=30m | grep -i -E 'error|<vm>'
oc $W -n openshift-mtv get plan,migration                   # VMware plans live on ocp-a
```

The failing pipeline step tells where to look: *Initialize* = provider or map; *PrepareTarget* = target namespace, NAD, StorageClass, accessMode; *Synchronization* (live) = migration network, CA, virt-handler; *DiskTransfer* (cold) = storage, export pod.

**Hub backup**

```bash
oc $H -n open-cluster-management-backup get backupstoragelocation,backupschedule
oc $H -n open-cluster-management-backup get backup --sort-by=.metadata.creationTimestamp | tail -5
oc $A -n open-cluster-management-backup get restore -o jsonpath='{.items[*].status}'
```

BSL *Unavailable* = S3 endpoint, credentials or CA (`caCert` in `dpa.yaml`).

### Level 3 — advanced, live migration between clusters

The live path has the most moving parts. Check them in this order:

1. **One plan per VM, nothing left over.** Cancel and delete competing plans; delete stale migration objects on both sides:

```bash
oc $W get vmim -A; oc $C get vmim -A
oc $W -n <ns> delete vmim <name>        # only ones that are Failed or orphaned
```

2. **Every virt-handler and sync controller has a migration address**, and they are the current ones:

```bash
for K in "$C" "$W"; do
  for p in $(oc $K -n openshift-cnv get pods -o name | grep -E 'virt-handler|virt-synchronization'); do
    echo "$p $(oc $K -n openshift-cnv get $p -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' | jq -r '.[] | select(.name|test("live-migration")) | .ips[]')"
  done
done
```

A pod with no address = pool exhausted (13.1 step 1). Addresses changed after a site-values edit = restart both clusters' virt-handlers and sync controllers.

3. **Stale whereabouts reservations** — if a pool looks full but fewer pods exist, compare reservations to running pods:

```bash
oc $C get ippools.whereabouts.cni.cncf.io -n openshift-multus -o yaml | grep -c podref
oc $C get overlappingrangeipreservations.whereabouts.cni.cncf.io -n openshift-multus
```

Delete only reservations whose pod no longer exists; the whereabouts reconciler normally does this itself.

4. **Reachability on VLAN 333** between a source and target virt-handler (port 9185 for the sync controllers; migration traffic on the virt-handler addresses):

```bash
oc $W -n openshift-cnv debug pod/<virt-handler-pod> --image=registry.redhat.io/openshift4/ose-cli-rhel9:v4.22 -- \
  bash -c 'timeout 3 bash -c "</dev/tcp/<c1-sync-controller-ip>/9185" && echo open || echo closed'
```

5. **CA trust** — *x509: certificate signed by unknown authority* in the virt-handler or sync-controller logs:

```bash
oc $W -n openshift-cnv get cm kubevirt-external-ca -o jsonpath='{.metadata.annotations}'
oc $H -n openshift-mtv create job ca-sync-now --from=cronjob/kubevirt-ca-exchange   # namespace as in mtv-hub-settings
```

6. **Logs on both ends at the same moment:**

```bash
oc $W -n openshift-cnv logs <virt-handler on source node> --since=10m | grep -i migrat
oc $C -n openshift-cnv logs <virt-handler on target node> --since=10m | grep -i migrat
oc $C -n openshift-cnv logs deploy/virt-synchronization-controller --since=10m
```

*connection reset* on one node only = restart that node's virt-handler; on every node = restart all, both clusters.

### Level 3 — advanced, other areas

| Situation | Approach |
| --- | --- |
| A policy keeps flipping Compliant / NonCompliant | Two writers fight over one object (another policy, an operator, a hand edit). Find the field in the policy message; give one owner; use `mustonlyhave` only where the policy must own the whole object |
| MachineConfigPool Degraded | `oc $C get mcp worker -o yaml` → the node and reason; `oc $C -n openshift-machine-config-operator logs <mcd pod on node> -c machine-config-daemon` |
| Shift migration stalls at disk creation | `oc $W -n shift logs deploy/shift-toolkit-listener`, `deploy/shift-toolkit`; check `shift-toolkit-tls` exists and the StorageClass annotations carry the right backend UUID (`oc $W -n trident get tbc ontap-nas-vmw-c -o jsonpath='{.status.backendInfo.backendUUID}'`, same for `-vmw-b` and `-vmw-a`) |
| Trident Protect app OutOfSync / hook stuck | `oc $C -n trident-protect get jobs,pods`; the hook job's events; `trident-protect-prereqs` Compliant; then sync the app in Argo CD |
| Standby hub shows errors after a restore | Restored objects that must differ per hub (Thanos secret, MCH components): keep them out of the backup or set them explicitly in `hubs/hub-b` |
| A VM is refused or warned about at creation | The message names the missing tags or the wrong value (`example.com/environment must be one of sbx, dev, tst, prd (got prod)`). Check the binding mode: `oc $W get validatingadmissionpolicybinding vm-tags -o jsonpath='{.spec.validationActions}'`. MTV is never blocked; if a migration is, its service account changed: compare `request.userInfo.username` in the API audit log with the exemptions in `vm-tagging.yaml` |
| `vm-tagging-report` lists a VM that looks tagged | A key misspelt or a value empty: list exactly what is missing with the `jq` command in `docs/vm-tagging.md` (*Checking*) |
| Which VM owns an ONTAP volume | `OC="oc $W" scripts/vm-storage-map.sh`; for `prime_<8 hex>…`: `oc $W get pvc -A -o custom-columns=NS:.metadata.namespace,PVC:.metadata.name,UID:.metadata.uid \| grep -i <8 hex>` (CDI names the temporary PVC after the final PVC's UID) |
| Red Hat support case | `oc $C adm must-gather` plus `--image=registry.redhat.io/container-native-virtualization/cnv-must-gather-rhel9:v4.22` for Virtualization, and the MTV must-gather image for migrations; for policies, the hub must-gather `registry.redhat.io/rhacm2/acm-must-gather-rhel9` |

## 15. Open items

- SVM-DR / SnapMirror relationships with Trident Protect: NetApp session on 11/30; then Trident Protect AppVaults and schedules.
- NetApp DII collector registration: waiting on the firewall rule from NetApp to the cluster APIs (port 6443), then recreate the token.
- Corp templates for the other operating systems in use (Windows, RHEL 8) — 13.16.
- VM tag enforcement from `Warn` to `Deny` once the templates are in regular use — 13.17.
- VDDK image location: a Corp internal registry (survives cluster rebuilds, usable from ocp-b) instead of ocp-a's internal registry.
- Shift test clones left on `SVM_VMW_C` (reclaim policy Retain): patch the PVs to Delete and remove them.
- Ingress certificates and MetalLB addresses (labels disabled until values exist).

## Appendix: screenshots

Figure 16 — New virt-handler stuck in Init: *subnet address pool exhausted* (fixed by freeing live-migration IPs).


&#91;image: Address pool exhausted\]

Figure 17 — *Migration failed: the selected node is unavailable* — the stale virt-handler on ocp-b-wn03, fixed by restarting virt-handlers and sync controllers.


&#91;image: Migration failed, node unavailable\]
