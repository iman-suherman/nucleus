function readBool(value, fallback = false) {
  if (value == null || value === "") return fallback;
  return ["1", "true", "yes", "on"].includes(String(value).trim().toLowerCase());
}

function readList(value, fallback = []) {
  if (!value || !String(value).trim()) return fallback;
  return String(value)
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

const projectId = process.env.GCP_PROJECT_ID?.trim() || process.env.GOOGLE_CLOUD_PROJECT?.trim() || "";
const llmBaseUrl =
  process.env.LLM_BASE_URL?.trim() ||
  process.env.OLLAMA_BASE_URL?.trim() ||
  "";
const llmProvider = (() => {
  const explicit = process.env.LLM_PROVIDER?.trim().toLowerCase();
  if (explicit) return explicit;
  if (process.env.K_SERVICE) return "vertex";
  if (llmBaseUrl) return "openai";
  return projectId ? "vertex" : "none";
})();

const isVertex = llmProvider === "vertex";
const isOpenAi = llmProvider === "openai";

const defaultPlannerModel = isVertex ? "gemini-2.5-flash" : "qwen3:8b";
const defaultReasonerModel = isVertex ? "gemini-2.5-pro" : "qwen3:32b";

const config = {
  port: Number(process.env.PORT || 8080),
  corsOrigin: process.env.CORS_ORIGIN?.trim() || "*",
  publicUrl: process.env.AI_OVERVIEW_PUBLIC_URL?.trim() || "https://nucleus-ai.suherman.net",

  auth: {
    required: readBool(
      process.env.NUCLEUS_CLOUD_AUTH_REQUIRED,
      Boolean(process.env.K_SERVICE),
    ),
  },

  llm: {
    provider: llmProvider,
    enabled:
      (isVertex && Boolean(projectId)) ||
      (isOpenAi && Boolean(llmBaseUrl)),
    baseUrl: llmBaseUrl || "http://127.0.0.1:11434",
    apiKey: process.env.LLM_API_KEY?.trim() || "",
    vertex: {
      projectId,
      location: process.env.VERTEX_LOCATION?.trim() || process.env.GCP_LOCATION?.trim() || "us-central1",
    },
    plannerModel: process.env.PLANNER_MODEL?.trim() || defaultPlannerModel,
    contextModel:
      process.env.CONTEXT_MODEL?.trim() || process.env.PLANNER_MODEL?.trim() || defaultPlannerModel,
    reasonerModel: process.env.REASONER_MODEL?.trim() || defaultReasonerModel,
    verifierModel:
      process.env.VERIFIER_MODEL?.trim() || process.env.PLANNER_MODEL?.trim() || defaultPlannerModel,
    googleSearchGrounding: readBool(process.env.VERTEX_GOOGLE_SEARCH_GROUNDING, true),
    timeoutMs: Number(process.env.LLM_TIMEOUT_MS || 120_000),
    temperature: {
      planner: Number(process.env.PLANNER_TEMPERATURE ?? 0.1),
      context: Number(process.env.CONTEXT_TEMPERATURE ?? 0.2),
      reasoner: Number(process.env.REASONER_TEMPERATURE ?? 0.3),
      verifier: Number(process.env.VERIFIER_TEMPERATURE ?? 0.1),
    },
  },

  search: {
    enabledSources: readList(process.env.SEARCH_SOURCES, [
      "web",
      "news",
      "wikipedia",
      "reddit",
      "github",
    ]),
    maxResultsPerSource: Number(process.env.SEARCH_MAX_RESULTS || 5),
    timeoutMs: Number(process.env.SEARCH_TIMEOUT_MS || 12_000),
    githubToken: process.env.GITHUB_TOKEN?.trim() || "",
    serperApiKey: process.env.SERPER_API_KEY?.trim() || "",
    braveApiKey: process.env.BRAVE_SEARCH_API_KEY?.trim() || "",
  },

  pipeline: {
    enableVerifier: readBool(process.env.ENABLE_VERIFIER, true),
    maxEvidenceItems: Number(process.env.MAX_EVIDENCE_ITEMS || 12),
    maxFollowUpQuestions: Number(process.env.MAX_FOLLOW_UP_QUESTIONS || 3),
  },
};

module.exports = { config };
