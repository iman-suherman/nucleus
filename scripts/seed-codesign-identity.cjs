#!/usr/bin/env node
/**
 * Seed Developer ID .p12 + export password into GCP Secret Manager.
 */
const fs = require("fs");
const path = require("path");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const {
  ensureSecret,
  addSecretVersion,
  addSecretVersionFromFile,
  secretExists,
} = require("./gcp-secrets.cjs");

const repoRoot = path.join(__dirname, "..");

function fail(message) {
  console.error(`seed-codesign: ${message}`);
  process.exit(1);
}

function main() {
  applyGcpEnv(repoRoot);
  const projectId = resolveGcpProjectId(repoRoot);
  if (!projectId) {
    fail("GCP_PROJECT_ID is not set. Add it to .env or run gcloud auth.");
  }

  const password = process.env.NUCLEUS_DEVELOPER_ID_CODESIGN_P12_PASSWORD?.trim();
  if (!password) {
    fail("NUCLEUS_DEVELOPER_ID_CODESIGN_P12_PASSWORD is not set");
  }

  const p12Path = path.join(repoRoot, "config", "Nucleus_DeveloperID.codesign.p12");
  if (!fs.existsSync(p12Path)) {
    fail(`missing ${p12Path} — run scripts/export-codesign-identity.sh first`);
  }

  for (const [secretId, value, label] of [
    ["NUCLEUS_DEVELOPER_ID_CODESIGN_P12_PASSWORD", password, "password"],
    ["NUCLEUS_DEVELOPER_ID_CODESIGN_P12", null, "p12"],
  ]) {
    const existed = secretExists(projectId, secretId);
    ensureSecret(projectId, secretId);
    if (label === "password") {
      addSecretVersion(projectId, secretId, value);
    } else {
      addSecretVersionFromFile(projectId, secretId, p12Path, { encoding: "base64" });
    }
    console.log(
      `seed-codesign: ${existed ? "updated" : "created"} ${secretId} in project ${projectId}`
    );
  }
}

main();
