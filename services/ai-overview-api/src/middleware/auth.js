const { config } = require("../config");
const { authenticateNucleusCloud } = require("../auth/nucleus-cloud");

async function requireNucleusCloudAuth(req, res, next) {
  if (!config.auth.required) {
    next();
    return;
  }

  try {
    const user = await authenticateNucleusCloud(req.headers.authorization);
    if (!user) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }
    req.nucleusUser = user;
    next();
  } catch (error) {
    console.error("Nucleus Cloud auth failed:", error);
    res.status(503).json({ error: "Authentication service unavailable" });
  }
}

module.exports = {
  requireNucleusCloudAuth,
};
