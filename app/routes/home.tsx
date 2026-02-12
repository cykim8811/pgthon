import type { Route } from "./+types/home";
import MainView from "../views/MainView";

export function meta({ }: Route.MetaArgs) {
  return [
    { title: "Pgthon" },
    { name: "description", content: "Pgthon - A Python-based workspace" },
  ];
}

export default function Home() {
  return <MainView />;
}
