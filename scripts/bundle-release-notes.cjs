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

if (require.main === module) {
  bundleReleaseNotes();
}

module.exports = { bundleReleaseNotes };
