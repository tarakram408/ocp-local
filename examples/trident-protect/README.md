# Trident Protect: protecting and replicating the VMs

Nothing in this folder is applied. These are the objects that make the failover cluster useful for VMs.
`vm-workloads` stands for one VM namespace; repeat per namespace.

| File | Applied on | Purpose |
|---|---|---|
| `appvault.yaml` | both clusters | Where Trident Protect keeps application metadata and backups (an ONTAP S3 bucket) |
| `application.yaml` | primary | Declares the namespace as one protected application |
| `schedule-replication.yaml` | primary | Takes the snapshots that replication ships |
| `appmirrorrelationship.yaml` | failover | SnapMirror replication of the app from primary to failover |

Prerequisites outside git: the two ONTAP clusters and SVMs are peered, and each cluster's storage class
points at its own peered SVM.

**Fail over:** on the failover cluster set `spec.desiredState: Promoted`.
**Fail back:** reverse the relationship (delete it, recreate it with source and destination swapped), let it sync, then promote on the original primary.

`sourceApplicationUID` is a runtime value read from the primary cluster
(`oc get application.protect.trident.netapp.io -n vm-workloads -o jsonpath='{.items[0].metadata.uid}'`).
It changes whenever the Application is recreated, including after a cluster rebuild, so this one field
has to be updated by hand or by an AAP job.
