import { useState } from "react";
import { createClient } from "@supabase/supabase-js";
import { Play, Terminal, Loader2, Trash2, Bug } from "lucide-react";
import { ObjectInspector } from "../components/ObjectInspector";

// Initialize Supabase Client
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
const supabase = createClient(supabaseUrl, supabaseKey);

const DEFAULT_CODE = `LOAD_CONST 10
STORE_FAST a
LOAD_CONST 20
STORE_FAST b
LOAD_FAST a
LOAD_FAST b
BINARY_ADD
RETURN_VALUE`;

export default function ReplPage() {
    const [code, setCode] = useState(DEFAULT_CODE);
    const [resultId, setResultId] = useState<string | null>(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [logs, setLogs] = useState<string[]>([]);

    const handleRun = async () => {
        setLoading(true);
        setError(null);
        setResultId(null);
        setLogs([]);

        try {
            setLogs(prev => [...prev, "> Assembling and Running..."]);

            const { data: resId, error: runError } = await supabase.rpc("vm_execute_source", {
                p_source: code
            });

            if (runError) throw runError;

            setLogs(prev => [...prev, `> Execution Success. Result ID: ${resId}`]);
            setResultId(resId);

        } catch (err: any) {
            setError(err.message || "An error occurred");
            setLogs(prev => [...prev, `> Error: ${err.message}`]);
            console.error(err);
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="min-h-screen bg-zinc-50 flex flex-col font-sans text-zinc-900">
            <header className="px-6 py-4 border-b border-zinc-200 bg-white flex items-center justify-between">
                <div className="flex items-center gap-2">
                    <Terminal className="w-5 h-5 text-zinc-900" />
                    <h1 className="font-semibold tracking-tight">Elytra Bytecode REPL</h1>
                </div>
            </header>

            <main className="flex-1 flex gap-4 p-6 overflow-hidden">
                {/* Editor */}
                <div className="flex-1 flex flex-col bg-white rounded-lg border border-zinc-200 shadow-sm overflow-hidden">
                    <div className="px-4 py-2 border-b border-zinc-100 bg-zinc-50/50 flex justify-between items-center">
                        <span className="text-xs font-medium text-zinc-500 uppercase tracking-wider">Assembly Source</span>
                        <div className="flex items-center gap-2">
                            <span className="text-[10px] text-zinc-400">Ctrl+Enter to Run</span>
                            <button
                                onClick={() => setCode("")}
                                className="p-1 hover:bg-zinc-200 rounded text-zinc-400 hover:text-red-500 transition-colors"
                            >
                                <Trash2 className="w-4 h-4" />
                            </button>
                        </div>
                    </div>
                    <textarea
                        value={code}
                        onChange={(e) => setCode(e.target.value)}
                        onKeyDown={(e) => {
                            if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
                                handleRun();
                            }
                        }}
                        className="flex-1 p-4 font-mono text-sm resize-none focus:outline-none text-zinc-800 leading-relaxed"
                        spellCheck={false}
                    />
                </div>

                {/* Output & Inspector */}
                <div className="w-[450px] flex flex-col gap-4">
                    <div className="bg-white rounded-lg border border-zinc-200 shadow-sm p-4">
                        <button
                            onClick={handleRun}
                            disabled={loading}
                            className="w-full py-2.5 bg-zinc-900 text-white rounded-md font-medium text-sm hover:bg-zinc-800 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2 transition-all active:scale-[0.98]"
                        >
                            {loading ? (
                                <Loader2 className="w-4 h-4 animate-spin" />
                            ) : (
                                <Play className="w-4 h-4 fill-current" />
                            )}
                            {loading ? "Running..." : "Run Bytecode"}
                        </button>
                    </div>

                    {/* Result Inspector */}
                    <div className="flex-1 bg-zinc-900 rounded-lg shadow-sm border border-zinc-800 overflow-hidden flex flex-col">
                        <div className="px-4 py-2 border-b border-zinc-800 bg-zinc-950 flex items-center gap-2">
                            <Bug className="w-3.5 h-3.5 text-zinc-400" />
                            <span className="text-xs font-mono text-zinc-400">Result Inspector</span>
                        </div>

                        <div className="flex-1 p-4 overflow-y-auto">
                            {resultId ? (
                                <ObjectInspector objectId={resultId} label="RETURN_VALUE" />
                            ) : (
                                <div className="h-full flex flex-col items-center justify-center text-zinc-600 gap-2">
                                    <Terminal className="w-8 h-8 opacity-20" />
                                    <span className="text-xs italic">Run code to inspect result...</span>
                                </div>
                            )}
                        </div>

                        {/* Mini Log */}
                        <div className="h-32 border-t border-zinc-800 bg-zinc-950 p-3 font-mono text-[10px] text-zinc-500 overflow-y-auto">
                            {logs.map((log, i) => (
                                <div key={i}>{log}</div>
                            ))}
                        </div>
                    </div>
                </div>
            </main>
        </div>
    );
}
