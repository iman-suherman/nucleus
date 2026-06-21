const { Firestore } = require("@google-cloud/firestore");

const COLLECTIONS = {
  users: "nucleus_sync_users",
  apiTokens: "nucleus_sync_api_tokens",
};

let firestore;

function clearLocalCredentialsInCloudRun() {
  if (!process.env.K_SERVICE) return;
  delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
}

function getFirestore() {
  if (!firestore) {
    clearLocalCredentialsInCloudRun();
    const projectId = process.env.GCP_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT;
    firestore = new Firestore(projectId ? { projectId } : undefined);
  }
  return firestore;
}

module.exports = {
  COLLECTIONS,
  getFirestore,
};
