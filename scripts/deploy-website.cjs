/**
 * Deploy the Next.js marketing website + Nucleus Cloud Sync API to Cloud Run.
 */
const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const { getProjectAdcPath } = require("./gcp-lib-adc.cjs");
const { loadDotenv } = require("./load-dotenv.cjs");
const { secretExists } = require("./gcp-secrets.cjs");
const { getDeployTarget } = require("./deploy-config.cjs");
const { recordDirectDeployOutcome } = require("./deploy-record-direct.cjs");

const root = path.join(__dirname, "..");
const websiteDir = path.join(root, "website");
const shell = process.platform === "win32";
const DEPLOY_REPO = "nucleus-website";
const DEPLOY_NPM_SCRIPT = "deploy:website:direct";
const deployTarget = getDeployTarget(DEPLOY_REPO);
const deployStartedAt = new Date().toISOString();

function recordDeploy(status, { exitCode = 0, error = null } = {}) {
  recordDirectDeployOutcome({
    repo: DEPLOY_REPO,
    label: deployTarget?.label,
    npmScript: DEPLOY_NPM_SCRIPT,
    status,
    startedAt: deployStartedAt,
    exitCode,
    error,
  });
}

function fail(message) {
  recordDeploy("failure", { exitCode: 1, error: message });
  console.error(`deploy:website: ${message}`);
  process.exit(1);
}

const SYNC_SECRETS = ["AUTH_SECRET", "GOOGLE_OAUTH_CLIENT_ID", "GOOGLE_OAUTH_CLIENT_SECRET"];
const REQUIRED_SYNC_SECRETS = ["AUTH_SECRET"];
const OPTIONAL_SYNC_SECRETS = ["GOOGLE_OAUTH_CLIENT_ID", "GOOGLE_OAUTH_CLIENT_SECRET"];

function applyGcpEnv() {
  loadDotenv(root);
  const projectAdc = getProjectAdcPath(root);
  if (fs.existsSync(projectAdc)) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = projectAdc;
  }
}

function run(command, args, options = {}) {
  const r = spawnSync(command, args, {
    stdio: "inherit",
    cwd: options.cwd || root,
    shell,
    env: process.env,
  });
  if (r.error) throw r.error;
  if (r.status !== 0) {
    recordDeploy("failure", { exitCode: r.status ?? 1, error: `${command} exited ${r.status ?? 1}` });
    process.exit(r.status ?? 1);
  }
}

function yamlString(value) {
  return JSON.stringify(String(value));
}

function writeRuntimeEnvFile({
  projectId,
  syncBaseUrl,
  oauthRedirectUri,
}) {
  const lines = [
    `GCP_PROJECT_ID: ${yamlString(projectId)}`,
    `WEBSITE_BASE_URL: ${yamlString(syncBaseUrl)}`,
    `GOOGLE_OAUTH_REDIRECT_URI: ${yamlString(oauthRedirectUri)}`,
  ];
  const filePath = path.join(os.tmpdir(), `nucleus-website-env-${process.pid}.yaml`);
  fs.writeFileSync(filePath, `${lines.join("\n")}\n`, "utf8");
  return filePath;
}

function ensureSyncSecrets(projectId) {
  const missingRequired = REQUIRED_SYNC_SECRETS.filter((key) => !secretExists(projectId, key));
  if (missingRequired.length > 0) {
    const unset = missingRequired.filter((key) => !process.env[key]?.trim());
    if (unset.length > 0) {
      fail(
        `Missing required Cloud Sync secret AUTH_SECRET. ` +
          "Generate with: openssl rand -base64 32, add to .env, then npm run seed:secrets",
      );
    }
  }

  const bindings = [];
  const envFallback = [];

  for (const key of SYNC_SECRETS) {
    if (secretExists(projectId, key)) {
      bindings.push(`${key}=${key}:latest`);
      continue;
    }
    if (process.env[key]?.trim()) {
      envFallback.push(`${key}=${process.env[key]}`);
      continue;
    }
    if (OPTIONAL_SYNC_SECRETS.includes(key)) {
      console.warn(`deploy:website: ${key} not set — Google sign-in will be unavailable until configured`);
      continue;
    }
    fail(`Missing required Cloud Sync secret: ${key}`);
  }

  if (bindings.length) {
    return { secretBindings: bindings.join(","), envFallback };
  }

  if (envFallback.length) {
    console.warn(
      "deploy:website: Cloud Sync secrets not in Secret Manager; using .env values for this deploy only.",
    );
  }

  return { secretBindings: null, envFallback };
}

function grantSecretAccessor(projectId, secretId) {
  if (!secretExists(projectId, secretId)) return;
  const projectNumber = spawnSync(
    "gcloud",
    ["projects", "describe", projectId, "--format=value(projectNumber)"],
    { encoding: "utf8", shell },
  );
  if (projectNumber.status !== 0) return;
  const serviceAccount = `${projectNumber.stdout.trim()}-compute@developer.gserviceaccount.com`;
  spawnSync(
    "gcloud",
    [
      "secrets",
      "add-iam-policy-binding",
      secretId,
      `--project=${projectId}`,
      `--member=serviceAccount:${serviceAccount}`,
      "--role=roles/secretmanager.secretAccessor",
      "--quiet",
    ],
    { stdio: "ignore", shell },
  );
}

function main() {
  applyGcpEnv();

  const projectId = resolveGcpProjectId(root);
  if (!projectId) fail("GCP_PROJECT_ID is not set. Run: npm run login");

  const region = process.env.GCP_LOCATION?.trim() || "australia-southeast1";
  const serviceName = process.env.WEBSITE_SERVICE?.trim() || "nucleus-website";
  const registryApiUrl =
    process.env.NEXT_PUBLIC_REGISTRY_API_URL?.trim() ||
    "https://nucleus-registry.suherman.net";
  const downloadBase =
    process.env.PUBLIC_DOWNLOAD_BASE_URL?.trim() ||
    process.env.NEXT_PUBLIC_DOWNLOAD_BASE_URL?.trim() ||
    "https://nucleus-download.suherman.net/downloads";
  const syncBaseUrl =
    process.env.NUCLEUS_SYNC_PUBLIC_URL?.trim() ||
    process.env.WEBSITE_BASE_URL?.trim() ||
    "https://nucleus-sync.suherman.net";
  const oauthRedirectUri =
    process.env.GOOGLE_OAUTH_REDIRECT_URI?.trim() ||
    `${syncBaseUrl}/api/auth/google/callback`;

  const envFile = writeRuntimeEnvFile({
    projectId,
    syncBaseUrl,
    oauthRedirectUri,
  });

  const deployArgs = [
    "run",
    "deploy",
    serviceName,
    "--source",
    websiteDir,
    "--project",
    projectId,
    "--region",
    region,
    "--allow-unauthenticated",
    "--quiet",
    "--env-vars-file",
    envFile,
    "--set-build-env-vars",
    `NEXT_PUBLIC_REGISTRY_API_URL=${registryApiUrl},NEXT_PUBLIC_APP_ID=nucleus-macos,NEXT_PUBLIC_DOWNLOAD_BASE_URL=${downloadBase}`,
  ];

  const { secretBindings, envFallback } = ensureSyncSecrets(projectId);
  if (secretBindings) {
    for (const binding of secretBindings.split(",")) {
      const secretId = binding.split("=")[0];
      grantSecretAccessor(projectId, secretId);
    }
  }
  if (secretBindings) {
    deployArgs.push("--set-secrets", secretBindings);
  }
  if (envFallback.length) {
    deployArgs.push("--set-env-vars", envFallback.join(","));
  }

  console.log(`deploy:website: deploying ${serviceName} to Cloud Run (${region})…`);
  console.log(`deploy:website: sync base URL ${syncBaseUrl}`);
  run("gcloud", deployArgs);

  try {
    fs.unlinkSync(envFile);
  } catch {
    // ignore
  }

  console.log("deploy:website: done");
  console.log(`deploy:website: health check https://${new URL(syncBaseUrl).host}/api/health`);
  recordDeploy("success", { exitCode: 0 });
}

main();
