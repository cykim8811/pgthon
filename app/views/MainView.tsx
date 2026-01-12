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

export default function MainView() {
    return (
        <div className="min-h-screen flex flex-col items-center justify-center bg-white text-zinc-900 font-sans selection:bg-zinc-100">
            <main className="max-w-2xl px-8 py-16 animate-in fade-in duration-1000 slide-in-from-bottom-4">
                <header className="mb-12">
                    <div className="flex items-center gap-2 mb-6">
                        <ElytraIcon className="w-16 h-auto text-zinc-900" />
                        <h1 className="text-5xl font-light tracking-tight">
                            Elytra
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
                © 2026 Elytra
            </footer>
        </div>
    );
}
