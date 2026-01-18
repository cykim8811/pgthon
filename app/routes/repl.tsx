import { useState } from "react";
import { createClient } from "@supabase/supabase-js";
import { Play, Terminal, Loader2, Trash2 } from "lucide-react";

// Initialize Supabase Client
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || "http://127.0.0.1:54321";
const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5vbmUiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTYzMzQ0NDgwMCwiZXhwIjoxOTQ5MDIwODAwfQ.sY_ZD_s-6j-a_a-a_a-a_a-a_a-a_a-a_a-a_a-a_a";
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
    const [output, setOutput] = useState<string | null>(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const handleRun = async () => {
        setLoading(true);
        setError(null);
        setOutput(null);

        try {
            // 1. Assemble Code
            const { data: codeId, error: assembleError } = await supabase.rpc("vm_assemble", {
                p_source: code,
                p_name: "web_repl"
            });

            if (assembleError) throw assembleError;
            if (!codeId) throw new Error("Failed to assemble code (No ID returned)");

            // 2. Create Locals (Empty Dict)
            // Ideally we should reuse locals to keep state, but for MVP new locals each run.
            // Helper to assume locals created inside vm_run_frame if null? No, vm_run_frame needs locals.

            // Let's create a temp dict for locals manually here?
            // Or better: Create a helper RPC `vm_run_script(source)` that does both.
            // But let's stick to primitives for now to test connections.

            // 2a. Create Dict
            // We need raw SQL or RPC to create dict.
            // Let's rely on a new helper `vm_quick_eval(code_id)`?
            // Or just use the fact that we can't easily create dicts from client without RPC.
            // Let's add `vm_eval_assembled` RPC next step.
            // For now, assume a helper RPC exists or use `vm_run_frame` with NULL locals?
            // Our `vm_run_frame` crashes if locals is null for LOAD_FAST.

            // Workaround: Call a new helper RPC we will make: `vm_execute_source`
            const { data: resultId, error: runError } = await supabase.rpc("vm_execute_source", {
                p_source: code
            });

            if (runError) throw runError;

            // 3. Get Result Value
            // Inspect the result object
            // We need a way to see the value.
            // Let's use `vm_get_value_as_text` (We need to make this too).

            // For now, let's display Result ID
            setOutput(`Result Object ID: ${resultId}`);

            // Try to fetch value if int
            const { data: intVal } = await supabase
                .from("py_long_object")
                .select("long_value")
                .eq("ob_base", resultId)
                .single();

            if (intVal) {
                setOutput((prev) => `${prev}\nValue (Int): ${intVal.long_value}`);
            }

        } catch (err: any) {
            setError(err.message || "An error occurred");
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
                        <button
                            onClick={() => setCode("")}
                            className="p-1 hover:bg-zinc-200 rounded text-zinc-400 hover:text-red-500 transition-colors"
                        >
                            <Trash2 className="w-4 h-4" />
                        </button>
                    </div>
                    <textarea
                        value={code}
                        onChange={(e) => setCode(e.target.value)}
                        className="flex-1 p-4 font-mono text-sm resize-none focus:outline-none text-zinc-800 leading-relaxed"
                        spellCheck={false}
                    />
                </div>

                {/* Output & Controls */}
                <div className="w-96 flex flex-col gap-4">
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

                    <div className="flex-1 bg-zinc-900 rounded-lg shadow-sm border border-zinc-800 overflow-hidden flex flex-col">
                        <div className="px-4 py-2 border-b border-zinc-800 bg-zinc-950 flex items-center gap-2">
                            <div className="w-2.5 h-2.5 rounded-full bg-red-500/20 border border-red-500/50"></div>
                            <div className="w-2.5 h-2.5 rounded-full bg-yellow-500/20 border border-yellow-500/50"></div>
                            <div className="w-2.5 h-2.5 rounded-full bg-green-500/20 border border-green-500/50"></div>
                            <span className="ml-2 text-xs font-mono text-zinc-500">Output Log</span>
                        </div>
                        <div className="flex-1 p-4 font-mono text-xs text-zinc-300 overflow-y-auto whitespace-pre-wrap">
                            {error && (
                                <div className="text-red-400 mb-2">
                                    Error: {error}
                                </div>
                            )}
                            {output ? (
                                <div className="text-green-400">{output}</div>
                            ) : (
                                <span className="text-zinc-600 italic">Ready to run...</span>
                            )}
                        </div>
                    </div>
                </div>
            </main>
        </div>
    );
}
