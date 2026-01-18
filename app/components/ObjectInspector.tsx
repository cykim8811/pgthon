import { useEffect, useState } from "react";
import { createClient } from "@supabase/supabase-js";
import { ChevronRight, ChevronDown, Box, List, FileJson, Hash, Type } from "lucide-react";

// Initialize Supabase Client (Should pass as prop or context ideally)
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
const supabase = createClient(supabaseUrl, supabaseKey);

interface ObjectInspectorProps {
    objectId: string;
    label?: string;
    level?: number;
}

export function ObjectInspector({ objectId, label, level = 0 }: ObjectInspectorProps) {
    const [data, setData] = useState<any>(null);
    const [expanded, setExpanded] = useState(level === 0);
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        if (expanded && !data) {
            setLoading(true);
            supabase.rpc("vm_inspect_object", { p_obj_id: objectId })
                .then(({ data, error }) => {
                    if (data) setData(data);
                    setLoading(false);
                });
        }
    }, [expanded, objectId]);

    const toggle = () => setExpanded(!expanded);

    if (!objectId) return <span className="text-zinc-500">None</span>;

    // Simple Render for top level if not expanded
    if (!expanded) {
        return (
            <div
                className="flex items-center gap-1 cursor-pointer hover:bg-zinc-100/10 rounded px-1 py-0.5 select-none"
                onClick={toggle}
                style={{ marginLeft: level * 12 }}
            >
                <ChevronRight className="w-3 h-3 text-zinc-500" />
                {label && <span className="text-zinc-400 mr-1">{label}:</span>}
                <span className="text-zinc-300">Object({objectId.slice(0, 8)}...)</span>
            </div>
        );
    }

    if (loading) {
        return (
            <div className="flex items-center gap-2 text-zinc-500 ml-4 animate-pulse">
                <div className="w-2 h-2 bg-zinc-600 rounded-full" />
                <span className="text-xs">Loading...</span>
            </div>
        );
    }

    // Detail Render
    return (
        <div style={{ marginLeft: level * 12 }}>
            <div
                className="flex items-center gap-1 cursor-pointer hover:bg-zinc-800 rounded px-1 py-0.5 select-none"
                onClick={toggle}
            >
                <ChevronDown className="w-3 h-3 text-zinc-400" />
                {label && <span className="text-purple-300 font-mono mr-1">{label}:</span>}
                <span className="text-zinc-300 font-medium">{data?.type || 'unknown'}</span>
                <span className="text-zinc-600 text-[10px] ml-2">{objectId.slice(0, 8)}</span>
            </div>

            <div className="ml-4 border-l border-zinc-800 pl-2 py-1 flex flex-col gap-1">
                {/* Value (Int/Str) */}
                {data?.value !== undefined && (
                    <div className="flex items-start gap-2 text-sm">
                        <span className="text-zinc-500 w-12 text-xs uppercase tracking-wider py-0.5">Value</span>
                        <div className="font-mono text-green-300 bg-green-500/10 px-1.5 rounded">
                            {String(data.value)}
                        </div>
                    </div>
                )}

                {/* List Children */}
                {data?.children && (
                    <div className="mt-1">
                        <div className="text-xs text-zinc-500 mb-1 uppercase tracking-wider">Items ({data.length})</div>
                        {data.children.map((child: any, idx: number) => (
                            <div key={child.id} className="flex flex-col">
                                {/* Simple Preview for now, recursive later? */}
                                {/* If it's a simple type, show value. If complex, recursion. */}
                                {['int', 'str', 'bool'].includes(child.type) ? (
                                    <div className="flex gap-2 text-xs font-mono ml-2">
                                        <span className="text-zinc-500">{idx}:</span>
                                        <span className="text-yellow-200">{child.preview}</span>
                                    </div>
                                ) : (
                                    <ObjectInspector objectId={child.id} label={String(idx)} level={level + 1} />
                                )}
                            </div>
                        ))}
                    </div>
                )}

                {/* List Iterator */}
                {data?.type === 'list_iterator' && (
                    <div className="text-xs">
                        <div className="flex gap-2">
                            <span className="text-zinc-500">Index:</span>
                            <span className="text-zinc-200">{data.index}</span>
                        </div>
                        <div className="mt-1">
                            <span className="text-zinc-500 block mb-1">Target List:</span>
                            <ObjectInspector objectId={data.list_id} level={level + 1} />
                        </div>
                    </div>
                )}

                {/* Generic Repr */}
                {data?.repr && !data.value && !data.children && data.type !== 'list_iterator' && (
                    <div className="text-xs font-mono text-zinc-500 italic">
                        {data.repr}
                    </div>
                )}
            </div>
        </div>
    );
}
