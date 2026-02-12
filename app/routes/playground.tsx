import type { Route } from "./+types/playground";
import PlaygroundView from "../views/PlaygroundView";

export function meta({}: Route.MetaArgs) {
  return [
    { title: "Pgthon Playground" },
    {
      name: "description",
      content: "Run Python code on the Pgthon PostgreSQL VM",
    },
  ];
}

export default function Playground() {
  return <PlaygroundView />;
}
