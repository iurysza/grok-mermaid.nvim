import { render } from "grok-mermaid";

let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  input += chunk;
});
process.stdin.on("end", () => {
  try {
    const sources = JSON.parse(input);
    if (!Array.isArray(sources) || !sources.every((source) => typeof source === "string")) {
      throw new TypeError("Expected a JSON array of Mermaid source strings");
    }
    process.stdout.write(JSON.stringify(sources.map((source) => render(source)?.styled ?? false)));
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  }
});
