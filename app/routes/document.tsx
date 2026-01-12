import type { Route } from "./+types/document";
import DocumentView from "../views/DocumentView";

export function meta({ }: Route.MetaArgs) {
    return [
        { title: "Document - Elytra" },
        { name: "description", content: "Elytra Workspace Document" },
    ];
}

export default function Document() {
    return <DocumentView />;
}
