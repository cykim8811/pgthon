import React from "react";
import { PgthonIcon } from "../components/Icons";

export default function MainView() {
    return (
        <div className="min-h-screen flex flex-col items-center justify-center bg-white text-zinc-900 font-sans selection:bg-zinc-100">
            <main className="max-w-2xl px-8 py-16 animate-in fade-in duration-1000 slide-in-from-bottom-4">
                <header className="mb-12">
                    <div className="flex items-center gap-2 mb-6">
                        <PgthonIcon className="w-16 h-auto text-zinc-900" />
                        <h1 className="text-5xl font-light tracking-tight">
                            Pgthon
                        </h1>
                    </div>
                    <p className="text-lg text-zinc-500 font-light tracking-tight">
                        A Python-powered workspace.
                    </p>
                </header>

                <section className="space-y-6 text-zinc-600 font-light leading-relaxed">
                    <p>
                        A document-based workspace for visualizing and manipulating Python objects interactively.
                    </p>

                    <div className="pt-8 border-t border-zinc-100/50">
                        <button
                            className="px-6 py-2 bg-zinc-900 text-white text-sm font-medium rounded-full hover:bg-zinc-800 transition-colors duration-200"
                            onClick={() => console.log("Get started clicked")}
                        >
                            Get Started
                        </button>
                    </div>
                </section>
            </main>

            <footer className="fixed bottom-8 text-[10px] text-zinc-400 font-light tracking-[0.2em] uppercase">
                © 2026 Pgthon
            </footer>
        </div>
    );
}
