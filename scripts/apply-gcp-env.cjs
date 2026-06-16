const { loadDotenv } = require("./load-dotenv.cjs");
const { resolveAdcPath } = require("./gcp-lib-adc.cjs");

function applyGcpEnv(repoRoot) {
  loadDotenv(repoRoot);

  const adcPath = resolveAdcPath(repoRoot);
  if (adcPath) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = adcPath;
    return;
  }

  delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
}

module.exports = { applyGcpEnv };
