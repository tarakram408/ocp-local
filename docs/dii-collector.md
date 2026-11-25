# NetApp Data Infrastructure Insights (DII): OpenShift Virtualization collector

DII's OpenShift Virtualization collector discovers the VMs on a cluster (not all pods) through the cluster API
(HTTPS, port 6443) with a read-only service account token. NetApp recommends one collector per cluster.
Source: https://docs.netapp.com/us-en/data-infrastructure-insights/task_dc_redhat_openshift_virtualization.html

## What git provides

Policy `common-dii-collector` (`common/manifests/dii-collector/`), switched on per cluster by the label
`config.example.com/dii-collector: enabled` (set on ocp-a and ocp-b in `clusters/<name>/managedcluster.yaml`):

| Object | Name (as in NetApp's steps) |
|---|---|
| ServiceAccount, namespace `default` | `acq-readonly-cluster-user` |
| ClusterRoleBinding to `cluster-reader` | `acq-readonly-cluster-user-binding` |
| ClusterRoleBinding to `cluster-monitoring-view` | `acq-readonly-cluster-monitor-user-binding` |

## By hand, per cluster (the token is a secret: never in git)

```bash
oc $W create token acq-readonly-cluster-user -n default --duration=8760h     # ocp-a: paste into DII, do not save it
oc $C create token acq-readonly-cluster-user -n default --duration=8760h     # ocp-b
oc $W cluster-info | head -1        # API endpoint for the ocp-a collector
oc $C cluster-info | head -1        # ocp-b
```

In DII, add one **Red Hat OpenShift Virtualization** collector per cluster: the API host name from `oc cluster-info`,
HTTPS port 6443 (default), and the token. NetApp's form shows user name and password fields; confirm with NetApp
which field takes the token. Inventory poll interval defaults to 20 minutes.

## Renewal

The token expires after one year (`--duration=8760h`); DII then reports **"Failed to connect"**. Put a reminder
about 11 months after creation, run the same `oc create token` command and update the collector.
The cluster may cap token lifetimes below a year; check the `exp` of the token if DII stops earlier.

## Check

```bash
oc $H get policy -A | grep dii-collector                                        # Compliant on ocp-a and ocp-b
oc $W auth can-i list virtualmachines.kubevirt.io -A --as=system:serviceaccount:default:acq-readonly-cluster-user   # yes
```
