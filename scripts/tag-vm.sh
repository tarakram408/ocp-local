#!/usr/bin/env bash
# Set the required Corp tags on existing VMs (VMs brought in by MTV, or created before the tag policy).
# Labels for the fixed values, annotations for free text (docs/vm-tagging.md). Does not restart the VM.
#
# List only (no changes): every VM missing tags, which ones, all namespaces (or one):
#   OC="oc $W" scripts/tag-vm.sh --list [namespace]
#
# Interactive (asks for each tag, shows the current value; Enter keeps it):
#   OC="oc $W" scripts/tag-vm.sh                                  # lists VMs missing tags (all namespaces), pick one by number
#   OC="oc $W" scripts/tag-vm.sh virtual-machines vm-test01-linux     # asks for the tags of this VM
#
# One VM, no questions (all on the command line):
#   OC="oc $W" scripts/tag-vm.sh virtual-machines vm-test01-linux \
#     Environment=prd SupportLevel=24x7 DRTier=1 OS=Linux Application="Payroll web" \
#     ChargingAccount=CO01.XX000000.CC0001.PG00001.PJ000001 CreatedBy=vm-test01 \
#     OwnerDepartment="ITS" OwnerDepartmentContact=owner@example.com \
#     SupportDepartment="ITS Linux" SupportDepartmentContact=support@example.com
#   (only the tags given are changed; give all eleven for a VM with none)
#
# A migration wave from a CSV (header row with these column names, any order; namespace and vm are required):
#   namespace,vm,Environment,SupportLevel,DRTier,OS,Application,ChargingAccount,CreatedBy,OwnerDepartment,OwnerDepartmentContact,SupportDepartment,SupportDepartmentContact
#   OC="oc $W" scripts/tag-vm.sh --csv wave-1-tags.csv
# The vSphere tags of the source VMs can be exported to that layout with PowerCLI (Get-TagAssignment).
# Check afterwards: Governance -> Policies -> vm-tagging-report, or
#   oc get vm -A -L example.com/environment,example.com/support-level,example.com/dr-tier,example.com/os
set -euo pipefail
OC=${OC:-oc}

declare -A KEY=(
  [Environment]=label:example.com/environment
  [SupportLevel]=label:example.com/support-level
  [DRTier]=label:example.com/dr-tier
  [OS]=label:example.com/os
  [Application]=annotation:example.com/application
  [ChargingAccount]=annotation:example.com/charging-account
  [CreatedBy]=annotation:example.com/created-by
  [OwnerDepartment]=annotation:example.com/owner-department
  [OwnerDepartmentContact]=annotation:example.com/owner-department-contact
  [SupportDepartment]=annotation:example.com/support-department
  [SupportDepartmentContact]=annotation:example.com/support-department-contact
)

check() {   # tag value -> error message or nothing
  case "$1" in
    Environment)  [[ "$2" =~ ^(sbx|dev|tst|prd)$ ]]       || echo "Environment must be sbx, dev, tst or prd (got '$2')";;
    SupportLevel) [[ "$2" =~ ^(24x7|9x5|Unmanaged)$ ]]    || echo "SupportLevel must be 24x7, 9x5 or Unmanaged (got '$2')";;
    DRTier)       [[ "$2" =~ ^[123]$ ]]                   || echo "DRTier must be 1, 2 or 3 (got '$2')";;
    OS)           [[ "$2" =~ ^[A-Za-z0-9]([A-Za-z0-9._-]{0,61}[A-Za-z0-9])?$ ]] || echo "OS must be a single word such as Windows or Linux (got '$2')";;
  esac
}

canon() {   # tag value -> the value spelled as in the allowed list (case-insensitive match), else unchanged
  local c; for c in ${CHOICES[$1]:-}; do [ "${2,,}" = "${c,,}" ] && { echo "$c"; return; }; done; echo "$2"
}

tag_vm() {  # namespace vm tag=value...
  local ns=$1 vm=$2; shift 2
  local labels=() annots=() errs=0
  for kv in "$@"; do
    local k=${kv%%=*} v=${kv#*=}; v=$(canon "$k" "$v")
    [ -z "$v" ] && continue
    [ -n "${KEY[$k]:-}" ] || { echo "  $ns/$vm: unknown tag '$k' (valid: ${!KEY[*]})" >&2; errs=1; continue; }
    local msg; msg=$(check "$k" "$v"); [ -n "$msg" ] && { echo "  $ns/$vm: $msg" >&2; errs=1; continue; }
    local kind=${KEY[$k]%%:*} key=${KEY[$k]#*:}
    if [ "$kind" = label ]; then labels+=("$key=$v"); else annots+=("$key=$v"); fi
  done
  [ $errs -eq 0 ] || { echo "  $ns/$vm: not changed" >&2; return 1; }
  $OC -n "$ns" get vm "$vm" >/dev/null || return 1
  [ ${#labels[@]} -eq 0 ] || $OC -n "$ns" label vm "$vm" --overwrite "${labels[@]}" >/dev/null
  [ ${#annots[@]} -eq 0 ] || $OC -n "$ns" annotate vm "$vm" --overwrite "${annots[@]}" >/dev/null
  echo "  $ns/$vm: ${#labels[@]} labels, ${#annots[@]} annotations set"
}

ORDER=(Environment SupportLevel DRTier OS Application ChargingAccount CreatedBy OwnerDepartment OwnerDepartmentContact SupportDepartment SupportDepartmentContact)
declare -A CHOICES=([Environment]="sbx dev tst prd" [SupportLevel]="24x7 9x5 Unmanaged" [DRTier]="1 2 3" [OS]="Linux Windows")
declare -A HINT=([ChargingAccount]="e.g. CO01...XX000000.CC0001.PG00001.PJ000001..." [CreatedBy]="NetID"
                 [OwnerDepartmentContact]="e-mail" [SupportDepartmentContact]="e-mail")

ask() {     # ask VAR "question" default: line editing (arrows, backspace) on the terminal; Enter keeps the default
  local __a=""
  read -e -r -p "$2" __a <&3 || true
  printf -v "$1" '%s' "${__a:-$3}"
}

missing_vms() {   # [namespace] -> "ns<TAB>vm<TAB>count<TAB>missing keys" for VMs missing at least one tag (all namespaces if none)
  local scope=(-A); [ -n "${1:-}" ] && scope=(-n "$1")
  $OC get vm "${scope[@]}" -o json | jq -r '.items[] | . as $v
    | select(.metadata.namespace | startswith("openshift") | not)
    | ([ "example.com/environment","example.com/support-level","example.com/dr-tier","example.com/os"
         | select(($v.metadata.labels // {})[.] // "" | . == "") ]
     + [ "example.com/application","example.com/charging-account","example.com/created-by","example.com/owner-department",
         "example.com/owner-department-contact","example.com/support-department","example.com/support-department-contact"
         | select(($v.metadata.annotations // {})[.] // "" | . == "") ])
    | select(length > 0)
    | [$v.metadata.namespace, $v.metadata.name, (length|tostring), (map(sub("^example.com/";"")) | join(","))] | @tsv'
}

list_missing() {  # [namespace] -> numbered table; sets LIST_NS / LIST_VM arrays
  LIST_NS=(); LIST_VM=()
  local rows; rows=$(missing_vms "${1:-}")
  if [ -z "$rows" ]; then echo "All VMs carry every Corp tag (nothing to do)."; return 1; fi
  printf "  %-3s %-20s %-28s %-8s %s\n" "#" NAMESPACE VM MISSING TAGS
  local i=0 ns vm n keys
  while IFS=$'\t' read -r ns vm n keys; do
    i=$((i+1)); LIST_NS+=("$ns"); LIST_VM+=("$vm")
    [ "$n" = 11 ] && keys="all"
    printf "  %-3s %-20s %-28s %-8s %s\n" "$i" "$ns" "$vm" "$n/11" "$keys"
  done <<<"$rows"
  echo "  $i VM(s) not compliant."
}

interactive() {   # [namespace] [vm]
  local ns=${1:-} vm=${2:-}
  [ -e /dev/fd/3 ] || exec 3<"${TAG_VM_TTY:-/dev/tty}"   # answers come from the terminal, also when stdout is piped
  if [ -z "$vm" ]; then
    echo "VMs missing Corp tags${ns:+ in $ns}:"
    list_missing "$ns" || return 1
    local pick; ask pick "Number or VM name to tag (Enter to quit): " ""
    [ -n "$pick" ] || return 1
    if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le ${#LIST_VM[@]} ]; then
      ns=${LIST_NS[$((pick-1))]}; vm=${LIST_VM[$((pick-1))]}
    else
      vm=$pick
      if [ -z "$ns" ]; then
        local k; for k in "${!LIST_VM[@]}"; do [ "${LIST_VM[$k]}" = "$vm" ] && ns=${LIST_NS[$k]}; done
        [ -n "$ns" ] || ask ns "Namespace of $vm [virtual-machines]: " virtual-machines
      fi
    fi
  fi
  local json; json=$($OC -n "$ns" get vm "$vm" -o json) || exit 1
  echo; echo "Tags for $ns/$vm (Enter keeps the current value shown in [ ]):"
  local args=() k cur v kind key
  for k in "${ORDER[@]}"; do
    kind=${KEY[$k]%%:*}; key=${KEY[$k]#*:}
    if [ "$kind" = label ]; then cur=$(jq -r --arg k "$key" '.metadata.labels[$k] // ""' <<<"$json")
    else cur=$(jq -r --arg k "$key" '.metadata.annotations[$k] // ""' <<<"$json"); fi
    while true; do
      if [ -n "${CHOICES[$k]:-}" ]; then
        ask v "  $k (${CHOICES[$k]// /, }) [$cur]: " "$cur"
      else
        ask v "  $k${HINT[$k]:+ (${HINT[$k]})} [$cur]: " "$cur"
      fi
      if [ -z "$v" ]; then echo "    required" >&2; continue; fi
      if [ -n "${CHOICES[$k]:-}" ]; then          # same spelling for everyone: linux -> Linux, PRD -> prd
        local c; for c in ${CHOICES[$k]}; do [ "${v,,}" = "${c,,}" ] && v=$c; done
      fi
      msg=$(check "$k" "$v"); [ -z "$msg" ] && break; echo "    $msg" >&2
    done
    args+=("$k=$v")
  done
  echo; echo "About to set on $ns/$vm:"; printf '  %s\n' "${args[@]}"
  local ok; ask ok "Apply? [y/N]: " n
  [[ "$ok" =~ ^[Yy] ]] || { echo "Nothing changed (answer y to apply)"; return 0; }
  tag_vm "$ns" "$vm" "${args[@]}"
}

if [ "${1:-}" = "--csv" ]; then
  f=${2:?CSV file}; fails=0
  while IFS=$'\x1f' read -r -a row; do
    tag_vm "${row[@]}" || fails=$((fails+1))
  done < <(python3 -c '
import csv, sys
rows = csv.DictReader(open(sys.argv[1], newline="", encoding="utf-8-sig"))
for r in rows:
    ns, vm = (r.pop("namespace", "") or "").strip(), (r.pop("vm", "") or "").strip()
    if not ns or not vm: continue
    print("\x1f".join([ns, vm] + [k.strip() + "=" + (v or "").strip() for k, v in r.items() if k]))
' "$f")
  [ $fails -eq 0 ] || { echo "$fails VM(s) not tagged, see above" >&2; exit 1; }
elif [ "${1:-}" = "--list" ] || [ "${1:-}" = "-l" ]; then
  echo "VMs missing Corp tags${2:+ in $2}:"; list_missing "${2:-}" || true
elif [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,30p' "$0"
elif [ $# -le 1 ]; then
  # no VM named: list, pick, tag, then show the list again until Enter
  while interactive "${1:-}"; do echo; done
elif [ $# -eq 2 ]; then
  interactive "$@"
else
  tag_vm "$@"
fi
