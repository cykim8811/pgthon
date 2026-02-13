#!/usr/bin/env python3
"""Pgthon CLI — Compile Python and execute it on PostgreSQL."""

import json
import subprocess
import sys
import types


def serialize_const(value):
    """Serialize a Python constant to the JSONB format py_run expects."""
    if value is None:
        return {"type": "none"}
    if isinstance(value, bool):
        return {"type": "bool", "value": value}
    if isinstance(value, int):
        return {"type": "int", "value": value}
    if isinstance(value, float):
        return {"type": "float", "value": value}
    if isinstance(value, str):
        return {"type": "str", "value": value}
    if isinstance(value, bytes):
        return {"type": "bytes", "value": value.hex()}
    if isinstance(value, tuple):
        return {"type": "tuple", "items": [serialize_const(item) for item in value]}
    if isinstance(value, types.CodeType):
        return {"type": "code", "value": serialize_code(value)}
    if value is Ellipsis:
        return {"type": "none"}
    if isinstance(value, frozenset):
        return {"type": "none"}
    return {"type": "none"}


def serialize_code(code):
    """Serialize a Python code object to the JSONB format py_run expects."""
    return {
        "bytecode": code.co_code.hex(),
        "consts": [serialize_const(c) for c in code.co_consts],
        "names": list(code.co_names),
        "varnames": list(code.co_varnames),
        "cellvars": list(code.co_cellvars),
        "freevars": list(code.co_freevars),
        "argcount": code.co_argcount,
        "nlocals": code.co_nlocals,
        "stacksize": code.co_stacksize,
        "flags": code.co_flags,
        "name": code.co_name,
        "filename": "<pgthon>",
        "exceptiontable": code.co_exceptiontable.hex() if code.co_exceptiontable else None,
    }


def format_result(response):
    """Format the py_run JSONB response for display."""
    if response.get("error") and response["error"] is not None:
        err = response["error"]
        return f'{err["type"]}: {err["message"]}'

    result = response.get("result")
    globals_ = response.get("globals", {})
    parts = []

    # Show globals (exec mode side effects)
    if globals_:
        for name, obj in globals_.items():
            parts.append(f"{name} = {format_value(obj)}")

    # Show result if not None
    if result and result.get("type") != "none":
        parts.append(format_value(result))

    return "\n".join(parts) if parts else ""


def format_value(obj):
    """Format a serialized py_object for display."""
    t = obj.get("type")
    if t == "none":
        return "None"
    if t == "bool":
        return "True" if obj["value"] else "False"
    if t == "int":
        return str(obj["value"])
    if t == "float":
        v = obj["value"]
        return str(v) if v != int(v) else f"{v:.1f}"
    if t == "str":
        return repr(obj["value"])
    if t == "list":
        items = ", ".join(format_value(item) for item in obj.get("items", []))
        return f"[{items}]"
    if t == "tuple":
        items = ", ".join(format_value(item) for item in obj.get("items", []))
        if len(obj.get("items", [])) == 1:
            return f"({items},)"
        return f"({items})"
    if t == "dict":
        entries = obj.get("entries", {})
        pairs = ", ".join(f"{k}: {format_value(v)}" for k, v in entries.items())
        return "{" + pairs + "}"
    if t == "object":
        return obj.get("repr", "<object>")
    return str(obj)


def run_sql(sql):
    """Execute SQL via docker compose exec psql and return the result."""
    result = subprocess.run(
        ["docker", "compose", "exec", "-T", "postgres",
         "psql", "-U", "postgres", "-t", "-A", "-c", sql],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"psql error: {result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def execute(source, mode="exec"):
    """Compile Python source, send to PostgreSQL, return formatted result."""
    code = compile(source, "<pgthon>", mode)
    payload = serialize_code(code)
    payload["mode"] = mode

    sql = f"SELECT py_run('{json.dumps(payload)}'::jsonb);"
    raw = run_sql(sql)
    response = json.loads(raw)
    return format_result(response)


def repl():
    """Interactive REPL."""
    print("Pgthon — Python on PostgreSQL")
    print('Type "exit" or Ctrl-D to quit.\n')

    while True:
        try:
            source = input(">>> ")
        except (EOFError, KeyboardInterrupt):
            print()
            break

        source = source.strip()
        if not source or source == "exit":
            break

        # Multi-line input: if line ends with ':', keep reading
        while source.endswith(":") or source.endswith("\\"):
            try:
                line = input("... ")
            except (EOFError, KeyboardInterrupt):
                print()
                break
            if line == "":
                break
            source += "\n" + line

        try:
            # Try eval first (expressions), fall back to exec (statements)
            try:
                result = execute(source, mode="eval")
            except SyntaxError:
                result = execute(source, mode="exec")

            if result:
                print(result)
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)


def main():
    if len(sys.argv) > 1:
        source = " ".join(sys.argv[1:])
        try:
            result = execute(source, mode="eval")
        except SyntaxError:
            result = execute(source, mode="exec")
        if result:
            print(result)
    else:
        repl()


if __name__ == "__main__":
    main()
