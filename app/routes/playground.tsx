import type { Route } from "./+types/playground";
import PlaygroundView from "../views/PlaygroundView";

export function meta({}: Route.MetaArgs) {
  return [
    { title: "Elytra Playground" },
    {
      name: "description",
      content: "Run Python code on the Elytra PostgreSQL VM",
    },
  ];
}

export default function Playground() {
  return <PlaygroundView />;
}
