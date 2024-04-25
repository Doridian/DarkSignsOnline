#!/usr/bin/env python3

from dataclasses import dataclass
from os.path import exists

@dataclass(kw_only=True, eq=True)
class DSArg:
    name: str
    arg_type: str
    optional: bool
    default_value: str | None

    def format(self) -> str:
        res = self.name
        if self.default_value:
            res += " = " + self.default_value
        if self.arg_type.lower() != "variant":
            res += " [" + self.arg_type + "]"
        if self.optional:
            res = "<" + res + ">"

@dataclass(kw_only=True, eq=True)
class DSFunc:
    name: str
    args: list[DSArg]
    return_type: str | None
    docs: str
    limitations : list[str]

F_PREFIX = "public function "
def process_vb_file(file: str, always_add_limits: list[str] | None = None) -> list[DSFunc]:
    res: list[DSFunc] = []
    with open(file, "r") as f:
        lines = f.readlines()
    for i, line in enumerate(lines):
        line = line.strip()
        if not line.lower().startswith(F_PREFIX):
            continue

        funcdef = line[len(F_PREFIX):].strip()

        funcdef = funcdef.replace("()", "[]")
        idx = funcdef.find("(")
        if idx == -1:
            continue
        name = funcdef[:idx]
        args: list[DSArg] = []
        argstr = funcdef[idx+1:]
        idx = argstr.find(")")
        if idx == -1:
            continue
        funcdef = argstr[idx+1:]
        argstr = argstr[:idx].strip()

        func_limits: list[str] = []
        if always_add_limits:
            func_limits += always_add_limits
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
        j = i
        while j > 0:
            j -= 1
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

                if jlcur.lower().startswith("Example #"):
                    jlcur = "{{lgreen 12}}" + jlcur
                func_docs = jlcur + "\r\n" + func_docs
            else:
                break

        func_return = func_return.replace("[]", "()")
        
        if "_RETURN" in vbtype_overrides:
            func_return = vbtype_overrides["_RETURN"]

        for arg in args:
            if arg.name in vbtype_overrides:
                arg.arg_type = vbtype_overrides[arg.name]

        res.append(DSFunc(name=name, args=args, return_type=func_return, docs=func_docs, limitations=func_limits))
    return res

def vbesc(instr: str | None) -> str:
    if instr is None:
        return ""
    if "\n" in instr or "\r" in instr:
        raise ValueError("Newlines not supported")
    return instr.replace('"', '""')

def make_help_file(func: DSFunc) -> str:
    res: list[str] = []
    res.append("Option Explicit")
    res.append(f'Say props & "Function: {vbesc(func.name)}({vbesc(", ".join([f"{arg.name} [{arg.arg_type}]" for arg in func.args]))})"')
    res.append(f'Say props & "Returns: {vbesc(func.return_type) or "Nothing"}"')
    lred = "{{lred}}"
    for limit in func.limitations:
        res.append(f'Say "{lred}Restriction: {vbesc(limit)}"')

    if func.docs:
        for doc in func.docs.strip().split("\r\n"):
            res.append(f'Say "{vbesc(doc)}"')

    return "\r\n".join(res) + "\r\n"

ALL_FUNCS: list[DSFunc] = []
ALL_FUNCS += process_vb_file("clsScriptFunctions.cls")
ALL_FUNCS += process_vb_file("clsScriptTermlib.cls", ["Must be loaded with: DLOpen \"termlib\""])

for func in ALL_FUNCS:
    lfunc = func.name.lower()

    if exists(f"./user/system/commands/{lfunc}.ds"):
        print("Skipping docs for", func.name)
        continue

    with open(f"./user/system/commands/help/{lfunc}.ds", "wb") as f:
        f.write(make_help_file(func).encode("latin1"))
