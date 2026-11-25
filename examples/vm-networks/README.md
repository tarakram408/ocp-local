# VM network options

Nothing in this folder is applied. Pick one, move it into `policies/manifests/` and add a policy entry.
All three reach a datacenter VLAN through the same node plumbing: the `vm-trunk` mapping in
`policies/manifests/node-network/vm-uplink.yaml`.

| Option | Scope | Use it when | GitOps fit |
|---|---|---|---|
| `cudn-localnet.yaml` | Cluster, selects namespaces by label | VMs keep their existing VLAN and IP addresses. Red Hat's recommended way to put a VM on a physical network in 4.22. | Best: one object per VLAN, namespaces opt in with a label |
| `udn-primary-layer2.yaml` | One namespace | A new isolated network that replaces the pod network for that namespace. VMs get new, cluster-assigned addresses. | Good, but one object per namespace |
| `nad-localnet.yaml` | One namespace | Linux bridge or SR-IOV is needed, or an existing design must be matched. | Works, but one copy per namespace per VLAN |

For 25 migrated VMs that should keep their addresses, start with the CUDN.

**Migration constraint.** The NetApp Shift Toolkit and MTV map each VMware port group to a
NetworkAttachmentDefinition, so the target networks must exist as NADs before plans are written.
A plain NAD satisfies that directly. A localnet CUDN should too, because it generates a NAD of the
same name in every namespace it selects; confirm MTV offers it as a target before committing to it.
A primary UDN does not fit VMs that must keep their VLAN addresses.

**Chosen for the migration:** plain localnet NADs, one per VLAN, in `policies/manifests/vm-networks/` (see the
repository README, "VM networking"). They set `physicalNetworkName: vm-trunk` so that every VLAN can share one
bridge mapping; `nad-localnet.yaml` below is the single-VLAN form without it.
