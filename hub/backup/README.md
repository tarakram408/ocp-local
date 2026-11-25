# Hub backup and restore

## S3 endpoints (ONTAP)

| Server | SVM / site | LIFs (storage VLAN 222) | Buckets |
|---|---|---|---|
| `s3-site-b.example.com` | `SVM_OCP_B`, DC2 | `.77` (nas0204e), `.78` (nas0204f) | `acm-backup-acm` (200 GiB), `acm-metrics-hub-b` (95 GiB) |
| `s3-site-a.example.com` | `SVM_OCP_A`, DC1 | `.151` (nas01e), `.152` (nas01f) | `acm-metrics-hub-a` (100 GiB) |

Each bucket has one policy statement: `sm_s3_user` (per SVM) allowed GetObject, PutObject, DeleteObject, ListBucket,
GetBucketLocation, ListBucketMultipartUploads, ListMultipartUploadParts. Versioning and object locking off.

Requirements found while setting these up:

- **Pods reach the LIFs over `bond1.222`** only with common feature 16 (`routing-via-host`). A routed path is asymmetric:
  the SVMs default-route out of their management network.
- **Every S3 LIF carries the S3 service** (service policy `sm-custom-service-policy-nas-s3`); DNS returns both LIFs.
- **The certificate needs a Subject Alternative Name.** Velero and Thanos (Go) ignore the Common Name. ONTAP's default
  S3 certificate has only a CN, so it is reissued: `security certificate generate-csr -common-name <fqdn> -dns-name <fqdn>
  -extended-key-usage serverAuth`, `security certificate sign -vserver <svm> -ca SVM_SYSMGR_CA -ca-serial <serial>
  -expire-days 720` (must end before the CA, Oct 2028), `security certificate install -vserver <svm> -type server`,
  `vserver object-store-server modify -certificate-name <name>`. Check: `openssl s_client -connect <fqdn>:443 |
  openssl x509 -noout -ext subjectAltName`. Clients trust the root CA `SVM_SYSMGR_CA` **of the SVM they talk to**.
  Every SVM generates its own CA with that same name, so a CA from the wrong SVM fails with
  `x509: certificate signed by unknown authority (… crypto/rsa: verification error … "SVM_SYSMGR_CA")`. The same error
  appears when a client is sent to the wrong S3 server, so check its bucket and endpoint before its CA (12 Nov):

  | Client | Bucket | SVM | CA it must trust |
  |---|---|---|---|
  | Velero, both hubs (`caCert` in `dpa.yaml`) | `acm-backup-acm` | SVM_OCP_B | SVM_OCP_B's `SVM_SYSMGR_CA` |
  | Thanos on `hub-a` (secret `thanos-s3-ca`) | `acm-metrics-hub-a` | SVM_OCP_A | SVM_OCP_A's `SVM_SYSMGR_CA` (serial `18E25DAEF53B3D81`) |
  | Thanos on `hub-b` (secret `thanos-s3-ca`) | `acm-metrics-hub-b` | SVM_OCP_B | SVM_OCP_B's `SVM_SYSMGR_CA` |

  Sign each S3 certificate with **its own SVM's** CA (`-vserver <svm> -ca-serial <that SVM's root-ca serial>`, from
  `security certificate show -vserver <svm> -type root-ca`). Check a client's CA against the server certificate before
  changing anything: export both with `security certificate show -vserver <svm> -cert-name <name> -fields public-cert`
  (the bastion cannot reach the S3 LIFs) and run `openssl verify -CAfile <ca.pem> <server.pem>`.
  Both SVM CAs expire 21 Oct 2028: renew them and update every place above before then.
- **ONTAP rejects the AWS SDK's default checksum header** (`x-amz-content-sha256 must be UNSIGNED-PAYLOAD...`, HTTP 400).
  `dpa.yaml` sets `AWS_REQUEST_CHECKSUM_CALCULATION` and `AWS_RESPONSE_CHECKSUM_VALIDATION` to `when_required` on the
  Velero pod (and `checksumAlgorithm: ""`); `checksumAlgorithm` alone was not enough.

Check the bucket on ONTAP: `vserver object-store-server bucket show -vserver SVM_OCP_B -bucket acm-backup-acm
-fields logical-used,object-count,incomplete-multipart-uploads-count` (about 9 objects per Velero backup).

`hub-a` is the active hub and `hub-b` the passive one. Both run the RHACM `cluster-backup` component (OADP) with the
same backup location (`dpa.yaml`, an S3 bucket on the DC2 SVM `SVM_OCP_B`).

| File | Hub | What |
|---|---|---|
| `hub/backup/dpa.yaml` | both | Backup storage location |
| `hubs/hub-a/backup-schedule.yaml` | hub-a | Backups every 2 hours, kept 5 days |
| `hubs/hub-b/restore.yaml` | hub-b | Passive restore every 10 minutes: credentials and resources, not the managed clusters |

The passive Restore excludes `applications.argoproj.io`, `applicationsets.argoproj.io` and `appprojects.argoproj.io`: the first restore on 28 Oct brought `hub-a`'s `clusters` and `policies` apps and its ApplicationSets onto `hub-b` although they carry `velero.io/exclude-from-backup: "true"` (the label stays, but is not relied on). After any restore, check that `hub-b` lists only `root`, `hub-config` and `common-config`. Each hub's apps come from its own `argocd-apps*` folder; a restored `hub-a` app on `hub-b` would start managing
production from the passive hub.

Secrets created by hand on `hub-a` reach `hub-b` through the credentials backup when they carry the label
`cluster.open-cluster-management.io/backup` (existing secrets on `hub-b` are not overwritten):

```
oc -n policies label secret htpasswd ldap-bind cluster.open-cluster-management.io/backup=""
oc -n policies get secret -o name | grep ontap-credentials | xargs -r -I{} oc -n policies label {} cluster.open-cluster-management.io/backup=""
oc -n cluster-install-secrets label secret --all cluster.open-cluster-management.io/backup=""
```

## Incident 28 Oct and the checks after every restore

The first passive restore (without `excludedResources`) brought `hub-a`'s Argo CD Applications, including `root` and
`hub-config`, onto `hub-b`. For about 30 minutes `hub-b` synced `hub-a`'s hub configuration: production apps and
policies, `hub-a`'s storage address (`10.60.140.50`) and its BackupSchedule, which took one backup into the shared
bucket and put `hub-a`'s schedule into `BackupCollision`. No production impact (no managed clusters yet).
Recovery: re-apply `bootstrap/hub-b/root-app.yaml`, delete the restored apps/ApplicationSets and production policies,
delete `hub-b`'s backup set with `velero backup delete`, recreate `hub-a`'s schedule from git.

After any restore on `hub-b`:

```
oc get applications.argoproj.io -n openshift-gitops -o custom-columns=NAME:.metadata.name,PATH:.spec.source.path
#   only root (argocd-apps-hub-b), hub-config (hubs/hub-b), common-config
oc get applicationsets.argoproj.io -n openshift-gitops          # none
oc get backupschedule -n open-cluster-management-backup         # none on hub-b
oc get nncp storage-network -o jsonpath='{.spec.desiredState.interfaces[1].ipv4.address}'   # 10.60.140.51
oc get restore.velero.io -n open-cluster-management-backup -o custom-columns=NAME:.metadata.name,EXCL:.spec.excludedResources
oc get policy -n local-cluster open-cluster-management-backup.backup-restore-enabled   # Compliant (also on hub-a)
```

`hub-a`'s production policies, placements and policy sets in `policies` on `hub-b` are expected (restored hub
resources; their placements select no cluster while managed clusters are skipped). Do not delete them.
Use ACM's `Restore` for tests, not the OADP console's "Create Restore" (no ACM logic, no exclusions).

## Incident 10–11 Nov: backup location Unavailable

The commit "Updated config first run" (10 Nov) replaced `hub/backup/dpa.yaml` with a copy whose `caCert` was commented
out. Argo CD synced it, Velero no longer trusted `svm-ocp-b-s3`, the BackupStorageLocation `hub-backup` went
**Unavailable**, every scheduled backup ended **FailedValidation** ("backup can't be created because
BackupStorageLocation hub-backup is in Unavailable status"), and the `acm-hub-backup` policy set showed a violation
(`acm-backup-phase-validation`, `backup-storage-location-available`). Fixed 11 Nov by restoring the `caCert` line
(the 27 Oct version); the location is Available and the backups complete again. `caCert` is required, not optional.

```
oc get backupstoragelocation -n open-cluster-management-backup                 # hub-backup Available
oc get backupschedule schedule-acm -n open-cluster-management-backup -o jsonpath='{.status.phase}{"\n"}{.status.lastMessage}{"\n"}'
oc logs -n open-cluster-management-backup deploy/velero --tail=50 | grep -i error
oc get policy -n local-cluster | grep backup                                   # Compliant
```

## Incident 11–12 Nov: hub-b Thanos pointed at hub-a's bucket

hub-b's `observability-thanos-store-shard-*` and `observability-thanos-compact-0` crash-looped (up to 1,759 restarts,
alerts `ACMThanosCompactHasNotRun`, `ACMThanosCompactBucketHighOperationFailures`) with
`x509 … crypto/rsa: verification error … "SVM_SYSMGR_CA"` against `https://s3-site-a.example.com/acm-metrics-hub-a/`.

- Cause: hub-b's `thanos-object-storage` was **hub-a's** secret, restored by the passive sync
  (`velero.io/restore-name=restore-acm-passive-sync-acm-credentials-schedule-…`). The observability operator puts the
  `cluster.open-cluster-management.io/backup` label on that secret by itself (removing it on hub-a does not last), so
  it is in every credentials backup. hub-b's `thanos-s3-ca` correctly holds SVM_OCP_B's CA (serial `18E266DDFD17900A`),
  which cannot verify SVM_OCP_A's certificate: hence the x509 error. hub-a was healthy throughout.
- The x509 error was also what stopped two compactors from working on one bucket; never "fix" it by adding the other
  SVM's CA on hub-b.
- Fix (12 Nov 09:25): on hub-b, delete the restored secret and create its own (bucket `acm-metrics-hub-b`, endpoint
  `s3-site-b.example.com`, that bucket's keys; `hub/observability/thanos-object-storage.yaml.example`), without
  velero labels, then restart the store and compact pods.
- Check after every passive restore cycle that it stayed:

```
oc get secret thanos-object-storage -n open-cluster-management-observability \
  -o jsonpath='{.data.thanos\.yaml}' | base64 -d | grep -E "bucket|endpoint"      # acm-metrics-hub-b / svm-ocp-b-s3
oc get secret thanos-object-storage -n open-cluster-management-observability --show-labels | grep -o "velero[^,]*"   # none
oc get pods -n open-cluster-management-observability | grep -E "store|compact"   # Running
```

  If the restore brings hub-a's settings back, `hubs/hub-b/restore.yaml` has to leave that secret out of the passive
  sync (and the failover step below has to restore it on activation).
- On failover, hub-b keeps its own bucket (`acm-metrics-hub-b`) unless hub-a's history is wanted: then switch the
  secret to hub-a's bucket only after hub-a's compactor is confirmed stopped.

## Leftovers on hub-b from cnv-mtv-integrations (12 Nov)

`cnv-mtv-integrations` was on for hub-b for a few minutes on 11 Nov (before the explicit `enabled: false`). Its add-ons
installed OpenShift Virtualization and MTV on the hub; when the component was switched off they stayed and raised
`HCOInstallationIncomplete`. Removed by hand (no VMs on hub-b):

```
oc delete subscription,csv,operatorgroup --all -n openshift-cnv && oc delete ns openshift-cnv
oc delete subscription,csv,operatorgroup --all -n openshift-mtv && oc delete ns openshift-mtv
```

The deleted CSVs of other operators in those namespaces (GitOps, Trident) were OLM's per-namespace copies; the
operators are untouched. The OpenShift Virtualization CRDs remain and are inert.

## Failover (DC1 lost)

1. Confirm `hub-a` is down and stays down. Two active hubs fight over the same clusters.
2. In git: `hubs/hub-b/restore.yaml` set `veleroManagedClustersBackupName: latest`; in
   `argocd-apps-hub-b/kustomization.yaml` uncomment `policies.yaml`, `trident-protect-appset.yaml`, `workloads-appset.yaml`. Push.
3. On `hub-b`: `oc get managedcluster` until `ocp-a` and `ocp-b` are `Available` (`useManagedServiceAccount` lets them reconnect).
4. Copy `hubs/hub-a/backup-schedule.yaml` to `hubs/hub-b/` and list it, so `hub-b` becomes the backup source.
5. Copy the `cnv-mtv-integrations` patch from `hubs/hub-a/kustomization.yaml` into `hubs/hub-b/kustomization.yaml`
   (MTV on the hub for VM migrations; the `mtv-hub-*` policies come with `policies.yaml`).
6. Enable `clusters.yaml` only after a DR test has shown the restored install records do not trigger a reinstall.

## Failback

Remove the schedule from `hubs/hub-b/`, restore `hubs/hub-b/restore.yaml` to passive (`skip`) only after `hub-a`
holds the clusters again, and check that `hub-a`'s schedule does not report `BackupCollision`.
