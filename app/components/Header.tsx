import { Link } from "react-router";
import { Button } from "~/components/ui/button";
import { useEffect, useState } from "react";
import { supabase } from "~/utils/supabase";
import type { User } from "@supabase/supabase-js";
import { Avatar, AvatarFallback, AvatarImage } from "~/components/ui/avatar";
import {
    Popover,
    PopoverContent,
    PopoverTrigger,
} from "~/components/ui/popover";

export default function Header() {
    const [user, setUser] = useState<User | null>(null);

    useEffect(() => {
        supabase.auth.getSession().then(({ data: { session } }) => {
            setUser(session?.user ?? null);
        });

        const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
            setUser(session?.user ?? null);
        });

        return () => subscription.unsubscribe();
    }, []);

    const handleLogout = async () => {
        await supabase.auth.signOut();
    };

    const userInitial = user?.email?.charAt(0).toUpperCase() ?? "U";

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
                    <Popover>
                        <PopoverTrigger asChild>
                            <button className="outline-none">
                                <Avatar className="h-8 w-8 cursor-pointer border border-zinc-200 hover:opacity-80 transition-opacity">
                                    <AvatarImage src={user.user_metadata.avatar_url} />
                                    <AvatarFallback className="bg-zinc-100 text-zinc-600 text-xs">
                                        {userInitial}
                                    </AvatarFallback>
                                </Avatar>
                            </button>
                        </PopoverTrigger>
                        <PopoverContent className="w-56 p-2 mt-2" align="end">
                            <div className="px-2 py-1.5 mb-2">
                                <p className="text-[10px] text-zinc-400 uppercase tracking-widest font-medium">Logged in as</p>
                                <p className="text-xs font-medium text-zinc-900 truncate">{user.email}</p>
                            </div>
                            <div className="h-px bg-zinc-100 my-1" />
                            <Button
                                variant="ghost"
                                className="w-full justify-start text-xs font-normal text-red-500 hover:text-red-600 hover:bg-red-50"
                                size="sm"
                                onClick={handleLogout}
                            >
                                Logout
                            </Button>
                        </PopoverContent>
                    </Popover>
                ) : (
                    <Button variant="ghost" size="sm" asChild>
                        <Link to="/login">Login</Link>
                    </Button>
                )}
            </div>
        </header>
    );
}
