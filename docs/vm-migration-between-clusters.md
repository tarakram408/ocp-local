# Migrating VMs between ocp-a and ocp-b from the hub

Set up and tested 11 Nov 2026. VMs move between the two production clusters with MTV running on the active hub
`hub-a`: Migration for Virtualization > Migration plans > Create plan. Cold migrations: the VM is stopped, its disks are
copied over the network into `ontap-nas` on the target, and the VM is created there with the same MAC (and therefore
the same DHCP address) and the same VLAN.

## What provides it

| Piece | Where | How |
|---|---|---|
| MTV on the hub | `hub-a` only | MultiClusterHub component `cnv-mtv-integrations` (`hub/acm/multiclusterhub.yaml`: `false`; `hubs/hub-a/kustomization.yaml` patch: `true`). It also installs OpenShift Virtualization on the hub (already present on `hub-a`). |
| Provider per cluster | hub | Policy `mtv-hub-providers`: for every ManagedCluster labelled `config.example.com/mtv-provider: enabled`, a ManagedServiceAccount `mtv-provider` (rotating token), a Secret `openshift-mtv/<cluster>-mtv-provider` (token + CA, copied on the hub; nothing in git) and a Provider `openshift-mtv/<cluster>` (API URL from the ManagedCluster) |
| Access on each cluster | ocp-a, ocp-b | Policy `mtv-provider-access`: ClusterRoleBinding `mtv-provider-cluster-admin` for `open-cluster-management-agent-addon/mtv-provider`. Removing this policy revokes the hub's migration access. |
| Maps | hub | Policy `mtv-hub-maps`: NetworkMaps and StorageMaps `ocp-a-to-ocp-b` and `ocp-b-to-ocp-a`. Network: pod network + the 49 VM networks, each to the NAD of the same name. Storage: `ontap-nas` and `ontap-nas-vmw-c` to `ontap-nas`. Regenerate when a NAD is added to `policies/manifests/vm-networks/`. |

## Decisions

- **The clusters are not labelled `acm/cnv-operator-install`.** That label is ACM's opt-in for its integration, but it
  also makes ACM install OpenShift Virtualization on the cluster through the `kubevirt-hyperconverged` add-on, whose
  template carries its own HyperConverged CR. ACM and the `virtualization-config` policy would overwrite each other and
  the live migration settings (network `live-migration`, 800 s/GiB, limits 5/2) would fall back to defaults. The
  providers are registered by our own policies instead, with a label of our own.
- **`config.example.com/mtv-provider`, not `env=prod`.** `ocp-a` is configured by hand and is not labelled `env=prod`; the
  label opts in exactly the two clusters. On `ocp-a` it is set by hand until `clusters/ocp-a` is enabled:
  `oc label managedcluster ocp-a config.example.com/mtv-provider=enabled`.
- **`hub-b` keeps the component off** (standby; MTV and OpenShift Virtualization would sit idle on a single node). The
  MultiClusterHub operator copies every component into `spec.overrides.components`, so the component is set to `false`
  explicitly; leaving it out of git does not turn it off. On a hub failover, enable it there (`hub/backup/README.md`).
  It was briefly on for hub-b on 11 Nov; the OpenShift Virtualization and MTV operators it left behind were removed
  by hand on 12 Nov (`hub/backup/README.md`, Leftovers on hub-b).
- **Hub pod limit 500** (`hub/node/kubeletconfig.yaml`, with the auto-sized memory reservation). With MTV added, the
  single-node hub reached the default 250 pods: `0/1 nodes are available: 1 Too many pods`.

## Checks

```
oc --kubeconfig ~/hub-a.kubeconfig get managedcluster -L config.example.com/mtv-provider     # enabled on both
oc --kubeconfig ~/hub-a.kubeconfig get managedserviceaccount -A | grep mtv-provider        # ocp-b, ocp-a
oc --kubeconfig ~/hub-a.kubeconfig get provider,networkmap,storagemap -n openshift-mtv     # host, ocp-b, ocp-a Ready; 4 maps Ready
oc --kubeconfig ~/hub-a.kubeconfig get policy -A | grep -E "mtv-hub|mtv-provider"          # Compliant
```

## Running a migration

1. `hub-a` console > Migration for Virtualization > Migration plans > Create plan. Plan project `openshift-mtv`, source
   provider `ocp-a`, target provider `ocp-b`, target project (must exist on the target, e.g. `virtual-machines`).
2. Pick the VMs. Network map and storage map: *Use an existing map* > `ocp-a-to-ocp-b` (MTV makes a copy owned by the plan).
3. Migration type **Cold**. Other settings: transfer network *Target provider default*; **VM target power state: Power on**
   ("Retain source VM power state" records the state after MTV's own shutdown, so the VM arrives stopped).
4. Create the plan, wait for Ready, Start. Pipeline: Initialize, DiskTransfer, VirtualMachineCreation.
5. Check on the target: VM Running, same IP, gateway and DNS reachable.
6. MTV never deletes the source VM. It stays stopped on the source cluster; delete it after validation and never start
   both (same MAC and IP).

Test on 11 Nov: `testvm` (RHEL 9.8, one 32 GB disk, VLAN 3051) from `ocp-a` to `ocp-b` in about 2 minutes; same MAC
`02:00:00:00:00:4d`, same address `10.60.60.146/22`, running on `ocp-b-cp03`.

## Live migration between the clusters

Generally available since OpenShift Virtualization 4.21.1 (Technology Preview in 4.20). Set up 12 Nov:

- Both clusters' live migration NADs on the shared `10.60.160.0/25` (site values `liveMigrationSubnets`), each
  excluding all but its own addresses. Since 17 Nov, from the block Corp reserved in IPAM (.10-.35): ocp-a .10-.25
  (16), ocp-b .26-.35 (10): nodes + 2 synchronization controllers + 2 spare each. After changing the ranges, restart all
  virt-handlers and synchronization controllers on both clusters at once (they keep their old address until restarted).
- VLAN 333 is stretched DC1-DC2: `migration0` of a ocp-a virt-handler (.104) and of a ocp-b one (.28) reach each other
  directly (TTL 64, about 1 ms). Test from the node, in the virt-handler's network namespace (the image has no ping):
  `crictl inspect` for the PID, then `nsenter -t <pid> -n ping -I migration0 <other cluster's address>`.
- Feature gate `decentralizedLiveMigration: true` in the HyperConverged (`virtualization-config` policy): starts
  `virt-synchronization-controller` in `openshift-cnv` on both clusters.
- `feature_ocp_live_migration: "true"` in the hub's ForkliftController (`openshift-mtv` on hub-a), set by the hub
  policy `mtv-hub-settings` (`policies/manifests/mtv-hub-settings/`).
- **Mutual trust of the KubeVirt CAs.** Each cluster's synchronization controller and virt-handlers use certificates from
  their own cluster's CA (`openshift-cnv/kubevirt-ca`). Each cluster's bundle is copied into the other's
  `openshift-cnv/kubevirt-external-ca`; KubeVirt merges it into `kubevirt-ca` and empties `kubevirt-external-ca` again.
  The CA rotates every couple of days, so the hub CronJob `openshift-mtv/kubevirt-ca-exchange` (policy
  `mtv-hub-settings`) repeats the copy every 6 hours, using the `<cluster>-mtv-provider` tokens (no credentials in git).
  By hand:
  ```
  oc --kubeconfig ~/ocp-a.kubeconfig get cm kubevirt-ca -n openshift-cnv -o jsonpath='{.data.ca-bundle}' > wc.pem
  oc --kubeconfig ~/ocp-b.kubeconfig get cm kubevirt-ca -n openshift-cnv -o jsonpath='{.data.ca-bundle}' > c1.pem
  oc --kubeconfig ~/ocp-a.kubeconfig create cm kubevirt-external-ca -n openshift-cnv --from-file=ca-bundle=c1.pem --dry-run=client -o yaml | oc --kubeconfig ~/ocp-a.kubeconfig apply -f -
  oc --kubeconfig ~/ocp-b.kubeconfig create cm kubevirt-external-ca -n openshift-cnv --from-file=ca-bundle=wc.pem --dry-run=client -o yaml | oc --kubeconfig ~/ocp-b.kubeconfig apply -f -
  ```
- Plans choose **Live** as the migration type (pipeline Initialize, PrepareTarget, Synchronization).
- Both clusters' hosts are `Cascadelake-Server` (label `host-model-cpu.node.kubevirt.io/…`), so any VM can move either way.

First successful live migration: 13 Nov, `livetest2` ocp-a → ocp-b, about one minute, VM kept running.

### Troubleshooting (13 Nov)

| Symptom | Cause | Fix |
|---|---|---|
| PrepareTarget fails: "Resource ref.Ref{ID:"", Name: …} not found" | VM not running on the source, or the hub's inventory not yet updated | Use a VM that runs on the source; wait a minute after creating it |
| Target VM stays `WaitingForReceiver`; source `vmim` Synchronizing; sync controller log `dial tcp 172.18.160.x:9185: i/o timeout` | `virt-synchronization-controller` pods still had the old live migration network mask (only virt-handler had been restarted after the subnet change) | Restart virt-handler **and** virt-synchronization-controller on both clusters after any change to the live migration network |
| Synchronization fails: "in-flight migration detected. Active migration job … already in progress" | A `vmim` of an earlier attempt still open on the source | Failed or stuck attempts are not retried: delete the `vmim` on both clusters, the receiver VM on the target and the plan, then start a new plan |
| Synchronization fails: "Migration failed, check VMIM status"; target launcher "No command socket found" / source domain "ShuttingDown" | Attempt run against a VM that had restarted during earlier clean-ups | Clean up both sides and retry with a VM that has not been restarted (a fresh VM is simplest) |
| `x509` / `unknown authority` in the sync controller or virt-handler logs | CA trust missing or expired | Run the CronJob now (`oc create job -n openshift-mtv --from=cronjob/kubevirt-ca-exchange kubevirt-ca-exchange-manual`) |

Checks: `oc get kubevirt -n openshift-cnv -o jsonpath='{.items[0].status.synchronizationAddresses}'` (each cluster's
controller address on VLAN 333, port 9185); from a node, in a virt-handler's network namespace:
`nsenter -t <pid> -n timeout 5 bash -c "</dev/tcp/<other address>/9185"`. Progress: `oc get vmim -n <ns>` on both
clusters; metrics `kubevirt_vmi_migration_data_processed_bytes` / `_remaining_bytes` in the source console.
