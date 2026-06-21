const { config } = require("../config");
const { completeJson } = require("../llm/client");

function buildCitationIndex(evidence) {
  const byId = new Map();
  for (const item of evidence) {
    if (item.evidenceId) byId.set(item.evidenceId, item);
  }
  return byId;
}

function heuristicCitationCheck(answer, evidence) {
  const index = buildCitationIndex(evidence);
  const citations = [];
  const warnings = [];
  const validIds = new Set(index.keys());

  for (const section of answer.sections || []) {
    for (const citationId of section.citations || []) {
      const source = index.get(citationId);
      if (source) {
        citations.push({
          statement: section.body,
          evidenceId: citationId,
          source: source.source,
          title: source.title,
          url: source.url,
        });
      } else if (citationId) {
        warnings.push(`Section "${section.title}" cites unknown evidence ID: ${citationId}`);
      }
    }
  }

  if (answer.sections?.length && citations.length === 0 && evidence.length > 0) {
    warnings.push("Answer sections did not include valid evidence citations; attaching top evidence instead.");
    for (const item of evidence.slice(0, 3)) {
      citations.push({
        statement: item.claim,
        evidenceId: item.evidenceId,
        source: item.source,
        title: item.title,
        url: item.url,
      });
    }
  }

  return {
    citations,
    warnings,
    unsupportedClaims: [],
    adjustedAnswer: answer,
    validEvidenceIds: [...validIds],
  };
}

async function verifyCitations({ question, answer, evidence }) {
  const heuristic = heuristicCitationCheck(answer, evidence);
  if (!config.pipeline.enableVerifier || evidence.length === 0) {
    return heuristic;
  }

  try {
    const payload = await completeJson({
      model: config.llm.verifierModel,
      system: `You verify AI overview answers against evidence.
Return ONLY JSON:
{
  "unsupportedClaims": ["claim"],
  "warnings": ["warning"],
  "citations": [
    { "statement": "sentence", "evidenceId": "id", "source": "source", "title": "title", "url": "url or null" }
  ],
  "confidenceAdjustment": "high|medium|low|null"
}
Rules:
- Flag statements not supported by evidence.
- Map supported statements to evidence IDs.
- Never invent new facts.`,
      user: `Question:\n${question}\n\nAnswer:\n${JSON.stringify(answer, null, 2)}\n\nEvidence:\n${JSON.stringify(evidence, null, 2)}`,
      temperature: config.llm.temperature.verifier,
    });

    const citations = Array.isArray(payload.citations) ? payload.citations : heuristic.citations;
    const warnings = [
      ...heuristic.warnings,
      ...(Array.isArray(payload.warnings) ? payload.warnings : []),
    ];
    const unsupportedClaims = Array.isArray(payload.unsupportedClaims) ? payload.unsupportedClaims : [];

    const adjustedAnswer = { ...answer };
    if (payload.confidenceAdjustment && ["high", "medium", "low"].includes(payload.confidenceAdjustment)) {
      adjustedAnswer.confidence = payload.confidenceAdjustment;
    }
    if (unsupportedClaims.length > 0 && adjustedAnswer.confidence === "high") {
      adjustedAnswer.confidence = "medium";
    }

    return {
      citations,
      warnings,
      unsupportedClaims,
      adjustedAnswer,
      validEvidenceIds: heuristic.validEvidenceIds,
    };
  } catch (error) {
    return { ...heuristic, verifierError: error.message };
  }
}

module.exports = {
  verifyCitations,
  heuristicCitationCheck,
};
