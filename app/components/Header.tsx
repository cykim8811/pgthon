import { Link } from "react-router";
import { Button } from "~/components/ui/button";
import { useEffect, useState } from "react";
import { supabase } from "~/utils/supabase";
import type { User } from "@supabase/supabase-js";

export default function Header() {
    const [user, setUser] = useState<User | null>(null);

    useEffect(() => {
        // 현재 세션 확인
        supabase.auth.getSession().then(({ data: { session } }) => {
            setUser(session?.user ?? null);
        });

        // 인증 상태 변경 감지
        const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
            setUser(session?.user ?? null);
        });

        return () => subscription.unsubscribe();
    }, []);

    const handleLogout = async () => {
        await supabase.auth.signOut();
    };

    return (
        <header className="h-12 border-b border-zinc-200 bg-white flex items-center justify-between px-6 sticky top-0 z-10">
            <div className="flex items-end gap-0.5">
                <Link to="/" className="text-md font-medium rounded text-zinc-800 hover:opacity-80 transition-opacity">
                    My Workspace
                </Link>
                <div className="flex gap-0.5 ml-1 mt-1">
                    <span className="text-zinc-500 font-light text-sm">.</span>
                    <span className="text-zinc-500 font-light text-sm">document1</span>
                </div>
            </div>
            <div className="flex items-center gap-4">
                <button className="text-sm text-zinc-500 hover:text-zinc-900 transition-colors">Share</button>

                {user ? (
                    <div className="flex items-center gap-3">
                        <span className="text-xs text-zinc-500">{user.email}</span>
                        <Button variant="ghost" size="sm" onClick={handleLogout}>
                            Logout
                        </Button>
                    </div>
                ) : (
                    <Button variant="ghost" size="sm" asChild>
                        <Link to="/login">Login</Link>
                    </Button>
                )}
            </div>
        </header>
    );
}
