
export default function Header() {
    return (
        <header className="h-12 border-b border-zinc-200 bg-white flex items-center justify-between px-6 sticky top-0 z-10">
            <div className="flex items-end gap-0.5">
                <span className="text-md font-medium rounded text-zinc-800">My Workspace</span>
                <div className="flex gap-0.5 ml-1 mt-1">
                    <span className="text-zinc-500 font-light text-sm">.</span>
                    <span className="text-zinc-500 font-light text-sm">document1</span>
                </div>
            </div>
            <div className="flex items-center gap-4">
                <button className="text-sm text-zinc-500 hover:text-zinc-900 transition-colors">Share</button>
            </div>
        </header>
    );
}
