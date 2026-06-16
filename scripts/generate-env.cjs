#!/usr/bin/env node
/**
 * Build .env from .env.example, existing .env values, and GCP Secret Manager.
 */
const fs = require("fs");
const path = require("path");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
const { parseEnvFile, resolveGcpProjectId } = require("./gcp-config.cjs");
const { MANAGED_SECRETS, accessSecret } = require("./gcp-secrets.cjs");

const repoRoot = path.join(__dirname, "..");
const examplePath = path.join(repoRoot, ".env.example");
const envPath = path.join(repoRoot, ".env");

function fail(message) {
  console.error(`generate-env: ${message}`);
  process.exit(1);
}

function orderedKeys(exampleContent, existingKeys, secretKeys) {
  const keys = [];
  const seen = new Set();

  for (const line of exampleContent.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    if (!seen.has(key)) {
      seen.add(key);
      keys.push(key);
    }
  }

  for (const key of existingKeys) {
    if (!seen.has(key)) {
      seen.add(key);
      keys.push(key);
    }
  }

  for (const key of secretKeys) {
    if (!seen.has(key)) {
      seen.add(key);
      keys.push(key);
    }
  }

  return keys;
}

function formatEnv(keys, values) {
  const lines = [];
  for (const key of keys) {
    const value = values[key];
    if (value === undefined || value === "") continue;
    lines.push(`${key}=${value}`);
  }
  return `${lines.join("\n")}\n`;
}

function main() {
  if (!fs.existsSync(examplePath)) {
    fail("missing .env.example");
  }

  applyGcpEnv(repoRoot);

  const exampleContent = fs.readFileSync(examplePath, "utf8");
  const example = parseEnvFile(examplePath);
  const existing = parseEnvFile(envPath);
  const projectId = resolveGcpProjectId(repoRoot);

  if (!projectId) {
    fail("GCP_PROJECT_ID is not set. Add it to .env or run npm run login.");
  }

  const secrets = {};
  for (const key of MANAGED_SECRETS) {
    try {
      secrets[key] = accessSecret(projectId, key);
      console.log(`generate-env: loaded ${key} from Secret Manager`);
    } catch (error) {
      if (existing[key]) {
        secrets[key] = existing[key];
        console.log(`generate-env: kept local ${key} (Secret Manager unavailable)`);
        continue;
      }
      console.log(`generate-env: skip ${key} (${error.message})`);
    }
  }

  const merged = { ...example, ...existing, ...secrets };
  const keys = orderedKeys(exampleContent, Object.keys(existing), MANAGED_SECRETS);
  fs.writeFileSync(envPath, formatEnv(keys, merged), "utf8");
  console.log(`generate-env: wrote ${envPath}`);
}

main();
