# Bare metal provisioning on the UCS blades

Redfish verified 28 Oct 2026; first production install (`ocp-a`) 30 Oct 2026.

> **Outcome (4 Nov 2026):** virtual media never mounted with out-of-band CIMC management (no outbound SNAT on the UCS NAT for CIMC-initiated traffic), so `ocp-a` was installed through the Assisted Installer on console.redhat.com instead. See ocp-a-as-built.md. This page stays the reference for the hub-driven build of `ocp-b` and the later rebuild.

## Redfish

The hub builds `ocp-a` and `ocp-b` over Redfish virtual media, talking to each blade's own management controller
(the vKVM address in the host sheet), not to UCS Manager (`ucs-fi` returns 404 on `/redfish/v1/`).

| Check | Result |
|---|---|
| Redfish service | 1.10.0 on every blade KVM address |
| System ID | the blade serial: `/redfish/v1/Systems/<serial>` (all 18 nodes match `clusters/*/clusterinstance.yaml`) |
| Login | users of the IPMI/Redfish access profile `OCP-Redfish` (org INFRA) attached to the blade's service profile. UCS Manager LDAP users (`ucs-Corp_LDAP\<user>`) are not accepted |
| Power | `ComputerSystem.Reset`: On, ForceOff, ForceRestart, GracefulShutdown, GracefulRestart, PowerCycle, Nmi |
| Boot override | `Cd` allowed |
| Virtual media | `/redfish/v1/Managers/CIMC/VirtualMedia/3`: DVD, `InsertMedia`/`EjectMedia` (0-2 are UCSM vMedia slots, 4 USB) |
| Reach from the hub | `hub-a` node to DC1 and DC2 blade KVM addresses, TCP 443: 200 |

Before each production build (status 30 Oct in brackets):

- Attach `OCP-Redfish` to the service profile of every blade the hub builds, and use a dedicated user in it (not
  `kvmadmin`, which is also a UCS Manager admin). [open: the dedicated user is not created yet]
- Put that user in `bmc-credentials` (namespace `cluster-install-secrets`) on `hub-a`, labelled
  `cluster.open-cluster-management.io/backup` so `hub-b` gets it.
- The blade must be out of vSphere first: the hub powers every listed blade off and on as soon as the
  `ClusterInstance` syncs, and the install wipes the boot drive.
- Boot policy: local disk first, then **CIMC Mounted vMedia > CIMC Mounted CD/DVD**. Redfish one-time boot to CD only
  works when the policy has that entry; "Remote CD/DVD" is the KVM-mapped drive, not the one Ironic uses.
  [Added 30 Oct to `OCP_Boot_Policy` as order 2, after Embedded LUN 1, Remote CD/DVD 3; Reboot on Boot Order
  Change: No. That policy is shared by the ESXi hosts: do not acknowledge pending activities for them. A separate
  `OCP_Boot_Pol` was also created in org INFRA.]
- Read the MGMT MACs from UCS after each blade is bound to its final service profile template.
  [On 30 Oct the `ocp-a` blades were still on their ESXi service profiles (`bl-esx-*`); the install used the MACs in
  the host sheet. Confirm the template and the NIC names (`ip -br link`) on the installed nodes before the day-2
  storage, VM and live-migration NNCPs (`ens5f2`-`ens5f7`) apply. Rebinding a blade to another template changes its
  MACs.]

Check all nodes (password read once, not stored):

```
read -s -p "password: " P; echo
while read n ip sn; do
  got=$(curl -ksS -m10 -u "<user>:$P" https://$ip/redfish/v1/Systems | jq -r '.Members[0]."@odata.id"')
  [ "$got" = "/redfish/v1/Systems/$sn" ] && echo "$n OK" || echo "$n FAIL ($got)"
done < <(grep -hE "hostName:|bmcAddress:" clusters/*/clusterinstance.yaml | paste - - | \
  sed -E 's/.*hostName: ([^.]+).*\/\/([0-9.]+)\/redfish\/v1\/Systems\/([A-Z0-9]+).*/\1 \2 \3/')
unset P
```

## ocp-a install, 30 Oct: findings

| Finding | Detail | Handling |
|---|---|---|
| Blades booted ESXi | The production blades were still on their ESXi service profiles and `OCP_Boot_Policy` (no CIMC CD/DVD entry), so the Redfish one-time CD boot fell through to the local ESXi disk. The hub then kept cycling all 12 blades through inspection | Pause the BareMetalHosts (below), add CIMC Mounted CD/DVD to the boot policy, release blades only once out of vSphere |
| CIMC cannot mount the image | Ironic inserts `http://10.64.55.70:6180/redfish/boot-<ironic node>.iso` (HTTPS on 6183 before `disableVirtualMediaTLS`) into `VirtualMedia/3` (`InsertMedia`, HTTP 202). The CIMC reports "Mount failed". See the investigation below | Open. Workaround: one shared ISO through the KVM (below) |
| Ironic powers blades off | Pausing a BMH stops the Bare Metal Operator, not Ironic. Ironic's power-state sync kept powering blades off because its recorded state was `power off`, then put a node in maintenance after repeated mismatches (`sync_power_state ... Changing hardware state to 'power off'` in the `metal3-ironic` log) | With every BMH paused: `oc -n openshift-machine-api rollout restart deploy/metal3` (Ironic's database is in memory, the paused hosts are not re-registered) |
| Install disk not valid | `rootDeviceHints: /dev/sda` matched on 1 of 12 blades: the KVM virtual drives take `sda`-`sdc`, so the 240 GB boot drive is `sdc`/`sdd` | `deviceName: /dev/disk/by-path/pci-0000:04:00.0-ata-1.0` (same on all 12, now in `clusterinstance.yaml`); for a running install, patch each Agent's `installation_disk_id` |
| No network after first reboot | With one shared ISO, the node's static network (`bond0` + `bond0.24`) is not carried onto the installed disk: Ignition loops on `GET https://10.64.55.90:22623/config/master` | Kernel arguments at the first boot from disk (below); `scripts/set-node-kargs.py` for a whole ClusterInstance (fallback only) |
| Namespace deleted on teardown | After the ClusterInstance was deleted the `ocp-a` namespace went to Terminating and was removed. Argo CD then retried with `namespaces "ocp-a" not found` even after the namespace was gone | Create the namespace (`oc create ns ocp-a`), then in Argo CD Terminate and Sync `clusters`; check the two install secrets are copied back |
| `oc get applications` returns nothing | ACM also installs `applications.app.k8s.io` | Use `applications.argoproj.io` |

Hosts paused or removed while blades are being worked on:

```
K="--kubeconfig $HOME/hub-a.kubeconfig"; C=ocp-a
for b in $(oc $K get bmh -n $C -o name); do oc $K annotate $b -n $C baremetalhost.metal3.io/paused="" --overwrite; done
oc $K get bmh -n $C -o custom-columns=NAME:.metadata.name,PAUSED:.metadata.annotations.baremetalhost\\.metal3\\.io/paused   # blank = paused
oc $K -n openshift-machine-api rollout restart deploy/metal3     # stop Ironic acting on the paused hosts
```

Tear down a cluster that never installed (no VMs, no failover; the `baremetalhost.metal3.io/detached` annotation is not
honoured while a host is inspecting):

```
# 1. comment the cluster out of clusters/kustomization.yaml and push; check ClusterInstance shows prune=true:
oc $K -n openshift-gitops get applications.argoproj.io clusters -o json | jq -r '.status.resources[] | select(.namespace=="'$C'") | .kind+"/"+.name+" prune="+((.requiresPruning//false)|tostring)'
# 2. delete without power actions
oc $K delete clusterinstance $C -n $C --wait=false; sleep 20
for b in $(oc $K get bmh -n $C -o name); do oc $K patch $b -n $C --type=merge -p '{"metadata":{"finalizers":null}}'; done
oc $K -n openshift-machine-api rollout restart deploy/metal3
# 3. wait until the namespace is gone, then restore the line in git and push
```

## Single shared discovery ISO (workaround while virtual media fails)

1. Keep every BMH paused and restart metal3 (above).
2. One InfraEnv for the whole cluster, carrying every node's `NMStateConfig` (each blade picks its own by MAC):
   ```
   oc $K get infraenv $C-cp01.$C.example.com -n $C -o json \
    | jq '{apiVersion,kind,metadata:{name:"'$C'-all",namespace:"'$C'"},spec:(.spec|.nmStateConfigLabelSelector={matchLabels:{"'$C'-all":"true"}})}' \
    | oc $K apply -f -
   oc $K label nmstateconfig --all -n $C $C-all=true
   oc $K get infraenv $C-all -n $C -o jsonpath='{.status.isoDownloadURL}{"\n"}'
   ```
   The object is not in git; delete it after the install.
3. Per blade (out of vSphere): KVM **Virtual Media > vKVM-Mapped vDVD** (the ISO streams from the operator's PC,
   so keep the KVM open), **Boot Device > vKVM-Mapped vDVD**, **Power Cycle**.
4. Agents register with hostname and role filled in from the BMHs. Set the install disk if `SpecSynced` is False:
   ```
   for a in $(oc $K get agent -n $C -o name); do
     D=$(oc $K get $a -n $C -o json | jq -r '[.status.inventory.disks[] | select(.installationEligibility.eligible==true)] | if length==1 then .[0].id else "SKIP" end')
     [ "$D" != "SKIP" ] && oc $K patch $a -n $C --type=merge -p "{\"spec\":{\"installation_disk_id\":\"$D\"}}"
   done
   ```
5. At each node's first boot from disk (agent stage `Rebooting`), stop GRUB, press `e` on the CoreOS entry and append
   to the `linux` line (KVM **File > Paste Clipboard Text**). Generate the lines:
   ```
   oc $K get nmstateconfig -n $C -o json | jq -r '.items[] | .metadata.name as $n | .spec.config as $c
    | ($c.interfaces[] | select(.type=="vlan")) as $v | ($c.interfaces[] | select(.type=="bond")) as $b
    | "\($n):\n  ip=\($v.ipv4.address[0].ip)::\($c.routes.config[0]."next-hop-address"):255.255.255.0::\($v.name):none bond=\($b.name):\($b."link-aggregation".port|join(",")):mode=active-backup,miimon=100 vlan=\($v.name):\($b.name) nameserver=\($c."dns-resolver".config.server|join(" nameserver="))"'
   ```
   RHCOS keeps network settings given this way on the first boot. Nodes whose disk is not written yet can take the
   same arguments through the Agent instead (`spec.installerArgs`, a JSON list of `--append-karg`, `<arg>` pairs) if
   the agent still accepts spec changes.
6. Watch: `oc $K get agent -n $C -o custom-columns=HOST:.spec.hostname,STAGE:.status.progress.currentStage,PCT:.status.progress.installationPercentage`
   and the events: `curl -sk "$(oc $K get agentclusterinstall $C -n $C -o jsonpath='{.status.debugInfo.eventsURL}')" | jq -r '.[-15:][] | .event_time[11:19]+"  "+.message'`.
7. After the install: unmap the vKVM DVDs and delete the `<cluster>-all` InfraEnv. **Leave the BMHs paused**: they are
   still in `inspecting`, and resuming them can make the hub power-cycle running nodes. How to hand them back
   (detach, or re-register as externally provisioned) is an open item.

## Virtual media investigation (open)

Confirmed on cp01 (`10.64.55.200`, CIMC firmware with BIOS `B200M5.4.3.2b`):

- `VirtualMedia/3` is `CIMC-Mapped vDVD`, `MediaTypes: [DVD]`, `ConnectedVia: URI`; `InsertMedia` accepts
  `TransferProtocolType` CIFS, HTTP, HTTPS, NFS, OEM. The KVM lists a mounted image in place of the
  "CIMC-Mapped vDVD" entry (it is not the floppy).
- Ironic first PATCHes `VirtualMedia/1` (HTTP 400, not supported), then uses `InsertMedia` on slot 3 (HTTP 202).
- The hub serves the ISO: `curl -I http://10.64.55.70:6180/redfish/boot-<node>.iso` from the bastion returns 200.
- Every insert returns a task "vmedia insert local media monitor" that ends about one second later with
  `TaskStatus: Warning`, "Mount failed", whatever the URL: hub `:6180`, bastion Apache on `:80` and on `:6180`, with
  and without `TransferProtocolType: HTTP`. The KVM shows "CIMC Mapped vDVD mount failed" and "The HTTP protocol will
  be deprecated". So the port and the request body are not the cause.
- Hub, bastion and blade KVM addresses are all on `10.64.55.0/24` (no firewall between them).

Next (helper: `source scripts/redfish-vmedia.sh <KVM IP>`, functions `st`, `ins`, `ins2`, `ej`, `task`):

1. `tcpdump -nn -i any tcp port 80` on the bastion during `ins http://10.64.55.248/<file>.iso`: does any packet
   arrive, and from which source address (the KVM address or a fabric interconnect management address)?
2. From UCS Manager: `connect cimc <chassis>/<blade>` and `connect local-mgmt a|b`, `ping 10.64.55.248` and
   `ping 10.64.55.70`.
3. UCS Manager version, blade CIMC firmware, whether the KVM address pool is out-of-band or in-band, and the FI faults/FSM
   for the blade right after a failed mount.
4. Then, depending on 1-3: routing or VLAN of the CIMC's outbound traffic, a UCS setting that blocks URI vMedia, or a
   firmware defect (Cisco TAC).

## Production SVMs (to be created)

Not created yet; decisions open (see the README "Items to confirm"). Whether `ocp-a`/`ocp-b` use new SVMs or the
SVMs holding the VMware datastores depends on NetApp's answer for the Shift Toolkit (in-place conversion).
Template for a new SVM (DC1 shown; DC2 the same on `c1_nas_cluster` with `nas0204e`/`nas0204f` and the N04e/N04f
aggregates):

```
vserver create -vserver SVM_PROD -rootvolume svm_prod_root -aggregate aggr3g_ssd1 -rootvolume-security-style unix -language C.UTF-8
vserver add-aggregates -vserver SVM_PROD -aggregates aggr3g_ssd1,aggr3h_ssd1
vserver nfs create -vserver SVM_PROD -v3 enabled -v4.0 disabled -v4.1 enabled -v4-numeric-ids enabled
vserver export-policy create -vserver SVM_PROD -policyname ocp-nfs
vserver export-policy rule create -vserver SVM_PROD -policyname ocp-nfs -clientmatch 10.60.140.0/24 -protocol nfs -rorule sys -rwrule sys -superuser sys
volume modify -vserver SVM_PROD -volume svm_prod_root -policy ocp-nfs
network interface create -vserver SVM_PROD -lif svm_prod_nfs1 -service-policy default-data-files -home-node nas01g -home-port a0a-222 -address 172.18.140.CHANGEME -netmask 255.255.255.0
network interface create -vserver SVM_PROD -lif svm_prod_nfs2 -service-policy default-data-files -home-node nas01h -home-port a0a-222 -address 172.18.140.CHANGEME -netmask 255.255.255.0
network interface create -vserver SVM_PROD -lif svm_prod_mgmt -service-policy default-management -home-node nas01g -home-port CHANGEME -address 172.16.250.CHANGEME -netmask 255.255.255.0
network route create -vserver SVM_PROD -destination 0.0.0.0/0 -gateway 10.61.250.1
security login create -vserver SVM_PROD -user-or-group-name trident_prod -application http   -authentication-method password -role vsadmin
security login create -vserver SVM_PROD -user-or-group-name trident_prod -application ontapi -authentication-method password -role vsadmin
vserver peer create -vserver SVM_PROD -peer-vserver SVM_PROD_B -peer-cluster c1_nas_cluster -applications snapmirror   # accept on c1_nas_cluster
```

Then: `ontap-credentials-<cluster>` secrets in `policies` on the hub (with the backup label), and `ontapSVM`,
`ontapManagementLIF`, `ontapDataLIF`, `ontapExportPolicy: "ocp-nfs"` in `policies/site-values/<cluster>.yaml`.
The export policy must be read-write with superuser for `10.60.140.0/24` (the hubs showed that a read-only default
policy gives volumes that bind but cannot be written).
