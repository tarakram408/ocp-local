#!/usr/bin/env python3
"""Set rootDeviceHints and static-network installerArgs on every node of a ClusterInstance.

FALLBACK ONLY, not for normal installs. When every blade boots one shared discovery ISO (manual vKVM mount,
30 Oct), the node's static network is not carried onto the installed disk and the node cannot fetch Ignition
after its first reboot. --append-karg puts the same network on the kernel command line. It duplicates
nodeNetwork, so remove the installerArgs lines again once the install is done.
Usage: python3 scripts/set-node-kargs.py clusters/<cluster>/clusterinstance.yaml [...]
"""
import ipaddress, json, re, sys

DISK = "/dev/disk/by-path/pci-0000:04:00.0-ata-1.0"   # 240 GB boot drive, confirmed on all ocp-a blades 30 Oct


def kargs(block):
    vlan = re.search(r"- name: (bond\d+\.\d+)\s*(?:#.*)?\n\s+type: vlan", block)
    bond = re.search(r"- name: (bond\d+)\s*(?:#.*)?\n\s+type: bond", block)
    ports = re.search(r"port:\s*\n((?:\s+- \S+\s*(?:#.*)?\n)+)", block)
    ip = re.search(r"- ip: (\S+)\s*(?:#.*)?\n\s+prefix-length: (\d+)", block)
    gw = re.search(r"next-hop-address: (\S+)", block)
    dns = re.search(r"server:\s*\n((?:\s+- \S+\s*(?:#.*)?\n)+)", block)
    if not (bond and ports and ip and gw and dns):
        raise SystemExit("could not parse node network:\n" + block[:200])
    mask = str(ipaddress.ip_network(f"0.0.0.0/{ip.group(2)}").netmask)
    dev = vlan.group(1) if vlan else bond.group(1)
    a = [f"ip={ip.group(1)}::{gw.group(1)}:{mask}::{dev}:none",
         f"bond={bond.group(1)}:{','.join(re.findall(r'- (\S+)', ports.group(1)))}:mode=active-backup,miimon=100"]
    if vlan:
        a.append(f"vlan={vlan.group(1)}:{bond.group(1)}")
    a += [f"nameserver={s}" for s in re.findall(r"- (\S+)", dns.group(1))]
    out = []
    for x in a:
        out += ["--append-karg", x]
    return json.dumps(out, separators=(",", ":"))


for path in sys.argv[1:]:
    parts = re.split(r"(?m)^(?=    - hostName: )", open(path).read())
    new = [parts[0]]
    for p in parts[1:]:
        p = re.sub(r"(?m)^      installerArgs: .*\n", "", p)
        p = re.sub(r"(?m)^(      rootDeviceHints:\n        deviceName: ).*\n",
                   lambda m: m.group(1) + DISK + "   # boot drive by PCI path\n"
                   + "      installerArgs: '" + kargs(p) + "'   # FALLBACK: static network on the installed disk\n", p)
        new.append(p)
        print(path, re.search(r"hostName: (\S+)", p).group(1), "ok")
    open(path, "w").write("".join(new))
