#!/usr/bin/env node
/**
 * Human-readable catalog of npm scripts in this repo.
 * Run: npm run list
 * Paged with `more` on TTY; use --all to print everything.
 */
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { color, dim, highlightDefault } = require("./terminal-colors.cjs");

const root = path.join(__dirname, "..");
const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));

/** @type {Record<string, string>} */
const DESCRIPTIONS = {
  info: "Show Nucleus quick-start guide",
  init: "Alias for npm run info",
  list: "Show this command catalog (paged with more on TTY)",

  "generate-env": "Create .env from .env-example",
  "seed:secrets": "Seed GCP Secret Manager from local secret files",

  build: "Build Swift packages (swift build)",
  test: "Run Swift package tests",
  "dev:app": "Build packages, test, build app, launch on macOS",
  local: "Build debug Nucleus.app and launch",
  start: "Build release app + DMG for drag-to-Applications install",
  "setup:xcodegen": "Install XcodeGen (brew install xcodegen)",
  "setup:xcode": "Xcode first-launch setup (if build fails)",
  "build:app": "Debug Nucleus.app build",
  "build:xcode": "xcodebuild Nucleus macOS Debug scheme",
  "build:app:release": "Release Nucleus.app build only",
  "run:app": "Launch Nucleus.app on macOS",
  app: "Build app + launch on macOS",
  xcode: "Build app + open macOS Xcode project",
  "open:xcode": "Open app/Nucleus.xcodeproj",
  "prepare:icon": "Generate macOS AppIcon asset catalog",
  sign: "Sign Nucleus.app for distribution",
  package: "Create Nucleus.dmg",
  logs: "Tail Nucleus app logs",
  "logs:all": "Tail all Nucleus log streams",
  "logs:network": "Tail Nucleus network-related logs",

  "build:ios": "Build NucleusIOS for iOS Simulator",
  "xcode:ios": "xcodegen + open NucleusIOS.xcodeproj",
  "prepare:ios-icon": "Generate full-bleed iOS app icon assets",
  "capture:ios-screenshots": "Capture App Store screenshot sets (simulator)",
  "validate:ios-app-store": "Pre-submission iOS checks (source + repo archive .app when present)",
  "clean:ios-build": "Remove nucleus-apple/Apps/NucleusIOS/build output",

  "prepare:website": "Prepare marketing website static assets",
  "dev:website": "Start nucleus.suherman.net website dev server",
  "deploy:website": "Deploy website via deploy runner",
  "deploy:website:direct": "Deploy website to Cloud Run (direct)",
  "deploy:registry": "Deploy registry API via deploy runner",
  "deploy:registry:direct": "Deploy registry API to Cloud Run (direct)",
  "deploy:ai-overview": "Deploy AI overview API via deploy runner",
  "deploy:ai-overview:direct": "Deploy AI overview API to Cloud Run (direct)",
  "dev:ai-overview": "Start AI overview API dev server (:8787)",

  release: "Full macOS release (version, build, GCS, Firestore, deploy checkpoint)",
  "release:direct": "Full macOS release without deploy-runner wrapper",
  "release:local": "Local release script (sign, notarize, upload)",
  "upload:release": "Upload release artifact to GCS",
  "deploy:app": "Deploy macOS DMG release via deploy runner",
  "deploy:retry": "Retry failed manual deploy target",
  "deploy:stop": "Stop in-progress manual deploy",
  ci: "Local manual deploy status dashboard",

  "install-hooks": "Install git hooks into this repo (.git/hooks)",
  "deploy:cloudkit-schema": "Deploy CloudKit production schema",
  "republish:release-notes": "Republish release notes to registry API",
  "sparkle:setup-keys": "Generate Sparkle Ed25519 signing keys",
  "sparkle:appcast": "Generate Sparkle appcast.xml for updates",

  postinstall: "Run npm run info after npm install",
};

/** @type {Array<[string, RegExp]>} */
const CATEGORY_RULES = [
  ["Help", /^(info|init|list)$/],
  ["Environment", /^(generate-env|seed:)/],
  ["iOS app", /^(build:ios|xcode:ios|prepare:ios-icon|capture:ios|validate:ios|clean:ios)/],
  ["macOS app", /^(build|test|dev:app|local|start|setup:|build:app|build:xcode|run:app|app|xcode|open:xcode|prepare:icon|sign|package|logs)/],
  ["Website & APIs", /^(prepare:website|dev:website|dev:ai|deploy:website|deploy:registry|deploy:ai)/],
  ["Release & deploy", /^(release|upload:release|deploy:app|deploy:retry|deploy:stop|ci)/],
  ["Cloud & updates", /^(install-hooks|deploy:cloudkit|republish:|sparkle:)/],
];

function parseOptions(argv) {
  const options = {
    showAll: false,
    help: false,
  };

  for (const arg of argv) {
    if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else if (arg === "--all") {
      options.showAll = true;
    }
  }

  return options;
}

function stripAnsi(text) {
  return String(text).replace(/\x1b\[[0-9;]*m/g, "");
}

function visibleLength(text) {
  return stripAnsi(text).length;
}

function padVisible(text, width) {
  return `${text}${" ".repeat(Math.max(0, width - visibleLength(text)))}`;
}

function categoryFor(name) {
  for (const [category, pattern] of CATEGORY_RULES) {
    if (pattern.test(name)) return category;
  }
  return "Other";
}

function describeScript(name, command) {
  if (DESCRIPTIONS[name]) return DESCRIPTIONS[name];
  if (name.endsWith(":direct")) {
    const base = name.replace(/:direct$/, "");
    const baseDesc = DESCRIPTIONS[base];
    if (baseDesc) return `${baseDesc.replace(/ \(.*\)$/, "")} (direct)`;
  }
  return `Run: ${command}`;
}

function buildRows() {
  const scripts = Object.entries(pkg.scripts || {}).sort(([a], [b]) => a.localeCompare(b));
  return scripts.map(([name, command]) => ({
    category: categoryFor(name),
    command: `npm run ${name}`,
    description: describeScript(name, command),
  }));
}

function groupRows(rows) {
  /** @type {Map<string, typeof rows>} */
  const groups = new Map();
  for (const row of rows) {
    if (!groups.has(row.category)) groups.set(row.category, []);
    groups.get(row.category).push(row);
  }

  const ordered = [];
  for (const [category] of CATEGORY_RULES) {
    if (groups.has(category)) {
      ordered.push([category, groups.get(category)]);
      groups.delete(category);
    }
  }
  for (const [category, items] of groups) {
    ordered.push([category, items]);
  }
  return ordered;
}

function buildSections(rows) {
  return groupRows(rows).map(([category, items]) => ({ category, items }));
}

function renderLines(sections, rows) {
  /** @type {string[]} */
  const lines = [];

  lines.push("");
  lines.push(highlightDefault(" Nucleus "));
  lines.push(dim(pkg.description || ""));
  lines.push("");
  lines.push(dim("Use npm run list (not npm list). Press space in more to continue · q to quit."));
  lines.push("");

  const cmdWidth = Math.max("Command".length, ...rows.map((row) => row.command.length));
  const header = `${padVisible(color("Command", "bold"), cmdWidth)}  ${color("Description", "bold")}`;
  const rule = `${"-".repeat(cmdWidth)}  ${"-".repeat(80)}`;

  for (const section of sections) {
    lines.push(color(section.category, "bold"));
    lines.push(header);
    lines.push(dim(rule));
    for (const row of section.items) {
      lines.push(`${padVisible(color(row.command, "cyan"), cmdWidth)}  ${row.description}`);
    }
    lines.push("");
  }

  lines.push(dim(`${rows.length} commands · npm run list -- --all to print without more`));
  lines.push("");

  return lines;
}

function printLines(lines) {
  for (const line of lines) {
    console.log(line);
  }
}

function printViaMore(lines) {
  const pager = process.env.PAGER || "more";
  const input = `${lines.join("\n")}\n`;
  const result = spawnSync(pager, [], {
    input,
    encoding: "utf8",
    stdio: ["pipe", "inherit", "inherit"],
  });

  if (result.error || result.status === 127) {
    printLines(lines);
  }
}

function printHelp() {
  console.log("");
  console.log(highlightDefault(" npm run list "));
  console.log("");
  console.log("Usage:");
  console.log("  npm run list");
  console.log("  npm run list -- --all");
  console.log("");
  console.log(dim("Interactive TTY output is piped through more (override with PAGER=less)."));
  console.log("");
}

function main() {
  const options = parseOptions(process.argv.slice(2));
  if (options.help) {
    printHelp();
    return;
  }

  const rows = buildRows();
  const sections = buildSections(rows);
  const lines = renderLines(sections, rows);

  if (options.showAll || !process.stdout.isTTY) {
    printLines(lines);
    return;
  }

  printViaMore(lines);
}

main();
