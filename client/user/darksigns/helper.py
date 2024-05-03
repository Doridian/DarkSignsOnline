#!/usr/bin/env python3

from dataclasses import dataclass, field
from os.path import exists, join as path_join
from os import listdir, getenv

# Change this to where you have DarkSigns installed
DARKSIGNS_INSTALL_PATH = path_join(getenv("USERPROFILE"), "Applications/Dark Signs")

# Do not change these unless you know what you're doing
DARKSIGNS_SERVERS = path_join(DARKSIGNS_INSTALL_PATH, "Data/Profiles/darksigns")
DARKSIGNS_SOURCE = path_join(DARKSIGNS_SERVERS, "Programs/uncompiled")

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
        return exists(path_join(DARKSIGNS_SOURCE, f"{self.name}.dsu"))

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
        with open(path_join(DARKSIGNS_SERVERS, f"{ip}.svf"), "r") as f:
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

        if ip == "23.23.1.91" and host == "zrio.org" and 45 not in ports:
            print(f"Missing port 45 for zrio.org. Adding it in...")
            print("WARNING: You might want to fix this! Your Dark Signs main mission is unplayable like this")
            ports[45] = DSScript.get("xcapro")

        return DSServer(ip=ip, host=host, ports=ports, trace=trace)
 
def load_servers() -> list[DSServer]:
    with open(path_join(DARKSIGNS_SERVERS, "index.dsh"), "r") as f:
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
    # darksoft_http.dsu is missing from the game, it is only present in compiled form
    # You can grab the decompiled version from the following link:
    # https://gist.github.com/Doridian/baeac1e3c80008115fd353c77f3de03b

    ds_ok = True
    for ds_script in all_ds_scripts.values():
        if not ds_script.has_ds():
            print("[CRITICAL] Missing DS script source", ds_script.name)
            ds_ok = False

    if not ds_ok:
        raise ValueError(f"DS scripts are missing. Please put them in {DARKSIGNS_SOURCE}")

    print("DS scripts are OK")

    ds_ok = True
    for ds_script in all_ds_scripts.values():
        if not ds_script.has_dso():
            print("[WARNING] Missing DSO script conversion", ds_script.name)
            ds_ok = False

    if not ds_ok:
        raise ValueError("DSO scripts are missing")

    print("DSO scripts are OK")

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
    print("Option Explicit")
    print("Sub UploadSecure(Domain, Port, File)")
    print("    Dim strData")
    print("    strData = Display(File)")
    print("    strData = CompileStr(strData)")
    print("    WaitFor UploadStr(Domain, Port, strData)")
    print("End Sub")

    for server in servers:
        for port, script in server.ports.items():
            print(f"Say \"Uploading {script.name}.ds to {server.ip}:{port}\"")
            print(f"UploadSecure \"{server.ip}\", {port}, \"/darksigns/mission_scripts/{script.name}.ds\"")
            print(f"Say \"Uploaded {script.name}.ds to {server.ip}:{port}\"")

    bPath = "remotefs"
    for dom in listdir(bPath):
        for f in listdir(path_join(bPath, dom)):
            print(f"Say \"Uploading {f} to {dom}\"")
            print(f"Run \"RemoteUpload\", \"{dom}\", \"{f}\", \"/darksigns/remotefs/{dom}/{f}\"")
            print(f"Say \"RemoteUploaded {f} to {dom}\"")

    bPath = "dso_specific"
    for scr in listdir(bPath):
        host, port = scr.removesuffix(".ds").split("___")
        print(f"Say \"Uploading {scr} to {host}:{port}\"")
        print(f"UploadSecure \"{host}\", {port}, \"/darksigns/dso_specific/{scr}\"")
        print(f"Say \"Uploaded {scr} to {host}:{port}\"")

# Generate all traceroute files for traceroute.dsn
def dso_upload_traceroutes():
    print("Dim sTrace")
    for server in servers:
        if not server.trace:
            continue
        print(f"sTrace = \"allowlist=fileserver\" & vbCrLf")
        for trace in server.trace:
            print(f"sTrace = sTrace & \"{trace}\" & vbCrLf")
        print(f"PrintVar RemoteWrite(\"traceroute.dsn\", \"{server.ip}.trace\", sTrace)")

# Generate all ipscan files for ipscan.dsn
def dso_upload_ipscans():
    print("Dim sScan")
    print(f"sScan = \"allowlist=fileserver\" & vbCrLf")
    for server in servers:
        print(f"sScan = sScan & \"{server.ip}\" & vbCrLf")
    print(f"PrintVar RemoteWrite(\"ipscan.dsn\", \"ip.list\", sScan)")

# Generate all portscan files for portscan.dsn
def dso_upload_portscans():
    print("Dim sScan")
    for server in servers:
        print(f"sScan = \"allowlist=fileserver\" & vbCrLf")
        for port, dsc in server.ports.items():
            print(f"sScan = sScan & \"{port}={dsc.name}\"  & vbCrLf")
        print(f"PrintVar RemoteWrite(\"portscan.dsn\", \"{server.ip}.ports\", sScan)")

dso_uploadscript()
