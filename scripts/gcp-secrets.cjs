/**
 * GCP Secret Manager helpers for Nucleus local .env generation.
 */
const fs = require("fs");
const { spawnSync } = require("child_process");

/** Env keys stored in Secret Manager (secret id matches env key). */
const MANAGED_SECRETS = [
  "CLOUDKIT_MANAGEMENT_TOKEN",
  "AUTH_SECRET",
  "GOOGLE_OAUTH_CLIENT_ID",
  "GOOGLE_OAUTH_CLIENT_SECRET",
];

/**
 * Binary files stored in Secret Manager and materialized on disk by generate-env.
 * secretId: GCP Secret Manager secret name (stores base64-encoded file contents)
 * envKey: .env key holding repo-relative output path
 * outputPath: repo-relative file path written by generate-env
 */
const MANAGED_FILE_SECRETS = [
  {
    secretId: "NUCLEUS_DEVELOPER_ID_PROVISIONING_PROFILE",
    envKey: "MACOS_DEVELOPER_ID_PROVISIONING_PROFILE",
    outputPath: "app/Nucleus/Nucleus_DeveloperID.provisionprofile",
    encoding: "base64",
  },
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

function addSecretVersionFromFile(projectId, secretId, filePath, { encoding = "binary" } = {}) {
  const value = fs.readFileSync(filePath);
  const payload = encoding === "base64" ? value.toString("base64") : value;
  if (encoding === "base64") {
    addSecretVersion(projectId, secretId, payload);
    return;
  }

  const result = spawnSync(
    "gcloud",
    [
      "secrets",
      "versions",
      "add",
      secretId,
      `--project=${projectId}`,
      "--data-file=-",
    ],
    { input: payload, stdio: ["pipe", "pipe", "pipe"] }
  );
  if (result.status !== 0) {
    const message = (result.stderr || result.stdout || "").toString().trim();
    throw new Error(message || `gcloud secrets versions add failed for ${secretId}`);
  }
}

module.exports = {
  MANAGED_SECRETS,
  MANAGED_FILE_SECRETS,
  secretExists,
  ensureSecret,
  addSecretVersion,
  addSecretVersionFromFile,
  accessSecret,
};
