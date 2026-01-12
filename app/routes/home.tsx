import type { Route } from "./+types/home";
import MainView from "../views/MainView";

export function meta({ }: Route.MetaArgs) {
  return [
    { title: "Elytra" },
    { name: "description", content: "Elytra - A Python-based workspace" },
  ];
}

export default function Home() {
  return <MainView />;
}
