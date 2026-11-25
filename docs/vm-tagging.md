# VM tags

Every VM on ocp-a and ocp-b carries the same required tags as the Production vCenter (requirements from Enterprise
Storage and Virtualization, 19 Nov 2026). New VMs are checked when they are created; existing and migrated VMs are listed
in a report until they are tagged.


## The tags

| vSphere tag | OpenShift key | Kept as | Allowed values |
|---|---|---|---|
| Environment | `example.com/environment` | label | `sbx`, `dev`, `tst`, `prd` |
| SupportLevel | `example.com/support-level` | label | `24x7`, `9x5`, `Unmanaged` |
| DRTier | `example.com/dr-tier` | label | `1`, `2`, `3` |
| OS | `example.com/os` | label | `Windows`, `Linux` (other single words allowed) |
| Application | `example.com/application` | annotation | free text |
| ChargingAccount | `example.com/charging-account` | annotation | free text, e.g. `CO01…XX000000.CC0001.PG00001.PJ000001…` |
| CreatedBy | `example.com/created-by` | annotation | free text (NetID) |
| OwnerDepartment | `example.com/owner-department` | annotation | free text |
| OwnerDepartmentContact | `example.com/owner-department-contact` | annotation | free text (e-mail) |
| SupportDepartment | `example.com/support-department` | annotation | free text |
| SupportDepartmentContact | `example.com/support-department-contact` | annotation | free text (e-mail) |

**Why two kinds.** Labels hold short fixed values and can be searched and filtered (`oc get vm -l example.com/environment=prd`,
console filters, metrics). Label values cannot contain spaces, `@` or more than 63 characters, so names, e-mail addresses
and charging accounts are annotations.

## What is in git

| File | What it does |
|---|---|
| `policies/manifests/vm-tagging/vm-tagging.yaml` | Admission policy `vm-tags`: checks every new VM for all eleven tags and the three fixed value lists |
| `policies/site-values/<cluster>.yaml`, `vmTagEnforcement` | `Warn`: the VM is created and the person sees a warning. `Deny`: the VM is refused. Both clusters start on `Warn` |
| `policies/manifests/vm-tagging-report/vm-tagging-report.yaml` | Report only (inform): lists every VM that is missing a tag. Never changes a VM |
| `policies/manifests/vm-templates/corp-rhel9-server-small.yaml` | The Corp template puts every tag key on the VM (empty, filled in on the wizard's Customization step); OS is fixed to `Linux` |
| `scripts/tag-vm.sh` | Tags existing VMs, one at a time or a whole migration wave from a CSV |

## Not checked when created

- **VMs created by MTV** (`openshift-mtv` service accounts, and the hub MTV provider account for cluster-to-cluster
  migrations). A migration must not fail because of tags; migrated VMs are tagged afterwards with `scripts/tag-vm.sh` and
  show in the report until then.
- **OpenShift Virtualization itself** (`openshift-cnv`: clones, snapshot restores) and every `openshift-*` namespace.
- **Namespaces labelled `example.com/vm-tags=exempt`** (for example a test namespace):
  `oc $W label namespace <ns> example.com/vm-tags=exempt`.

Changing a VM later is not checked by the admission policy; removing a tag makes the VM appear in the report.

## Creating a VM

**From the Corp template (recommended).** Virtualization → VirtualMachines → Create → From template →
**Corp RHEL 9 VM (small)**. The VM already carries every Corp key with an empty value (and `example.com/os: Linux`). On the
**Customization** step, open **Metadata** (or the **YAML** tab) and fill in the values: labels `example.com/environment`,
`example.com/support-level`, `example.com/dr-tier`; annotations Application, Charging account, Created by, Owner department and
contact, Support department and contact. Then create.

The template parameters are deliberately not marked required: the 4.22 wizard cannot process a template with required
parameters that have no value and stops at Customization. A value left empty gets the same warning (or refusal) as a
missing tag.

**From YAML or another template.** Add the tags to the VM's `metadata`:

```yaml
metadata:
  labels:
    example.com/environment: prd
    example.com/support-level: 24x7
    example.com/dr-tier: "1"                      # quoted: label values are strings
    example.com/os: Linux
  annotations:
    example.com/application: Payroll web
    example.com/charging-account: CO01.XX000000.CC0001.PG00001.PJ000001
    example.com/created-by: vm-test01
    example.com/owner-department: ITS
    example.com/owner-department-contact: owner@example.com
    example.com/support-department: ITS Linux
    example.com/support-department-contact: support@example.com
```

**What a missing tag looks like.** With `Warn`, the console shows a yellow warning after Create and `oc` prints:

```
Warning: VM web01 is missing required Corp tags: example.com/dr-tier, example.com/charging-account. Use a Corp template ...
```

With `Deny` the same message is an error and the VM is not created. A wrong fixed value gives, for example,
`example.com/environment must be one of sbx, dev, tst, prd (got prod)`.

## Tagging existing and migrated VMs

Interactive (the script asks for each tag, shows the current value in `[ ]`, Enter keeps it; fixed values are checked
and asked again if wrong; nothing changes until you answer `y`):

```bash
OC="oc $W" scripts/tag-vm.sh --list                           # list only: every VM missing tags, and which tags
OC="oc $W" scripts/tag-vm.sh                                  # same list, numbered: pick one, answer, repeat; Enter quits
OC="oc $W" scripts/tag-vm.sh virtual-machines vm-test01-linux     # straight to the questions for this VM
```

```
Tags for virtual-machines/vm-test01-linux (Enter keeps the current value shown in [ ]):
  Environment (sbx, dev, tst, prd) []: prd
  SupportLevel (24x7, 9x5, Unmanaged) []: 24x7
  DRTier (1, 2, 3) []: 1
  ...
Apply? [y/N]: y
```

One VM with everything on the command line (no questions, for scripts):

```bash
OC="oc $W" scripts/tag-vm.sh virtual-machines vm-test01-linux \
  Environment=prd SupportLevel=24x7 DRTier=1 OS=Linux Application="Payroll web" \
  ChargingAccount=CO01.XX000000.CC0001.PG00001.PJ000001 CreatedBy=vm-test01 \
  OwnerDepartment=ITS OwnerDepartmentContact=owner@example.com \
  SupportDepartment="ITS Linux" SupportDepartmentContact=support@example.com
```

A migration wave: one CSV row per VM, with the vSphere tag names as column headers (export them from vCenter with
PowerCLI `Get-TagAssignment`):

```
namespace,vm,Environment,SupportLevel,DRTier,OS,Application,ChargingAccount,CreatedBy,OwnerDepartment,OwnerDepartmentContact,SupportDepartment,SupportDepartmentContact
virtual-machines,vm-test01-linux,prd,24x7,1,Linux,Payroll web,CO01.XX000000.CC0001.PG00001.PJ000001,vm-test01,ITS,owner@example.com,ITS Linux,support@example.com
```

```bash
OC="oc $W" scripts/tag-vm.sh --csv wave-1-tags.csv
```

The script checks the fixed values before changing anything (a row with a wrong value is skipped and reported), only sets
the tags given, and does not restart the VM. Use the OpenShift VM name (lower case), which can differ from the vSphere name.

## Checking

```bash
oc $W get vm -A -L example.com/environment,example.com/support-level,example.com/dr-tier,example.com/os
oc $W get validatingadmissionpolicy vm-tags
oc $W get validatingadmissionpolicybinding vm-tags -o jsonpath='{.spec.validationActions}{"\n"}'   # ["Warn","Audit"]
```

Console: **Governance → Policies**
- `vm-tagging`: Compliant on ocp-a and ocp-b (the admission policy is in place).
- `vm-tagging-report`: NonCompliant while any VM is missing tags. Open it → the cluster → **View details**: one entry per
  VM that is missing labels and one per VM missing annotations (`found but not as specified`). Compliant once every VM
  is tagged. Argo CD shows it Healthy either way (annotation `example.com/argocd-health: report-only`).
- Which tags each VM is missing, from the command line:

  ```bash
  oc $W get vm -A -o json | jq -r '.items[] | select(.metadata.namespace | startswith("openshift") | not)
    | . as $v | [ "example.com/environment","example.com/support-level","example.com/dr-tier","example.com/os"
                  | select(($v.metadata.labels // {})[.] // "" | . == "") ]
      + [ "example.com/application","example.com/charging-account","example.com/created-by","example.com/owner-department",
          "example.com/owner-department-contact","example.com/support-department","example.com/support-department-contact"
          | select(($v.metadata.annotations // {})[.] // "" | . == "") ]
    | select(length > 0) | "\($v.metadata.namespace)/\($v.metadata.name): \(join(", "))"'
  ```

## Moving to Deny

When the Corp templates are in use and the report shows no untagged VMs created by people (migrated VMs do not matter,
MTV is never blocked):

1. `policies/site-values/ocp-a.yaml` (and `ocp-b.yaml`): `vmTagEnforcement: "Deny"`.
2. Commit, push, sync `policies`.
3. Check: `oc $W get validatingadmissionpolicybinding vm-tags -o jsonpath='{.spec.validationActions}'` shows
   `["Deny","Audit"]`. Test by creating a VM from YAML without tags: it is refused with the message above.

Back to `Warn` the same way if something unexpected is blocked.

## Changing the rules

- **Allowed values** (a new environment, support level or DR tier): edit the value lists in validations 2–4 of
  `policies/manifests/vm-tagging/vm-tagging.yaml`, the same lists in `scripts/tag-vm.sh` (`check`), and the parameter
  descriptions in the Corp templates.
- **A new required tag:** add it to `missingLabels` or `missingAnnotations` in the admission policy, to `$reqL`/`$reqA` in
  the report, to `KEY` in `scripts/tag-vm.sh`, and as a parameter in each Corp template.
- **More templates** (Windows, RHEL 8): copy the tag parameters and the `example.com/*` lines from
  `corp-rhel9-server-small.yaml`, with `example.com/os` fixed to the template's OS.
