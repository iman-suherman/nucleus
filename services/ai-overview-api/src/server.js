const express = require("express");
const { config } = require("./config");
const { requireNucleusCloudAuth } = require("./middleware/auth");
const { runOverviewPipeline } = require("./pipeline/orchestrator");
const { planQuestion } = require("./pipeline/planner");

const app = express();
const port = config.port;

app.use(express.json({ limit: "2mb" }));
app.use((_req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", config.corsOrigin);
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (_req.method === "OPTIONS") {
    res.status(204).end();
    return;
  }
  next();
});

app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    service: "nucleus-ai-overview-api",
    publicUrl: config.publicUrl,
    authRequired: config.auth.required,
    llmEnabled: config.llm.enabled,
    llmProvider: config.llm.provider,
    llmBaseUrl: config.llm.provider === "openai" && config.llm.enabled ? config.llm.baseUrl : null,
    vertex: config.llm.provider === "vertex"
      ? {
          projectId: config.llm.vertex.projectId || null,
          location: config.llm.vertex.location,
          googleSearchGrounding: config.llm.googleSearchGrounding,
        }
      : null,
    models: {
      planner: config.llm.plannerModel,
      reasoner: config.llm.reasonerModel,
    },
  });
});

app.post("/api/v1/overview/plan", requireNucleusCloudAuth, async (req, res, next) => {
  try {
    const question = String(req.body?.question || "").trim();
    if (!question) {
      res.status(400).json({ error: "question is required" });
      return;
    }
    const plan = await planQuestion({
      question,
      localData: req.body?.localData || {},
      hints: req.body?.hints || {},
    });
    res.json({ plan });
  } catch (err) {
    next(err);
  }
});

app.post("/api/v1/overview/ask", requireNucleusCloudAuth, async (req, res, next) => {
  try {
    const result = await runOverviewPipeline({
      question: req.body?.question,
      localData: req.body?.localData,
      sources: req.body?.sources,
      hints: req.body?.hints,
    });
    res.json(result);
  } catch (err) {
    next(err);
  }
});

app.use((err, _req, res, _next) => {
  console.error(err);
  const status = err.status || 500;
  res.status(status).json({ error: err.message || "Internal server error" });
});

app.listen(port, () => {
  console.log(`ai-overview-api listening on :${port}`);
  console.log(`LLM provider: ${config.llm.provider}`);
  if (config.llm.provider === "vertex") {
    console.log(`Vertex AI: ${config.llm.vertex.projectId} @ ${config.llm.vertex.location}`);
  } else if (config.llm.enabled) {
    console.log(`LLM base URL: ${config.llm.baseUrl}`);
  }
});
