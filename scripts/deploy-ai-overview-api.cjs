/**
 * Deploy the AI Overview API to Cloud Run.
 */
const { spawnSync } = require("child_process");
const path = require("path");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
const { loadDotenv } = require("./load-dotenv.cjs");
const { getDeployTarget } = require("./deploy-config.cjs");
const { recordDirectDeployOutcome } = require("./deploy-record-direct.cjs");
const { secretExists } = require("./gcp-secrets.cjs");

const root = path.join(__dirname, "..");
const serviceDir = path.join(root, "services", "ai-overview-api");
const shell = process.platform === "win32";
const DEPLOY_REPO = "nucleus-ai";
const DEPLOY_NPM_SCRIPT = "deploy:ai-overview:direct";
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
  console.error(`deploy:ai-overview: ${message}`);
  process.exit(1);
}

function run(command, args, options = {}) {
  const r = spawnSync(command, args, {
    stdio: options.quiet ? "pipe" : "inherit",
    cwd: options.cwd || root,
    shell,
    env: process.env,
    encoding: options.quiet ? "utf8" : undefined,
  });
  if (r.error) throw r.error;
  if (r.status !== 0) {
    if (options.allowFailure) return null;
    recordDeploy("failure", { exitCode: r.status ?? 1, error: `${command} exited ${r.status ?? 1}` });
    process.exit(r.status ?? 1);
  }
  return options.quiet ? (r.stdout || "").trim() : "";
}

function readSecret(projectId, secretId) {
  if (!secretExists(projectId, secretId)) return "";
  return run(
    "gcloud",
    ["secrets", "versions", "access", "latest", `--secret=${secretId}`, `--project=${projectId}`],
    { quiet: true, allowFailure: true },
  );
}

function grantSecretAccessor(projectId, secretId) {
  const projectNumber = run(
    "gcloud",
    ["projects", "describe", projectId, "--format=value(projectNumber)"],
    { quiet: true },
  );
  if (!projectNumber) return;
  run(
    "gcloud",
    [
      "secrets",
      "add-iam-policy-binding",
      secretId,
      `--project=${projectId}`,
      `--member=serviceAccount:${projectNumber}-compute@developer.gserviceaccount.com`,
      "--role=roles/secretmanager.secretAccessor",
      "--quiet",
    ],
    { allowFailure: true },
  );
}

function grantVertexAccess(projectId) {
  const projectNumber = run(
    "gcloud",
    ["projects", "describe", projectId, "--format=value(projectNumber)"],
    { quiet: true },
  );
  if (!projectNumber) return;

  run(
    "gcloud",
    [
      "projects",
      "add-iam-policy-binding",
      projectId,
      `--member=serviceAccount:${projectNumber}-compute@developer.gserviceaccount.com`,
      "--role=roles/aiplatform.user",
      "--quiet",
    ],
    { allowFailure: true },
  );
}

function enableVertexApi(projectId) {
  run(
    "gcloud",
    ["services", "enable", "aiplatform.googleapis.com", `--project=${projectId}`, "--quiet"],
    { allowFailure: true },
  );
}

function describeServiceUrl(projectId, region, serviceName) {
  return run(
    "gcloud",
    [
      "run",
      "services",
      "describe",
      serviceName,
      "--project",
      projectId,
      "--region",
      region,
      "--format=value(status.url)",
    ],
    { quiet: true, allowFailure: true },
  );
}

function printDomainInstructions(publicHost, serviceUrl) {
  if (!serviceUrl) return;
  console.log("");
  console.log("deploy:ai-overview: domain setup");
  console.log(`  Public URL target: https://${publicHost}`);
  console.log(`  Cloud Run URL:     ${serviceUrl}`);
  console.log("");
  console.log("  Configure Cloudflare (suherman-net-infra):");
  console.log(`    CNAME ${publicHost} -> ${new URL(serviceUrl).host}`);
  console.log("    Proxy enabled (orange cloud), SSL Full");
  console.log("");
  console.log("  Or from suherman-net-infra:");
  console.log("    npm run cloudflare:nucleus -- --skip-website --skip-sync --skip-registry --skip-download");
}

function main() {
  loadDotenv(root);
  applyGcpEnv(root);

  const projectId = resolveGcpProjectId(root);
  if (!projectId) fail("GCP_PROJECT_ID is not set. Run: npm run login");

  const region = process.env.GCP_LOCATION?.trim() || "australia-southeast1";
  const vertexLocation = process.env.VERTEX_LOCATION?.trim() || "us-central1";
  const serviceName = process.env.AI_OVERVIEW_API_SERVICE?.trim() || "nucleus-ai-overview-api";
  const publicUrl =
    process.env.AI_OVERVIEW_PUBLIC_URL?.trim() ||
    process.env.NEXT_PUBLIC_AI_OVERVIEW_API_URL?.trim() ||
    "https://nucleus-ai.suherman.net";
  const publicHost = new URL(publicUrl).host;

  const llmProvider = process.env.LLM_PROVIDER?.trim() || "vertex";
  const llmBaseUrl =
    process.env.LLM_BASE_URL?.trim() ||
    readSecret(projectId, "AI_OVERVIEW_LLM_BASE_URL") ||
    readSecret(projectId, "LLM_BASE_URL") ||
    "";
  const llmApiKey =
    process.env.LLM_API_KEY?.trim() ||
    readSecret(projectId, "AI_OVERVIEW_LLM_API_KEY") ||
    readSecret(projectId, "LLM_API_KEY") ||
    "";
  const serperApiKey =
    process.env.SERPER_API_KEY?.trim() || readSecret(projectId, "SERPER_API_KEY") || "";
  const braveApiKey =
    process.env.BRAVE_SEARCH_API_KEY?.trim() || readSecret(projectId, "BRAVE_SEARCH_API_KEY") || "";
  const githubToken =
    process.env.GITHUB_TOKEN?.trim() || readSecret(projectId, "GITHUB_TOKEN") || "";

  const plannerModel = process.env.PLANNER_MODEL?.trim() || "gemini-2.5-flash";
  const reasonerModel = process.env.REASONER_MODEL?.trim() || "gemini-2.5-pro";
  const contextModel = process.env.CONTEXT_MODEL?.trim() || plannerModel;
  const verifierModel = process.env.VERIFIER_MODEL?.trim() || plannerModel;
  const googleSearchGrounding = process.env.VERTEX_GOOGLE_SEARCH_GROUNDING?.trim() || "true";

  if (llmProvider === "vertex") {
    console.log(`deploy:ai-overview: enabling Vertex AI (${vertexLocation})…`);
    enableVertexApi(projectId);
    grantVertexAccess(projectId);
  }

  const envPairs = [
    `GCP_PROJECT_ID=${projectId}`,
    `AI_OVERVIEW_PUBLIC_URL=${publicUrl}`,
    `NUCLEUS_CLOUD_AUTH_REQUIRED=true`,
    `LLM_PROVIDER=${llmProvider}`,
    `VERTEX_LOCATION=${vertexLocation}`,
    `VERTEX_GOOGLE_SEARCH_GROUNDING=${googleSearchGrounding}`,
    `PLANNER_MODEL=${plannerModel}`,
    `CONTEXT_MODEL=${contextModel}`,
    `REASONER_MODEL=${reasonerModel}`,
    `VERIFIER_MODEL=${verifierModel}`,
    `ENABLE_VERIFIER=true`,
  ];

  const secretBindings = [];

  if (llmProvider === "openai" && llmBaseUrl) envPairs.push(`LLM_BASE_URL=${llmBaseUrl}`);
  if (llmProvider === "openai" && llmApiKey) {
    if (secretExists(projectId, "AI_OVERVIEW_LLM_API_KEY")) {
      grantSecretAccessor(projectId, "AI_OVERVIEW_LLM_API_KEY");
      secretBindings.push("AI_OVERVIEW_LLM_API_KEY=AI_OVERVIEW_LLM_API_KEY:latest");
    } else {
      envPairs.push(`LLM_API_KEY=${llmApiKey}`);
    }
  }
  if (serperApiKey) envPairs.push(`SERPER_API_KEY=${serperApiKey}`);
  if (braveApiKey) envPairs.push(`BRAVE_SEARCH_API_KEY=${braveApiKey}`);
  if (githubToken) envPairs.push(`GITHUB_TOKEN=${githubToken}`);

  const deployArgs = [
    "run",
    "deploy",
    serviceName,
    "--source",
    serviceDir,
    "--project",
    projectId,
    "--region",
    region,
    "--allow-unauthenticated",
    "--timeout",
    "300",
    "--memory",
    "1Gi",
    "--cpu",
    "1",
    "--quiet",
    "--set-env-vars",
    envPairs.join(","),
  ];

  if (secretBindings.length > 0) {
    deployArgs.push("--set-secrets", secretBindings.join(","));
  }

  console.log(`deploy:ai-overview: deploying ${serviceName} to Cloud Run (${region})…`);
  console.log(`deploy:ai-overview: public URL ${publicUrl}`);
  console.log(`deploy:ai-overview: LLM provider ${llmProvider} (${reasonerModel} @ ${vertexLocation})`);
  console.log("deploy:ai-overview: auth requires Nucleus Cloud Bearer token (nuc_…)");
  run("gcloud", deployArgs);

  const serviceUrl = describeServiceUrl(projectId, region, serviceName);
  printDomainInstructions(publicHost, serviceUrl);

  console.log("deploy:ai-overview: done");
  if (serviceUrl) {
    console.log(`deploy:ai-overview: health check ${serviceUrl}/health`);
  }
  recordDeploy("success", { exitCode: 0 });
}

main();
