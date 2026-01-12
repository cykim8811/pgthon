import React from "react";
import Header from "../components/Header";

export default function DocumentView() {
    return (
        <div className="min-h-screen bg-zinc-50/50 flex flex-col font-sans text-zinc-900">
            <Header />

            <main className="flex-1 max-w-4xl w-full mx-auto p-12 space-y-8">
                <section className="space-y-12">
                    <div className="group relative">
                        <h2 className="text-2xl font-light tracking-tight mb-4">Introduction</h2>
                        <p className="text-zinc-600 font-light leading-relaxed">
                            This is a document-based workspace where you can interact with Python objects.
                            Click on a block to edit or execute Python code.
                        </p>
                    </div>
                </section>
            </main>
        </div>
    );
}
