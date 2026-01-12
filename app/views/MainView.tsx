import React from "react";

export default function MainView() {
    return (
        <div className="min-h-screen flex flex-col items-center justify-center bg-white text-zinc-900 font-sans selection:bg-zinc-100">
            <main className="max-w-2xl px-8 py-16 animate-in fade-in duration-1000 slide-in-from-bottom-4">
                <header className="mb-12">
                    <h1 className="text-4xl font-light tracking-tight mb-3">
                        Elytra
                    </h1>
                    <p className="text-lg text-zinc-500 font-light tracking-tight">
                        A Python-based workspace.
                    </p>
                </header>

                <section className="space-y-6 text-zinc-600 font-light leading-relaxed">
                    <p>
                        Welcome to a focused environment designed for Python development.
                        Minimal, efficient, and tailored for clarity.
                    </p>

                    <div className="pt-8 border-t border-zinc-100">
                        <button
                            className="px-6 py-2 bg-zinc-900 text-white text-sm font-medium rounded-full hover:bg-zinc-800 transition-colors duration-200"
                            onClick={() => console.log("Get started clicked")}
                        >
                            Get Started
                        </button>
                    </div>
                </section>
            </main>

            <footer className="fixed bottom-8 text-xs text-zinc-400 font-light tracking-widest uppercase">
                © 2026 Elytra
            </footer>
        </div>
    );
}
