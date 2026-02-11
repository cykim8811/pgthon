let pyodidePromise: Promise<any> | null = null;

function loadScript(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    if (document.querySelector(`script[src="${src}"]`)) {
      resolve();
      return;
    }
    const script = document.createElement("script");
    script.src = src;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error(`Failed to load ${src}`));
    document.head.appendChild(script);
  });
}

export async function getPyodide(): Promise<any> {
  if (!pyodidePromise) {
    pyodidePromise = (async () => {
      await loadScript(
        "https://cdn.jsdelivr.net/pyodide/v0.24.1/full/pyodide.js"
      );
      const pyodide = await (window as any).loadPyodide({
        indexURL: "https://cdn.jsdelivr.net/pyodide/v0.24.1/full/",
      });
      return pyodide;
    })();
  }
  return pyodidePromise;
}
