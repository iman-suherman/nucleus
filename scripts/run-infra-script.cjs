#!/usr/bin/env node
/**
 * Run an npm script in suherman-net-infra (forwards args after --).
 *
 * Usage:
 *   node scripts/run-infra-script.cjs ci [-- --once]
 */
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const workspaceRoot = path.resolve(
  process.env.SUHERMAN_WORKSPACE_ROOT || path.join(os.homedir(), "src"),
);
const infraRoot = path.resolve(
  process.env.SUHERMAN_NET_INFRA_ROOT ||
    path.join(workspaceRoot, "personal", "suherman-net-infra"),
);

function main() {
  const script = process.argv[2];
  if (!script) {
    console.error("usage: node scripts/run-infra-script.cjs <npm-script> [-- extra args]");
    process.exit(1);
  }

  if (!fs.existsSync(path.join(infraRoot, "package.json"))) {
    console.error(
      `run-infra-script: package.json not found at ${infraRoot} — set SUHERMAN_NET_INFRA_ROOT`,
    );
    process.exit(1);
  }

  const dash = process.argv.indexOf("--");
  const extra = dash === -1 ? process.argv.slice(3) : process.argv.slice(dash + 1);
  const npmArgs = ["run", script];
  if (extra.length > 0) {
    npmArgs.push("--", ...extra);
  }

  const result = spawnSync("npm", npmArgs, {
    cwd: infraRoot,
    stdio: "inherit",
    env: process.env,
    shell: process.platform === "win32",
  });

  if (result.error) {
    console.error(result.error.message);
    process.exit(1);
  }
  process.exit(result.status ?? 1);
}

main();
