const { config } = require("../config");
const { planQuestion } = require("./planner");
const { runPlannedSearches } = require("../search");
const { buildContext } = require("./context-builder");
const { reasonAnswer } = require("./reasoner");
const { verifyCitations } = require("./citation-checker");

async function runOverviewPipeline(input) {
  const startedAt = Date.now();
  const question = String(input.question || "").trim();
  if (!question) {
    const error = new Error("question is required");
    error.status = 400;
    throw error;
  }

  const localData = input.localData || {};
  const requestedSources = Array.isArray(input.sources) ? input.sources : [];
  const hints = input.hints || {};

  const plan = await planQuestion({ question, localData, hints });

  const searchRuns = await runPlannedSearches(plan, localData, requestedSources);
  const context = await buildContext({ question, plan, searchRuns });
  const draftAnswer = await reasonAnswer({
    question,
    plan,
    evidence: context.evidence,
    compressedEvidence: context.compressedEvidence,
  });
  const verification = await verifyCitations({
    question,
    answer: draftAnswer,
    evidence: context.evidence,
  });

  const latencyMs = Date.now() - startedAt;

  return {
    question,
    plan,
    searches: searchRuns,
    evidence: context.evidence,
    answer: verification.adjustedAnswer,
    citations: verification.citations,
    warnings: verification.warnings,
    unsupportedClaims: verification.unsupportedClaims,
    meta: {
      analyzedAt: new Date().toISOString(),
      latencyMs,
      rawResultCount: context.rawResultCount,
      models: {
        provider: config.llm.provider,
        planner: config.llm.plannerModel,
        context: config.llm.contextModel,
        reasoner: config.llm.reasonerModel,
        verifier: config.pipeline.enableVerifier ? config.llm.verifierModel : null,
        vertexLocation: config.llm.provider === "vertex" ? config.llm.vertex.location : null,
        googleSearchGrounding: config.llm.googleSearchGrounding,
      },
      errors: compactErrors({
        planner: plan.plannerError,
        context: context.contextError,
        reasoner: draftAnswer.reasonerError,
        verifier: verification.verifierError,
      }),
    },
  };
}

function compactErrors(errors) {
  return Object.fromEntries(Object.entries(errors).filter(([, value]) => Boolean(value)));
}

module.exports = {
  runOverviewPipeline,
};
