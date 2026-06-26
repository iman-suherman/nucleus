/**
 * Install stack git hooks from suherman-net-infra/githooks/ into .git/hooks/.
 */
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const root = path.join(__dirname, "..");
const workspaceRoot = path.resolve(
  process.env.SUHERMAN_WORKSPACE_ROOT || path.join(os.homedir(), "src"),
);
const infraRoot = path.resolve(
  process.env.SUHERMAN_NET_INFRA_ROOT ||
    path.join(workspaceRoot, "personal", "suherman-net-infra"),
);
const sourceDir = path.join(infraRoot, "githooks");
const targetDir = path.join(root, ".git/hooks");

/** Legacy nucleus hooks replaced by the stack installer. */
const legacyHooks = ["commit-msg"];

function listHookFiles(dir, base = dir) {
  /** @type {string[]} */
  const files = [];
  for (const name of fs.readdirSync(dir)) {
    if (name.startsWith(".")) continue;
    const full = path.join(dir, name);
    const stat = fs.statSync(full);
    if (stat.isDirectory()) {
      files.push(...listHookFiles(full, base));
    } else if (stat.isFile()) {
      files.push(path.relative(base, full));
    }
  }
  return files.sort();
}

function main() {
  if (!fs.existsSync(targetDir)) {
    console.error("install-git-hooks: .git/hooks not found — is this a git repository?");
    process.exit(1);
  }
  if (!fs.existsSync(sourceDir)) {
    console.error(
      `install-git-hooks: githooks/ not found at ${sourceDir} — set SUHERMAN_NET_INFRA_ROOT`,
    );
    process.exit(1);
  }

  for (const name of legacyHooks) {
    const target = path.join(targetDir, name);
    if (fs.existsSync(target)) {
      fs.unlinkSync(target);
      console.log(`install-git-hooks: removed legacy ${name}`);
    }
  }

  for (const rel of listHookFiles(sourceDir)) {
    const source = path.join(sourceDir, rel);
    const target = path.join(targetDir, rel);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.copyFileSync(source, target);
    fs.chmodSync(target, 0o755);
    console.log(`install-git-hooks: installed ${rel}`);
  }
}

main();
