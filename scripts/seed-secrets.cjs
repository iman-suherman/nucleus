#!/usr/bin/env node
/**
 * Push managed secret values from .env into GCP Secret Manager.
 */
const fs = require("fs");
const path = require("path");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
const { loadDotenv } = require("./load-dotenv.cjs");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const {
  MANAGED_SECRETS,
  MANAGED_FILE_SECRETS,
  ensureSecret,
  addSecretVersion,
  addSecretVersionFromFile,
  secretExists,
} = require("./gcp-secrets.cjs");

const repoRoot = path.join(__dirname, "..");

function fail(message) {
  console.error(`seed-secrets: ${message}`);
  process.exit(1);
}

function main() {
  applyGcpEnv(repoRoot);
  const env = loadDotenv(repoRoot);
  const projectId = resolveGcpProjectId(repoRoot);
  if (!projectId) {
    fail("GCP_PROJECT_ID is not set. Add it to .env or run npm run login.");
  }

  let seeded = 0;
  for (const key of MANAGED_SECRETS) {
    const value = env[key];
    if (!value) {
      console.log(`seed-secrets: skip ${key} (not set in .env)`);
      continue;
    }

    const existed = secretExists(projectId, key);
    ensureSecret(projectId, key);
    addSecretVersion(projectId, key, value);
    seeded += 1;
    console.log(
      `seed-secrets: ${existed ? "updated" : "created"} ${key} in project ${projectId}`
    );
  }

  for (const { secretId, envKey, outputPath, encoding } of MANAGED_FILE_SECRETS) {
    const configuredPath = env[envKey]?.trim();
    const filePath = configuredPath
      ? path.isAbsolute(configuredPath)
        ? configuredPath
        : path.join(repoRoot, configuredPath)
      : path.join(repoRoot, outputPath);

    if (!fs.existsSync(filePath)) {
      console.log(`seed-secrets: skip ${secretId} (missing file ${filePath})`);
      continue;
    }

    const existed = secretExists(projectId, secretId);
    ensureSecret(projectId, secretId);
    addSecretVersionFromFile(projectId, secretId, filePath, { encoding: encoding ?? "binary" });
    seeded += 1;
    console.log(
      `seed-secrets: ${existed ? "updated" : "created"} ${secretId} from ${filePath}`
    );
  }

  if (!seeded) {
    fail("no managed secrets found in .env");
  }
}

main();
