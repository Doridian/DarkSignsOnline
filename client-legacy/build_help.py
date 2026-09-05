#!/usr/bin/env python3

from dataclasses import dataclass
from os import listdir

DOT_DS = ".ds"

@dataclass(kw_only=True, eq=True)
class DSArg:
    name: str
    arg_type: str
    optional: bool
    default_value: str | None

    def format(self) -> str:
        res = self.name
        attribs = []
        if self.arg_type.lower() != "variant":
            attribs.append(self.arg_type)
        if self.default_value:
            attribs.append("Default=" + self.default_value)
        if attribs:
            res += "[" + ",".join(attribs) + "]"
        if self.optional:
            res = "<" + res + ">"
        return res

@dataclass(kw_only=True, eq=True)
class DSProp:
    name: str
    prop_type: str
    limitations_get: list[str]
    limitations_let: list[str]
    docs_get: str
    docs_let: str
    has_get: bool
    has_let: bool

@dataclass(kw_only=True, eq=True)
class DSFunc:
    name: str
    args: list[DSArg]
    return_type: str | None
    docs: str
    limitations : list[str]

def process_vb_function_decl(prefix: str, i: int, lines: list[str], always_add_limits: list[str], scan_docs_backward: bool = False) -> DSFunc | None:
    line = lines[i].strip()
    if not line.lower().startswith(prefix):
        return None

    funcdef = line[len(prefix):].strip()

    idx = funcdef.find("(")
    if idx == -1:
        print("Skipping ", line)
        return None
    name = funcdef[:idx]
    args: list[DSArg] = []
    argstr = funcdef[idx+1:]
    idx = argstr.find(")")
    if idx == -1:
        print("Skipping ", line)
        return None
    funcdef = argstr[idx+1:]
    argstr = argstr[:idx].strip()

    funcdef = funcdef.replace("()", "[]")
    argstr = argstr.replace("()", "[]")

    func_limits: list[str] = []
    if always_add_limits:
        func_limits += always_add_limits
    if not scan_docs_backward:
        limiterline = lines[i+1].strip().lower()
        if limiterline == "assertlocalonly":
            func_limits.append("Can only be used locally (local script or CLI)")
        elif limiterline == "assertremoteonly":
                func_limits.append("Can only be used remotely (on a server/domain)")

    args_raw = argstr.split(",")
    for arg in args_raw:
        arg = arg.strip()
        if not arg:
            continue

        arg_type = "Variant"
        arg_name = ""
        arg_optional = False
        arg_default_value: str | None = None
        arg_is_vararg = False

        next_is_type = False
        next_is_default = False

        arg_parts = arg.split(" ")
        for part in arg_parts:
            if not part:
                continue

            partl = part.lower()

            if next_is_type:
                arg_type = part
                next_is_type = False
                continue

            if next_is_default:
                arg_default_value = part
                next_is_default = False
                continue

            if partl == "byval" or partl == "byref":
                continue
            elif partl == "optional":
                arg_optional = True
                continue
            elif partl == "paramarray":
                arg_is_vararg = True
                continue
            elif partl == "as":
                next_is_type = True
                continue
            elif partl == "=": # In theory, defaults can contain spaces (or commas), but we're not going to handle that
                next_is_default = True
                continue

            arg_name = part

        if "[]" in arg_name:
            arg_name = arg_name.removesuffix("[]")
            arg_type += "()"

        if arg_is_vararg:
            arg_name = arg_name + "..."

        args.append(DSArg(name=arg_name, arg_type=arg_type, optional=arg_optional, default_value=arg_default_value))

    func_return = ""
    if funcdef:
        next_is_type = False
        fdsplit = funcdef.split(" ")
        for part in fdsplit:
            if not part:
                continue
            if part.lower() == "as":
                next_is_type = True
            elif next_is_type:
                func_return = part
                break

    vbtype_overrides: dict[str, str] = {}

    func_docs = ""
    if scan_docs_backward:
        j = 0
    else:
        j = i
    linecnt = len(lines)
    while True:
        if scan_docs_backward:
            j += 1
            if j >= linecnt:
                break
        else:
            j -= 1
            if j < 0:
                break

        jline = lines[j].strip()
        if jline.startswith("'"):
            jlcur = jline[1:].strip()
            if jlcur.lower().startswith("vbtype:"):
                vbtcur = jlcur[7:].strip()
                vbtspl = vbtcur.split("=")
                if len(vbtspl) == 2:
                    vbtype_overrides[vbtspl[0].strip()] = vbtspl[1].strip()
                else:
                    raise ValueError(f"Invalid VBType override: {vbtcur}")
                continue
            elif jlcur.lower() == "vbnodoc":
                return None

            if jlcur.lower().startswith("example #"):
                jlcur = "{{lgreen 12}}" + jlcur
            if scan_docs_backward:
                func_docs += jlcur + "\r\n"
            else:
                func_docs = jlcur + "\r\n" + func_docs
        else:
            break
    
    if "_RETURN" in vbtype_overrides:
        func_return = vbtype_overrides["_RETURN"]

    for arg in args:
        if arg.name in vbtype_overrides:
            arg.arg_type = vbtype_overrides[arg.name]
    
    func_return = func_return.replace("[]", "()")

    return DSFunc(name=name, args=args, return_type=func_return, docs=func_docs, limitations=func_limits)

F_PREFIX = "public function "
S_PREFIX = "public sub "
PG_PREFIX = "public property get "
PL_PREFIX = "public property let "

def process_vb_file(file: str, always_add_limits: list[str] | None = None) -> tuple[list[DSFunc], list[DSProp]]:
    if not always_add_limits:
        always_add_limits = []
    res: list[DSFunc] = []
    props: dict[str, DSProp] = {}
    with open(file, "r") as f:
        lines = f.readlines()
    for i in range(len(lines)):
        line_decl = process_vb_function_decl(F_PREFIX, i, lines, always_add_limits)
        if line_decl:
            if not line_decl.return_type:
                line_decl.return_type = "Variant"
            res.append(line_decl)
            continue

        line_decl = process_vb_function_decl(S_PREFIX, i, lines, always_add_limits)
        if line_decl:
            res.append(line_decl)
            continue

        line_decl = process_vb_function_decl(PG_PREFIX, i, lines, always_add_limits)
        if line_decl:
            if line_decl.name in props:
                props[line_decl.name].docs_get = line_decl.docs
                props[line_decl.name].has_get = True
                props[line_decl.name].limitations_get = line_decl.limitations
            else:
                props[line_decl.name] = DSProp(name=line_decl.name, prop_type=line_decl.return_type, limitations_get=line_decl.limitations, limitations_let=[], docs_get=line_decl.docs, docs_let="", has_get=True, has_let=False)
            continue

        line_decl = process_vb_function_decl(PL_PREFIX, i, lines, always_add_limits)
        if line_decl:
            if line_decl.name in props:
                props[line_decl.name].docs_let = line_decl.docs
                props[line_decl.name].has_let = True
                props[line_decl.name].limitations_let = line_decl.limitations
            else:
                props[line_decl.name] = DSProp(name=line_decl.name, prop_type=line_decl.return_type, limitations_let=line_decl.limitations, limitations_get=[], docs_get="", docs_let=line_decl.docs, has_get=False, has_let=True)
            continue

    return res, list(props.values())

def vbesc(instr: str | None) -> str:
    if instr is None:
        return ""
    if "\n" in instr or "\r" in instr:
        raise ValueError("Newlines not supported")
    return instr.replace('"', '""')

B_PROPS = "{{green 12}}"

def make_func_help_file(func: DSFunc) -> str:
    res: list[str] = []
    res.append("Option Explicit")
    res.append(f'Say "{B_PROPS}Function: {vbesc(func.name)}({vbesc(", ".join([arg.format() for arg in func.args]))}) -> {vbesc(func.return_type) or "Nothing"}"')
    lred = "{{lred}}"
    for limit in func.limitations:
        res.append(f'Say "{lred}Restriction: {vbesc(limit)}"')

    if func.docs:
        for doc in func.docs.strip().split("\r\n"):
            res.append(f'Say "{vbesc(doc)}"')

    return "\r\n".join(res) + "\r\n"

def make_command_help_file(func: DSFunc) -> str:
    res: list[str] = []
    res.append("Option Explicit")
    if func.args:
        res.append(f'Say "{B_PROPS}Command: {vbesc(func.name)} {vbesc(" ".join([arg.format() for arg in func.args]))}"')
    else:
        res.append(f'Say "{B_PROPS}Command: {vbesc(func.name)}"')
    lred = "{{lred}}"
    for limit in func.limitations:
        res.append(f'Say "{lred}Restriction: {vbesc(limit)}"')

    if func.docs:
        for doc in func.docs.strip().split("\r\n"):
            res.append(f'Say "{vbesc(doc)}"')

    return "\r\n".join(res) + "\r\n"

E_PROPS = "{{lgreen 12}}"

def make_prop_help_file(prop: DSProp) -> str:
    res: list[str] = []
    res.append("Option Explicit")
    res.append(f'Say "{B_PROPS}Property: {vbesc(prop.name)}[{vbesc(prop.prop_type)}]"')
    if prop.has_get:
        res.append(f'Say "{E_PROPS}Example read: SomeVar = {vbesc(prop.name)}"')
    if prop.has_let:
        res.append(f'Say "{E_PROPS}Example write: {vbesc(prop.name)} = SomeVar"')

    yellow = "{{yellow}}"
    lgreen = "{{lgreen}}"
    lred = "{{lred}}"

    mode_name = ""
    if prop.has_get and prop.has_let:
        mode_name = "Read/Write"
    elif prop.has_get:
        mode_name = "Read-Only"
    elif prop.has_let:
        mode_name = "Write-Only"

    if prop.has_get:
        res.append(f"Say \"{yellow}Access level: {mode_name}\"")

    for limit in prop.limitations_get:
        res.append(f'Say "{lred}READ restriction: {vbesc(limit)}"')
    for limit in prop.limitations_let:
        res.append(f'Say "{lred}WRITE restriction: {vbesc(limit)}"')

    if prop.has_get and prop.docs_get:
        res.append(f"Say \"{lgreen}Help for reading\"")
        for doc in prop.docs_get.strip().split("\r\n"):
            res.append(f'Say "{vbesc(doc)}"')

    if prop.has_get and prop.docs_let:
        res.append(f"Say \"{lgreen}Help for writing\"")
        for doc in prop.docs_get.strip().split("\r\n"):
            res.append(f'Say "{vbesc(doc)}"')

    return "\r\n".join(res) + "\r\n"

ALL_FUNCS: list[DSFunc] = []
ALL_PROPS: list[DSProp] = []
f, p = process_vb_file("clsScriptFunctions.cls")
ALL_FUNCS += f
ALL_PROPS += p
f, p = process_vb_file("clsScriptTermlib.cls", ["Must be loaded with: DLOpen \"termlib\""])
ALL_FUNCS += f
ALL_PROPS += p

for func in ALL_FUNCS:
    lfunc = func.name.lower()

    with open(f"./user/system/commands/help/functions/{lfunc}.ds", "wb") as f:
        f.write(make_func_help_file(func).encode("latin1"))

for prop in ALL_PROPS:
    lprop = prop.name.lower()

    with open(f"./user/system/commands/help/properties/{lprop}.ds", "wb") as f:
        f.write(make_prop_help_file(prop).encode("latin1"))

C_PREFIX = "'commanddefinition"
for cmd in listdir("./user/system/commands"):
    if not cmd.endswith(DOT_DS):
        continue
    with open(f"./user/system/commands/{cmd}", "r") as f:
        lines = f.readlines()

    dfnc: DSFunc | None = None
    line = lines[0].strip()
    if not line.lower().startswith(C_PREFIX):
        continue

    line = f"{C_PREFIX} {cmd.removesuffix(DOT_DS).upper()}{line[len(C_PREFIX):].strip()}"
    lines[0] = line
    dfnc = process_vb_function_decl(C_PREFIX, 0, lines, [], True)

    if not dfnc:
        print(f"Failed to process {cmd}")

    if dfnc is not None:
        with open(f"./user/system/commands/help/commands/{cmd}", "wb") as f:
            f.write(make_command_help_file(dfnc).encode("latin1"))
