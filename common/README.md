# common: day-2 configuration for the hubs and the production clusters

The same ACM policies configure all four clusters (`hub-a`, `hub-b`, `ocp-a`, `ocp-b`). Each feature is switched on per cluster with a label, `config.example.com/<feature>: enabled`. Any other value (for example `disabled`) skips it.

The `common-config` Argo CD Application syncs this folder on both hubs. On `hub-a` it reaches `hub-a` itself and both production clusters. On `hub-b` it reaches only `hub-b`, until a takeover.

## Features and switches

| # | Label `config.example.com/…` | Policy | What it does | Needs first |
|---|---|---|---|---|
| 1 | `htpasswd` | `common-oauth` | Local `htpasswd` identity provider. Its user (`htpasswdAdminUser`) is cluster-admin and in the `break-glass` group | Hub secret `htpasswd` |
| 2 | `ad` | `common-oauth`, `common-ldap-sync` | Active Directory login (`corp-ad` LDAP provider) and a CronJob that syncs the listed AD groups every 30 minutes | LDAP values in `values.yaml` (set for `corp.example.com`); hub secret `ldap-bind`; ConfigMap `ldap-ca` only for LDAPS |
| 3 | `etcd-encryption` | `common-etcd-encryption` | AES-GCM encryption of etcd | — |
| 4 | `ntp` | `common-ntp` | Chrony on every node pointing at `clock1`–`clock3.example.com` (MachineConfig, rolling reboot) | — |
| 5 | `console` | `common-console` | Masthead logo, product name, and the identity banner from site values | Corp logo in `manifests/console/logo.svg` |
| 6 | `namespace-template` | `common-namespace-template` | Project request template, and an admission policy requiring `namespacePrefix` on namespaces created by people | Prefix in `values.yaml` |
| 7 | `rbac` | `common-rbac`, `common-argocd-rbac` | AD groups bound to cluster-admin, cluster-reader and VM admin; the break-glass group; on the hubs, the same groups as Argo CD admin and read-only (`readOnlyForAllUsers` sets the Argo CD default to read-only) | Group names in `values.yaml` |
| 8 | `ingress-cert` | `common-ingress-cert` | Corp certificate for `*.apps` on the default IngressController | Hub secret `<cluster>-ingress-cert` |
| 9 | `multipath` | `common-multipath` | `/etc/multipath.conf` and `multipathd` on worker and control plane nodes (MachineConfig, rolling reboot) | — |
| 9 | `lldp` | `common-lldp` | LLDP on every vNIC of nodes with the worker role (NNCP, no reboot) | NIC names confirmed |
| 10 | `metallb` | `common-metallb-operator`, `common-metallb-config` | MetalLB operator, a layer 2 address pool and its advertisement | `metallbAddresses` in site values |
| 11 | `alerting` | `common-alerting` | Alertmanager e-mails critical alerts to `alertEmailTo` through the SMTP relay. Warning, info and Watchdog alerts are not sent. The configuration is `alerting/alertmanager.yaml`; console edits are overwritten | SMTP values in `values.yaml`; `alertEmailFrom` and `alertClusterName` in site values; hub secret `alertmanager-smtp` only if the relay needs a login |
| 12 | `observability` | `common-observability` | **Hubs only.** RHACM MultiClusterObservability: metrics from the clusters the hub manages, and from itself, into Thanos with long-term storage in ONTAP S3. The operator ships with RHACM and the namespace is always created (`hub/`) | S3 bucket; secrets `thanos-object-storage` and `multiclusterhub-operator-pull-secret` in `open-cluster-management-observability` on that hub; `ontap-nas` |
| 13 | `image-registry` | `common-image-registry` | The internal image registry switched to `Managed` on a ReadWriteMany `ontap-nas` claim `image-registry-storage` (bare metal installs it `Removed`) | `imageRegistrySize` in `values.yaml`; `ontap-nas` |
| 14 | `etcd-backup` | `common-etcd-backup` | Namespace `etcd-backup` with a privileged CronJob that runs `/usr/local/bin/cluster-backup.sh` on a control plane node and copies the snapshot to an `ontap-nas` claim, keeping the newest `etcdBackupRetain`. Deliberately not the built-in automated backup, which is Technology Preview and needs `TechPreviewNoUpgrade` | `etcdBackupSchedule`, `etcdBackupRetain` in `values.yaml`; `ontap-nas` |
| 15 | `techpreview-guard` | `common-techpreview-guard` | **Inform only, changes nothing.** NonCompliant if the cluster `FeatureGate` sets `TechPreviewNoUpgrade`, `DevPreviewNoUpgrade` or `CustomNoUpgrade` (these cannot be reverted and block upgrades) | none |
| 16 | `routing-via-host` | `common-routing-via-host` | OVN-Kubernetes `routingViaHost: true` and `ipForwarding: Global`: pod egress follows the host routing table, so pods reach ONTAP S3 on the storage LIFs over `bond1.222` (a routed path is asymmetric because the SVMs default-route out of their management network). Restarts the ovnkube pods once | `bond1` storage network on the node |
| 17 | `mtv-provider` | `mtv-provider-access` (in `policies/`) and `mtv-hub-providers` on the hub | Registers the cluster as an MTV provider on the hub (ManagedServiceAccount, cluster-admin binding) so VMs can move between clusters | MTV on the hub |
| 18 | `dii-collector` | `common-dii-collector` | Read-only ServiceAccount `acq-readonly-cluster-user` in `default` (cluster-reader, cluster-monitoring-view) for the NetApp Data Infrastructure Insights collector; the token is created by hand (`docs/dii-collector.md`). On ocp-a and ocp-b, not the hubs | Firewall from NetApp to the cluster API (6443) |
| 19 | `mtv-pvc-naming` | `common-mtv-pvc-naming` | Every MTV plan in `openshift-mtv` that has not started and has no PVC name template gets `{{.TargetVmName}}-disk-{{.DiskIndex}}` without a random suffix, so the disk PVC is `<vm>-disk-<n>` and Trident names the ONTAP volume `<cluster>_<namespace>_<vm>_disk_<n>`. A template typed on the plan's Details tab wins; started plans are never changed. On ocp-a and both hubs | MTV installed |
| 20 | `log-forwarding` | `common-log-forwarding-operator`, `common-log-forwarding` | Red Hat OpenShift Logging operator (default channel) in `openshift-logging` and a `ClusterLogForwarder` `collector`: infrastructure and audit logs to siem-syslog.example.com (10.62.8.57) and graylog.example.com over TCP 514, RFC5424, with APP-NAME `ocp-<cluster>-<type>-<source>` (e.g. `ocp-ocp-a-infra-container`, `ocp-hub-a-audit-kubeAPI`; cluster from `alertClusterName` in the site values). Service account `logcollector` with `collect-infrastructure-logs` and `collect-audit-logs`. No log store on the cluster | Firewall: every node to both servers on TCP 514 |
| 21 | `etcd-defrag` | `common-etcd-defrag` | **Single-node hubs only.** Namespace `etcd-defrag` with a privileged CronJob that defragments etcd when the database file is at least 100 MiB and under 55% in use (the etcd operator's own thresholds; the alert `etcdDatabaseHighFragmentationRatio` fires under 50%). It runs `etcdctl` inside the etcd pod through `crictl`, refuses to run on a cluster with more than one etcd member (the etcd operator defragments those itself), and clears a `NOSPACE` alarm afterwards. The API pauses for a few seconds during a defragmentation | `etcdDefragSchedule` in `values.yaml` (after the daily backup, switch 14) |

## Where the switches are

| Cluster | File | Form |
|---|---|---|
| `ocp-a`, `ocp-b` | `clusters/<cluster>/managedcluster.yaml` (live) and `clusterinstance.yaml` `extraLabels` (for a rebuild from git): keep both the same | `config.example.com/ntp: enabled` |
| `hub-a`, `hub-b` | `hubs/<hub>/local-cluster-labels.yaml` | `ntp: enabled` (the `common-hub-labels` policy adds the `config.example.com/` prefix and puts the labels on the hub's own ManagedCluster) |

As set on 24 Nov:

| Switches | ocp-a | ocp-b | hub-a, hub-b |
|---|---|---|---|
| 1-7 (htpasswd, ad, etcd-encryption, ntp, console, namespace-template, rbac), 9 lldp, 11 alerting, 13-16, 20 log-forwarding | enabled | enabled | enabled |
| 8 ingress-cert, 9 multipath, 10 metallb | disabled | disabled | disabled |
| 12 observability | – | – | enabled |
| 17 mtv-provider, 18 dii-collector | enabled | enabled | – |
| 19 mtv-pvc-naming | enabled | disabled (no MTV) | enabled |
| 21 etcd-defrag | – (three control plane nodes: the etcd operator defragments) | – | enabled |

The ingress certificate and MetalLB stay off until their values and secrets exist; multipath is off because there are no SAN LUNs.

Change a switch in git and merge. The policies follow on the next evaluation. If a change to the OAuth providers does not appear within a few minutes, force a re-evaluation from the hub:

```
oc -n policies annotate policy common-oauth policy.open-cluster-management.io/trigger-update="$(date +%s)" --overwrite
```

## Values

| Values | File |
|---|---|
| Same on every cluster: product name, htpasswd user, LDAP server, bind DN, base DNs, synced groups, RBAC group names, namespace prefix | `common/values.yaml` |
| Per production cluster: banner text and colours, MetalLB range, `alertClusterName` (alert e-mails and the syslog prefix `ocp-<cluster>-…`) | `policies/site-values/<cluster>.yaml` |
| Per hub: banner text and colours, MetalLB range, `alertClusterName` | `hubs/<hub>/site-values.yaml` (named `local-cluster-site-values`) |

## Secrets (never in git)

Create these by hand on **each** hub, in the `policies` namespace, before switching the feature on. `common/hub-secrets.yaml.example` has the shapes and the commands.

| Secret or ConfigMap | Used by |
|---|---|
| `htpasswd` (key `htpasswd`) | 1 |
| `ldap-bind` (key `bindPassword`), ConfigMap `ldap-ca` (key `ca.crt`) | 2 |
| `ocp-a-ingress-cert`, `ocp-b-ingress-cert`, `local-cluster-ingress-cert` (type `kubernetes.io/tls`) | 8 |
| `alertmanager-smtp` (key `password`), only when `alertSmtpAuthUser` is set | 11 |

## Switching a feature off

- **Removed again:** `ad` (the LDAP provider leaves the OAuth list, and the sync CronJob and its namespace are deleted), `htpasswd` (the provider leaves the OAuth list while AD stays on), `metallb` (its MetalLB, pool and advertisement are deleted; the operator stays), `etcd-defrag` (the CronJob and its namespace are deleted).
- **Left as last applied:** `log-forwarding` (the operator and the `ClusterLogForwarder` stay: delete `clusterlogforwarder collector` in `openshift-logging` to stop forwarding), etcd encryption (set `type: identity` in git first to decrypt), NTP and multipath MachineConfigs, console branding, the namespace template, RBAC, the ingress certificate and LLDP. Delete the object by hand after switching off, or remove it from the manifest first and switch off after it has synced.
- Switching off both `htpasswd` and `ad` leaves the identity providers as they were. `kubeadmin` keeps working throughout.

## Checks

```
oc -n policies get policy | grep common-                      # on the hub: Compliant where enabled
oc get managedcluster -L config.example.com/ad,config.example.com/metallb
oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}{"\n"}'          # on a cluster
oc -n ldap-sync get cronjob,jobs
oc get mcp                                                                          # after ntp or multipath: UPDATED True
oc -n openshift-logging get clusterlogforwarder collector -o jsonpath='{.status.conditions}'   # switch 20: Ready
oc -n openshift-logging get ds collector                                            # one collector pod per node
oc -n openshift-monitoring get secret alertmanager-main -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d   # alerting
oc get nns <node> -o jsonpath='{.status.currentState.interfaces[?(@.name=="ens5f0")].lldp}{"\n"}'
```

### Checks for 13, 14, 15 and 21

```
oc get config.imageregistry.operator.openshift.io cluster -o jsonpath='{.spec.managementState} {.spec.storage.pvc.claim}{"\n"}'   # Managed image-registry-storage
oc get pvc -n openshift-image-registry; oc get pods -n openshift-image-registry | grep image-registry
oc get cronjob -n etcd-backup
oc create job etcd-backup-now --from=cronjob/etcd-backup -n etcd-backup     # first run by hand
oc logs -f job/etcd-backup-now -n etcd-backup                               # "etcd backup ... done" and the kept list
oc get cronjob -n etcd-defrag                                                # 21, hubs only
oc create job etcd-defrag-now --from=cronjob/etcd-defrag -n etcd-defrag     # run now; defragments only above the threshold
oc logs -f job/etcd-defrag-now -n etcd-defrag                               # "before: database … MiB, in use … MiB (…%)" then "done" or "below the threshold"
oc get featuregate cluster -o jsonpath='{.spec.featureSet}{"\n"}'          # empty = default feature set
oc -n policies get policy common-techpreview-guard                          # on the hub: Compliant
```
