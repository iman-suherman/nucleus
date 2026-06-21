const { hashToken, isNucleusCloudToken } = require("./tokens");
const { COLLECTIONS, getFirestore } = require("./firestore");

function mapApiToken(id, data) {
  return {
    id,
    userId: String(data.userId),
    tokenHash: String(data.tokenHash),
    deviceId: String(data.deviceId),
    deviceName: String(data.deviceName ?? "Nucleus"),
    expiresAt: data.expiresAt?.toDate?.() ?? new Date(data.expiresAt),
    lastUsedAt: data.lastUsedAt?.toDate?.() ?? undefined,
    createdAt: data.createdAt?.toDate?.() ?? new Date(data.createdAt),
  };
}

function mapUser(id, data) {
  return {
    id,
    email: String(data.email ?? ""),
    name: String(data.name ?? ""),
    avatarUrl: String(data.avatarUrl ?? ""),
  };
}

async function getApiTokenByPlainToken(plainToken) {
  const tokenHash = hashToken(plainToken);
  const doc = await getFirestore().collection(COLLECTIONS.apiTokens).doc(tokenHash).get();
  if (!doc.exists) return null;
  return mapApiToken(String(doc.data()?.id ?? doc.id), doc.data() ?? {});
}

async function getUserById(userId) {
  const doc = await getFirestore().collection(COLLECTIONS.users).doc(userId).get();
  if (!doc.exists) return null;
  return mapUser(doc.id, doc.data() ?? {});
}

async function touchApiToken(tokenHash) {
  await getFirestore()
    .collection(COLLECTIONS.apiTokens)
    .doc(tokenHash)
    .set({ lastUsedAt: new Date() }, { merge: true });
}

async function authenticateNucleusCloud(authorizationHeader) {
  if (!authorizationHeader?.startsWith("Bearer ")) {
    return null;
  }

  const plainToken = authorizationHeader.slice("Bearer ".length).trim();
  if (!isNucleusCloudToken(plainToken)) {
    return null;
  }

  const tokenRow = await getApiTokenByPlainToken(plainToken);
  if (!tokenRow || tokenRow.expiresAt <= new Date()) {
    return null;
  }

  const user = await getUserById(tokenRow.userId);
  if (!user) return null;

  await touchApiToken(tokenRow.tokenHash);

  return {
    id: user.id,
    email: user.email,
    name: user.name,
    avatarUrl: user.avatarUrl,
    deviceId: tokenRow.deviceId,
    deviceName: tokenRow.deviceName,
  };
}

module.exports = {
  authenticateNucleusCloud,
};
