const crypto = require("crypto");

const API_TOKEN_PREFIX = "nuc_";

function hashToken(token) {
  return crypto.createHash("sha256").update(token).digest("hex");
}

function isNucleusCloudToken(token) {
  return typeof token === "string" && token.startsWith(API_TOKEN_PREFIX) && token.length > API_TOKEN_PREFIX.length;
}

module.exports = {
  hashToken,
  isNucleusCloudToken,
  API_TOKEN_PREFIX,
};
