#!/usr/bin/env python3

from dataclasses import dataclass, field
from os.path import exists, join as path_join
from os import mkdir, listdir
from shutil import copy, rmtree

all_ds_scripts: dict[str, "DSScript"] = {}
@dataclass(kw_only=True, frozen=True, eq=True)
class DSScript:
    name: str

    @staticmethod
    def get(name: str) -> "DSScript":
        global all_ds_scripts

        if name not in all_ds_scripts:
            all_ds_scripts[name] = DSScript(name=name)
        return all_ds_scripts[name]

    def has_ds(self) -> bool:
        return exists(f"DS_scr/{self.name}.dsu")

    def has_dso(self) -> bool:
        return exists(f"mission_scripts/{self.name}.ds")

@dataclass(kw_only=True, frozen=True, eq=True)
class DSServer:
    ip: str
    host: str
    ports: dict[int, DSScript] = field(default_factory=dict)
    trace: list[str] = field(default_factory=list)

    @staticmethod
    def load(ip: str, host: str) -> "DSServer":
        with open(f"DS_srv/{ip}.svf", "r") as f:
            svf_lines = f.readlines()

        ports: dict[int, str] = {}
        raw_trace: dict[int, str] = {}

        for line in svf_lines:
            line = line.strip()
            if not line:
                continue

            if "%" not in line:
                continue

            resType, b = line.split("%")
            if resType == "port":
                port, name = b.split("#")

                port = port.strip()
                name = name.strip()

                ports[int(port)] = DSScript.get(name)
            elif resType.startswith("trace"):
                trace_idx = int(resType.removeprefix("trace")) - 1
                raw_trace[trace_idx] = b

        trace = []
        for v in sorted(raw_trace.keys()):
            trace.append(raw_trace[v])

        return DSServer(ip=ip, host=host, ports=ports, trace=trace)
 
def load_servers() -> list[DSServer]:
    with open("DS_srv/index.dsh", "r") as f:
        lines = f.readlines()
    
    servers: list[DSServer] = []
    for line in lines:
        if not line:
            line = line.strip()
            continue

        _, b = line.split("%")
        ip, host = b.split("#")

        host = host.lower()
        host = host.strip()
        ip = ip.strip()

        hostsplit = host.split(".")
        if len(hostsplit) < 2:
            raise ValueError("Invalid domain name")

        srv = DSServer.load(ip=ip, host=host)
        servers.append(srv)

    return servers

servers = load_servers()

# Call this function to check DS script conversion
def dso_convert_check():
    ds_ok = True
    for ds_script in all_ds_scripts.values():
        if not ds_script.has_ds():
            print("[CRITICAL] Missing DS script source", ds_script.name)
            ds_ok = False

    if not ds_ok:
        raise ValueError("DS scripts are missing")

    print("DS scripts are OK")

    try:
        rmtree("DS_scr_todo")
    except:
        pass

    mkdir("DS_scr_todo")

    for ds_script in all_ds_scripts.values():
        if not ds_script.has_dso():
            print("[WARNING] Missing DSO script conversion", ds_script.name)
            copy(f"DS_scr/{ds_script.name}.dsu", f"DS_scr_todo/{ds_script.name}.dsu")

# Call this function to generate a DScript to register all domains
def dso_regdomains():
    domains: dict[str, str] = {}
    sdomains: dict[str, str] = {}
    for server in servers:
        if not server.host:
            domains[server.ip] = "dynamic"
            continue
        spl = server.host.split(".")
        if len(spl) > 2:
            maindom = f"{spl[-2]}.{spl[-1]}"
            if maindom not in domains:
                domains[maindom] = "dynamic"
            sdomains[server.host] = server.ip
        elif len(spl) == 2:
            domains[server.host] = server.ip
        else:
            raise ValueError("Invalid domain name")
    
    for domain, ip in domains.items():
        if ip == "dynamic":
            print(f"PrintVar REGISTER(\"{domain}\")")
        else:
            print(f"PrintVar REGISTER(\"{domain}\", \"{ip}\")")
    for domain, ip in sdomains.items():
        if ip == "dynamic":
            print(f"PrintVar REGISTER(\"{domain}\")")
        else:
            print(f"PrintVar REGISTER(\"{domain}\", \"{ip}\")")
    
# Call this function to generate a script to upload all the DSO scripts to all the servers...
def dso_uploadscript():
    for server in servers:
        for port, script in server.ports.items():
            print(f"PrintVar UPLOAD(\"{server.ip}\", {port}, \"/darksigns/mission_scripts/{script.name}.ds\")")

    bPath = "remotefs"
    for dom in listdir(bPath):
        for f in listdir(path_join(bPath, dom)):
            print(f"Run \"RemoteUpload\", \"{dom}\", \"{f}\", \"/darksigns/remotefs/{dom}/{f}\"")

    bPath = "dso_specific"
    for scr in listdir(bPath):
        host, port = scr.removesuffix(".ds").split("___")
        print(f"PrintVar UPLOAD(\"{host}\", {port}, \"/darksigns/dso_specific/{scr}\")")

dso_uploadscript()
