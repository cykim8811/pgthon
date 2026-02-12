import { getPyodide } from "./pyodide";

export interface CodeObjectJSON {
  bytecode: string;
  consts: any[];
  names: string[];
  varnames: string[];
  cellvars: string[];
  freevars: string[];
  argcount: number;
  nlocals: number;
  stacksize: number;
  flags: number;
  name: string;
  filename: string;
  exceptiontable?: string;
  mode: "eval" | "exec";
}

const SERIALIZE_SCRIPT = `
def _pgthon_serialize_code(code):
    import json

    def serialize_const(c):
        if c is None:
            return {"type": "none"}
        if isinstance(c, bool):
            return {"type": "bool", "value": c}
        if isinstance(c, int):
            return {"type": "int", "value": c}
        if isinstance(c, float):
            return {"type": "float", "value": c}
        if isinstance(c, str):
            return {"type": "str", "value": c}
        if isinstance(c, bytes):
            return {"type": "bytes", "value": c.hex()}
        if isinstance(c, tuple):
            return {"type": "tuple", "items": [serialize_const(x) for x in c]}
        if isinstance(c, frozenset):
            return {"type": "frozenset"}
        if c is ...:
            return {"type": "ellipsis"}
        if hasattr(c, 'co_code'):
            return {"type": "code", "value": serialize_code_obj(c)}
        return {"type": "none"}

    def serialize_code_obj(co):
        result = {
            "bytecode": co.co_code.hex(),
            "consts": [serialize_const(c) for c in co.co_consts],
            "names": list(co.co_names),
            "varnames": list(co.co_varnames),
            "cellvars": list(co.co_cellvars),
            "freevars": list(co.co_freevars),
            "argcount": co.co_argcount,
            "nlocals": co.co_nlocals,
            "stacksize": co.co_stacksize,
            "flags": co.co_flags,
            "name": co.co_name,
            "filename": co.co_filename,
        }
        if hasattr(co, 'co_exceptiontable') and co.co_exceptiontable:
            result["exceptiontable"] = co.co_exceptiontable.hex()
        return result

    return json.dumps(serialize_code_obj(code))

def _pgthon_compile(source):
    import json
    try:
        code = compile(source, '<pgthon>', 'eval')
        mode = 'eval'
    except SyntaxError:
        code = compile(source, '<pgthon>', 'exec')
        mode = 'exec'
    result = json.loads(_pgthon_serialize_code(code))
    result['mode'] = mode
    return json.dumps(result)
`;

let initialized = false;

export async function compilePython(source: string): Promise<CodeObjectJSON> {
  const pyodide = await getPyodide();

  if (!initialized) {
    pyodide.runPython(SERIALIZE_SCRIPT);
    initialized = true;
  }

  const resultJson = pyodide.runPython(
    `_pgthon_compile(${JSON.stringify(source)})`
  );
  return JSON.parse(resultJson);
}
