/**
 * Copy curated release notes for the current app version into the app bundle resources.
 */
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const packageJson = require(path.join(root, "package.json"));
const version = packageJson.version;

const sourcePath = path.join(root, "release-notes", `${version}.json`);
const targetDir = path.join(root, "app/Nucleus/Resources");
const targetPath = path.join(targetDir, "ReleaseNotes.json");
const iosTargetPath = path.join(
  root,
  "nucleus-apple/Apps/NucleusIOS/NucleusIOS/Resources/ReleaseNotes.json"
);

function readIOSMarketingVersion() {
  const projectYml = path.join(root, "nucleus-apple/Apps/NucleusIOS/project.yml");
  if (!fs.existsSync(projectYml)) return null;
  const match = fs.readFileSync(projectYml, "utf8").match(/MARKETING_VERSION:\s*([0-9.]+)/);
  return match?.[1] ?? null;
}

function bundleReleaseNotes(appVersion = version) {
  const curatedPath = path.join(root, "release-notes", `${appVersion}.json`);
  if (!fs.existsSync(curatedPath)) {
    console.warn(`bundle-release-notes: no release-notes/${appVersion}.json — keeping existing bundle file`);
    return false;
  }

  fs.mkdirSync(targetDir, { recursive: true });
  fs.copyFileSync(curatedPath, targetPath);
  console.log(`bundle-release-notes: copied release-notes/${appVersion}.json → app/Nucleus/Resources/ReleaseNotes.json`);
  return true;
}

function bundleIOSReleaseNotes() {
  const iosVersion = readIOSMarketingVersion();
  if (!iosVersion) {
    console.warn("bundle-release-notes: could not read iOS MARKETING_VERSION — skipping iOS ReleaseNotes.json");
    return false;
  }

  const iosSourcePath = path.join(root, "release-notes", `ios-${iosVersion}.json`);
  const fallbackSourcePath = path.join(root, "release-notes", `${iosVersion}.json`);
  const source = fs.existsSync(iosSourcePath)
    ? iosSourcePath
    : fs.existsSync(fallbackSourcePath)
      ? fallbackSourcePath
      : null;

  if (!source) {
    console.warn(
      `bundle-release-notes: no release-notes/ios-${iosVersion}.json or release-notes/${iosVersion}.json — keeping existing iOS bundle file`
    );
    return false;
  }

  fs.mkdirSync(path.dirname(iosTargetPath), { recursive: true });
  fs.copyFileSync(source, iosTargetPath);
  console.log(`bundle-release-notes: copied ${path.relative(root, source)} → nucleus-apple/Apps/NucleusIOS/NucleusIOS/Resources/ReleaseNotes.json`);
  return true;
}

function bundleAllReleaseNotes(appVersion = version) {
  const macCopied = bundleReleaseNotes(appVersion);
  const iosCopied = bundleIOSReleaseNotes();
  return macCopied || iosCopied;
}

if (require.main === module) {
  bundleAllReleaseNotes();
}

module.exports = { bundleReleaseNotes, bundleIOSReleaseNotes, bundleAllReleaseNotes };
