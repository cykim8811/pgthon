import { useCallback, useEffect, useRef, useState } from "react";
import { EditorView, keymap } from "@codemirror/view";
import { EditorState } from "@codemirror/state";
import { python } from "@codemirror/lang-python";
import { basicSetup } from "codemirror";
import { indentWithTab } from "@codemirror/commands";
import { compilePython } from "~/utils/compile-python";
import { getPyodide } from "~/utils/pyodide";
import { supabase } from "~/utils/supabase";

interface RunResult {
  result: any;
  globals: Record<string, any>;
  error: any;
}

function formatValue(val: any): string {
  if (val === null || val === undefined) return "None";
  if (val.type === "none") return "None";
  if (val.type === "bool") return val.value ? "True" : "False";
  if (val.type === "int") return String(val.value);
  if (val.type === "float") return String(val.value);
  if (val.type === "str") return JSON.stringify(val.value);
  if (val.type === "list")
    return "[" + (val.items || []).map(formatValue).join(", ") + "]";
  if (val.type === "tuple") {
    const items = (val.items || []).map(formatValue);
    return items.length === 1
      ? "(" + items[0] + ",)"
      : "(" + items.join(", ") + ")";
  }
  if (val.type === "dict") {
    const entries = Object.entries(val.entries || {});
    return (
      "{" + entries.map(([k, v]) => k + ": " + formatValue(v)).join(", ") + "}"
    );
  }
  if (val.type === "object") return val.repr || "<object>";
  return JSON.stringify(val);
}

export default function PlaygroundView() {
  const editorRef = useRef<HTMLDivElement>(null);
  const viewRef = useRef<EditorView | null>(null);
  const [pyodideReady, setPyodideReady] = useState(false);
  const [loading, setLoading] = useState(false);
  const [output, setOutput] = useState<RunResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Load Pyodide on mount
  useEffect(() => {
    getPyodide()
      .then(() => setPyodideReady(true))
      .catch((err) => setError(`Failed to load Pyodide: ${err.message}`));
  }, []);

  // Initialize CodeMirror
  useEffect(() => {
    if (!editorRef.current) return;

    const state = EditorState.create({
      doc: "1 + 2",
      extensions: [
        basicSetup,
        python(),
        keymap.of([indentWithTab]),
        EditorView.theme({
          "&": { height: "100%" },
          ".cm-scroller": { overflow: "auto" },
        }),
      ],
    });

    const view = new EditorView({
      state,
      parent: editorRef.current,
    });
    viewRef.current = view;

    return () => {
      view.destroy();
      viewRef.current = null;
    };
  }, []);

  const handleRun = useCallback(async () => {
    if (!viewRef.current || !pyodideReady) return;

    const source = viewRef.current.state.doc.toString();
    setLoading(true);
    setError(null);
    setOutput(null);

    try {
      // Compile in browser via Pyodide
      const codeJson = await compilePython(source);

      // Execute on Elytra VM via Supabase RPC
      const { data, error: rpcError } = await supabase.rpc("py_run", {
        p_code: codeJson,
      });

      if (rpcError) {
        setError(`RPC error: ${rpcError.message}`);
        return;
      }

      setOutput(data as RunResult);
    } catch (err: any) {
      setError(err.message || "Unknown error");
    } finally {
      setLoading(false);
    }
  }, [pyodideReady]);

  return (
    <div className="flex flex-col h-screen bg-gray-950 text-gray-100">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-2 border-b border-gray-800 bg-gray-900">
        <div className="flex items-center gap-3">
          <a href="/" className="text-gray-400 hover:text-gray-200 text-sm">
            Elytra
          </a>
          <span className="text-gray-600">/</span>
          <h1 className="text-sm font-medium">Playground</h1>
        </div>
        <div className="flex items-center gap-3">
          {!pyodideReady && (
            <span className="text-xs text-gray-500">Loading Pyodide...</span>
          )}
          <button
            onClick={handleRun}
            disabled={!pyodideReady || loading}
            className="px-3 py-1 text-sm font-medium rounded bg-green-700 hover:bg-green-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            {loading ? "Running..." : "Run"}
          </button>
        </div>
      </div>

      {/* Main content */}
      <div className="flex flex-1 min-h-0">
        {/* Editor */}
        <div className="flex-1 border-r border-gray-800 min-w-0">
          <div ref={editorRef} className="h-full [&_.cm-editor]:h-full [&_.cm-editor_.cm-scroller]:h-full [&_.cm-gutters]:bg-gray-900 [&_.cm-gutters]:border-gray-800 [&_.cm-activeLineGutter]:bg-gray-800 [&_.cm-activeLine]:bg-gray-900/50" />
        </div>

        {/* Output panel */}
        <div className="w-[400px] flex flex-col bg-gray-900 overflow-auto">
          <div className="px-3 py-2 border-b border-gray-800">
            <span className="text-xs font-medium text-gray-400 uppercase tracking-wide">
              Output
            </span>
          </div>
          <div className="flex-1 p-3 font-mono text-sm space-y-3 overflow-auto">
            {error && (
              <div className="text-red-400">
                <span className="text-red-500 font-medium">Error: </span>
                {error}
              </div>
            )}
            {output && output.error && output.error !== null && (
              <div className="text-red-400">
                <span className="text-red-500 font-medium">
                  {output.error.type}:{" "}
                </span>
                {output.error.message}
              </div>
            )}
            {output && !output.error && output.result && (
              <div>
                <div className="text-gray-500 text-xs mb-1">Result</div>
                <div className="text-green-400">{formatValue(output.result)}</div>
              </div>
            )}
            {output &&
              output.globals &&
              Object.keys(output.globals).length > 0 && (
                <div>
                  <div className="text-gray-500 text-xs mb-1">Globals</div>
                  {Object.entries(output.globals).map(([key, val]) => (
                    <div key={key} className="text-blue-300">
                      <span className="text-gray-400">{key}</span>
                      <span className="text-gray-600"> = </span>
                      {formatValue(val)}
                    </div>
                  ))}
                </div>
              )}
            {!error && !output && !loading && (
              <div className="text-gray-600 italic">
                Press Run to execute Python code on the Elytra VM.
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
