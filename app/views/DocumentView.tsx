import React from "react";

const ElytraIcon = ({ className }: { className?: string }) => (
    <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 140 71"
        fill="none"
        className={className}
    >
        <path
            d="M140.347 35.4428L70.1738 105.617L0 35.4428L70.1738 -34.73L140.347 35.4428ZM57.0156 73.6626L70.1738 86.8198L121.551 35.4428L108.393 22.2846L57.0156 73.6626ZM18.7959 35.4428L47.6182 64.2641L98.9951 12.8872L70.1738 -15.9341L18.7959 35.4428ZM46.7207 24.81C48.3705 30.2109 52.5981 34.4385 57.999 36.0883C52.5982 37.7382 48.3706 41.9649 46.7207 47.3657C45.0708 41.965 40.844 37.7382 35.4434 36.0883C40.8442 34.4385 45.0709 30.2109 46.7207 24.81Z"
            fill="currentColor"
        />
    </svg>
);

export default function DocumentView() {
    return (
        <div className="min-h-screen bg-zinc-50/50 flex flex-col font-sans text-zinc-900">
            {/* Navigation / Header */}
            <header className="h-14 border-b border-zinc-200 bg-white flex items-center justify-between px-6 sticky top-0 z-10">
                <div className="flex items-center gap-3">
                    <ElytraIcon className="w-8 h-auto text-zinc-900" />
                    <span className="font-medium tracking-tight">Elytra</span>
                    <span className="text-zinc-300 mx-1">/</span>
                    <span className="text-zinc-500 font-light text-sm">Untitled Document</span>
                </div>
                <div className="flex items-center gap-4">
                    <button className="text-sm text-zinc-500 hover:text-zinc-900 transition-colors">Share</button>
                    <button className="px-4 py-1.5 bg-zinc-900 text-white text-xs font-medium rounded-md hover:bg-zinc-800 transition-colors">
                        Run All
                    </button>
                </div>
            </header>

            {/* Main Workspace */}
            <main className="flex-1 max-w-4xl w-full mx-auto p-12 space-y-8">
                {/* Placeholder Blocks */}
                <section className="space-y-12">
                    {/* Text Block */}
                    <div className="group relative">
                        <h2 className="text-2xl font-light tracking-tight mb-4">Introduction</h2>
                        <p className="text-zinc-600 font-light leading-relaxed">
                            This is a document-based workspace where you can interact with Python objects.
                            Click on a block to edit or execute Python code.
                        </p>
                    </div>

                    {/* Python Object Block Mockup */}
                    <div className="p-6 bg-white border border-zinc-200 rounded-xl shadow-sm space-y-4 hover:border-zinc-300 transition-all">
                        <div className="flex items-center justify-between">
                            <span className="text-xs font-mono text-zinc-400">DataFrame: users_data</span>
                            <span className="text-[10px] px-2 py-0.5 bg-emerald-50 text-emerald-600 rounded-full font-medium">Synced</span>
                        </div>
                        <div className="h-32 bg-zinc-50 rounded-lg flex items-center justify-center border border-zinc-100 border-dashed">
                            <span className="text-sm text-zinc-400 italic">Visualizer for Python Object</span>
                        </div>
                    </div>

                    {/* Code Block Mockup */}
                    <div className="rounded-xl overflow-hidden border border-zinc-200 shadow-sm bg-[#1e1e1e]">
                        <div className="px-4 py-2 bg-[#2d2d2d] border-b border-zinc-800 flex items-center gap-2">
                            <div className="w-2 h-2 rounded-full bg-red-500/50" />
                            <div className="w-2 h-2 rounded-full bg-amber-500/50" />
                            <div className="w-2 h-2 rounded-full bg-emerald-500/50" />
                            <span className="text-[10px] font-mono text-zinc-500 ml-2">analysis.py</span>
                        </div>
                        <pre className="p-6 text-sm font-mono text-zinc-300 overflow-x-auto leading-relaxed">
                            <code>{`import pandas as pd

def analyze_workspace():
    # Visualizing objects interactively
    return "Elytra is Ready"`}</code>
                        </pre>
                    </div>
                </section>
            </main>

            {/* Quick Access Sidebar / Floating Bar */}
            <div className="fixed bottom-8 left-1/2 -translate-x-1/2 flex items-center gap-2 p-1 bg-white border border-zinc-200 rounded-full shadow-lg">
                <button className="px-4 py-2 text-sm text-zinc-600 hover:bg-zinc-50 rounded-full transition-colors font-light">Add Text</button>
                <div className="w-px h-4 bg-zinc-100" />
                <button className="px-4 py-2 text-sm text-zinc-600 hover:bg-zinc-50 rounded-full transition-colors font-light">Add Python Block</button>
            </div>
        </div>
    );
}
