import type { Route } from "./+types/document";
import DocumentView from "../views/DocumentView";

export function meta({ }: Route.MetaArgs) {
    return [
        { title: "Document - Pgthon" },
        { name: "description", content: "Pgthon Workspace Document" },
    ];
}

export default function Document() {
    return <DocumentView />;
}
