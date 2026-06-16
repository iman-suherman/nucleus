/**
 * GCP Secret Manager helpers for Nucleus local .env generation.
 */
const { spawnSync } = require("child_process");

/** Env keys stored in Secret Manager (secret id matches env key). */
const MANAGED_SECRETS = [
  "CLOUDKIT_MANAGEMENT_TOKEN",
  "AUTH_SECRET",
  "GOOGLE_OAUTH_CLIENT_ID",
  "GOOGLE_OAUTH_CLIENT_SECRET",
];

function runGcloud(args, { input } = {}) {
  const result = spawnSync("gcloud", args, {
    encoding: "utf8",
    input,
    stdio: ["pipe", "pipe", "pipe"],
  });
  if (result.status !== 0) {
    const message = (result.stderr || result.stdout || "").trim();
    throw new Error(message || `gcloud ${args.join(" ")} failed`);
  }
  return (result.stdout || "").trimEnd();
}

function secretExists(projectId, secretId) {
  const result = spawnSync(
    "gcloud",
    [
      "secrets",
      "describe",
      secretId,
      `--project=${projectId}`,
      "--format=value(name)",
    ],
    { encoding: "utf8" }
  );
  return result.status === 0;
}

function ensureSecret(projectId, secretId) {
  if (secretExists(projectId, secretId)) return;
  runGcloud([
    "secrets",
    "create",
    secretId,
    `--project=${projectId}`,
    "--replication-policy=automatic",
    "--quiet",
  ]);
}

function addSecretVersion(projectId, secretId, value) {
  runGcloud(
    [
      "secrets",
      "versions",
      "add",
      secretId,
      `--project=${projectId}`,
      "--data-file=-",
    ],
    { input: value }
  );
}

function accessSecret(projectId, secretId) {
  return runGcloud([
    "secrets",
    "versions",
    "access",
    "latest",
    `--secret=${secretId}`,
    `--project=${projectId}`,
  ]);
}

module.exports = {
  MANAGED_SECRETS,
  secretExists,
  ensureSecret,
  addSecretVersion,
  accessSecret,
};
