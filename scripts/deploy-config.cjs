/**
 * Local manual deploy targets for nucleus.suherman.net.
 */
const path = require("node:path");

const REPO_ROOT = path.resolve(__dirname, "..");
const DEFAULT_BRANCH = process.env.NUCLEUS_DEPLOY_BRANCH || "main";

/** @type {Array<{ repo: string; label: string; branch?: string; npmScript?: string; note?: string; details?: string[] }>} */
const DEPLOY_TARGETS = [
  {
    repo: "nucleus-website",
    label: "nucleus.suherman.net + nucleus-sync.suherman.net",
    branch: DEFAULT_BRANCH,
    npmScript: "deploy:website:direct",
  },
  {
    repo: "nucleus-registry",
    label: "nucleus-registry.suherman.net",
    branch: DEFAULT_BRANCH,
    npmScript: "deploy:registry:direct",
  },
  {
    repo: "nucleus-ai",
    label: "nucleus-ai.suherman.net",
    branch: DEFAULT_BRANCH,
    npmScript: "deploy:ai-overview:direct",
    details: [
      "Requires Nucleus Cloud device token (Bearer nuc_…)",
      "Configure domain from suherman-net-infra: npm run cloudflare:nucleus -- --skip-website --skip-sync --skip-registry --skip-download",
    ],
  },
  {
    repo: "nucleus-app",
    label: "Nucleus macOS DMG",
    branch: DEFAULT_BRANCH,
    npmScript: "release:direct",
    details: [
      "Manual: npm run release",
      "Retry: npm run nucleus:deploy:retry -- --repo nucleus-app",
    ],
  },
  {
    repo: "nucleus-download",
    label: "nucleus-download.suherman.net",
    infraDeploy: true,
    note: "manual",
    details: ["Deploy from suherman-net-infra: npm run cloudflare:nucleus -- --skip-website --skip-sync --skip-registry"],
  },
];

function getDeployTarget(repo) {
  return DEPLOY_TARGETS.find((t) => t.repo === repo) || null;
}

function deployableTargets() {
  return DEPLOY_TARGETS.filter((t) => t.npmScript);
}

module.exports = {
  REPO_ROOT,
  DEFAULT_BRANCH,
  DEPLOY_TARGETS,
  getDeployTarget,
  deployableTargets,
};
