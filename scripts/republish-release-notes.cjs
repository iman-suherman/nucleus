/**
 * Regenerate release note artifacts and update Firestore for one or more versions
 * without rebuilding the app. Use after fixing curated release-notes/*.json files.
 */
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { loadDotenv } = require("./load-dotenv.cjs");
const { applyGcpEnv } = require("./apply-gcp-env.cjs");
const { resolveGcpProjectId } = require("./gcp-config.cjs");
const { generateReleaseNotes, writeReleaseArtifacts } = require("./generate-release-notes.cjs");
const { registerPluginVersion } = require("./register-version.cjs");
const { generateAppcast, sparkleReleaseNotesHtml } = require("./generate-appcast.cjs");
const { resolveDownloadBase, publicSparkleDownloadUrl } = require("./public-download-url.cjs");
const { bundleReleaseNotes } = require("./bundle-release-notes.cjs");

const root = path.join(__dirname, "..");
const shell = process.platform === "win32";

function run(command, args) {
  const r = spawnSync(command, args, {
    stdio: "inherit",
    cwd: root,
    shell,
    env: process.env,
  });
  if (r.error) throw r.error;
  if (r.status !== 0) process.exit(r.status ?? 1);
}

function resolveBucket(projectId) {
  return process.env.GCS_APP_BUCKET?.trim() || `${projectId}-nucleus`;
}

function resolvePrefix() {
  return (process.env.GCS_APP_PREFIX?.trim() || "releases").replace(/^\/+|\/+$/g, "");
}

function resolveAppId() {
  const packageJson = require(path.join(root, "package.json"));
  return process.env.DEFAULT_APP_ID?.trim() || packageJson.name;
}

function previousTagFor(version) {
  const tags = spawnSync("git", ["tag", "--list", "v*", "--sort=-v:refname"], {
    cwd: root,
    encoding: "utf8",
    shell,
  })
    .stdout.trim()
    .split("\n")
    .filter(Boolean);

  const current = `v${version}`;
  const index = tags.indexOf(current);
  if (index >= 0 && tags[index + 1]) return tags[index + 1];
  return null;
}

async function republishVersion(version) {
  const appId = resolveAppId();
  const previousTag = previousTagFor(version);
  const release = generateReleaseNotes({
    version,
    previousTag,
    previousLabel: previousTag || "initial release",
    pluginId: appId,
  });

  const artifacts = writeReleaseArtifacts(release);
  console.log(`republish: wrote ${artifacts.jsonPath}`);

  const sparkleDir = path.join(root, "releases", "sparkle");
  const htmlPath = path.join(sparkleDir, `Nucleus-${version}.html`);
  fs.mkdirSync(sparkleDir, { recursive: true });
  fs.writeFileSync(htmlPath, sparkleReleaseNotesHtml(release), "utf8");
  console.log(`republish: wrote ${htmlPath}`);

  const projectId = resolveGcpProjectId(root);
  if (!projectId) {
    console.warn("republish: GCP_PROJECT_ID not set — skipping cloud upload");
    return release;
  }

  const bucket = resolveBucket(projectId);
  const prefix = resolvePrefix();
  const dmgName = `${appId}-${version}.dmg`;
  const sparkleZipName = `Nucleus-${version}.zip`;
  const objectPath = `${prefix}/${version}/${dmgName}`;
  const latestObjectPath = `${prefix}/latest/${dmgName}`;
  const sparkleObjectPath = `${prefix}/${version}/${sparkleZipName}`;
  const sparkleLatestObjectPath = `${prefix}/latest/${sparkleZipName}`;
  const releaseNotesObjectPath = `${prefix}/${version}/release-${version}.json`;
  const releaseNotesMarkdownPath = `${prefix}/${version}/release-${version}.md`;

  run("gcloud", [
    "storage",
    "cp",
    artifacts.jsonPath,
    `gs://${bucket}/${releaseNotesObjectPath}`,
    "--project",
    projectId,
  ]);
  run("gcloud", [
    "storage",
    "cp",
    artifacts.mdPath,
    `gs://${bucket}/${releaseNotesMarkdownPath}`,
    "--project",
    projectId,
  ]);

  await registerPluginVersion({
    release,
    bucket,
    objectPath,
    latestObjectPath,
    releaseNotesObjectPath,
    sparkleObjectPath: fs.existsSync(path.join(sparkleDir, sparkleZipName))
      ? sparkleObjectPath
      : null,
    sparkleLatestObjectPath: fs.existsSync(path.join(sparkleDir, sparkleZipName))
      ? sparkleLatestObjectPath
      : null,
    sparkleDownloadUrl: fs.existsSync(path.join(sparkleDir, sparkleZipName))
      ? publicSparkleDownloadUrl({ version })
      : null,
    appcastObjectPath: `${prefix}/appcast.xml`,
    publishedBy: process.env.GCP_USER_EMAIL || "republish-release-notes",
  });

  console.log(`republish: updated Firestore for v${version}`);
  return release;
}

async function main() {
  loadDotenv(root);
  applyGcpEnv(root);
  process.env.SPARKLE_LOCAL = "0";
  process.env.LOCAL_RELEASE = "0";

  const versionsArg = process.argv.slice(2).join(" ").trim();
  const packageJson = require(path.join(root, "package.json"));
  const versions = versionsArg
    ? versionsArg.split(/[\s,]+/).filter(Boolean)
    : [packageJson.version];

  for (const version of versions) {
    await republishVersion(version);
  }

  if (versions.includes(packageJson.version)) {
    bundleReleaseNotes(packageJson.version);
  }

  const latest = versions[0];
  const latestRelease = generateReleaseNotes({
    version: latest,
    previousTag: previousTagFor(latest),
    pluginId: resolveAppId(),
  });
  const appcastArtifacts = generateAppcast({
    release: latestRelease,
    downloadBase: resolveDownloadBase({ ...process.env, SPARKLE_LOCAL: "0", LOCAL_RELEASE: "0" }),
  });

  const projectId = resolveGcpProjectId(root);
  if (projectId && fs.existsSync(appcastArtifacts.appcastPath)) {
    const bucket = resolveBucket(projectId);
    const prefix = resolvePrefix();
    run("gcloud", [
      "storage",
      "cp",
      appcastArtifacts.appcastPath,
      `gs://${bucket}/${prefix}/appcast.xml`,
      "--project",
      projectId,
    ]);
    console.log(`republish: uploaded appcast → gs://${bucket}/${prefix}/appcast.xml`);
  }

  console.log("republish: done");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
