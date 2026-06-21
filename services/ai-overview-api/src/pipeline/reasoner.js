const { config } = require("../config");
const { completeJson } = require("../llm/client");

const GROUNDED_REASONER_SYSTEM = `You are an expert assistant writing a concise AI overview.
Answer the question directly and confidently when you have reliable knowledge from web grounding or well-established facts.
Use high or medium confidence for clear facts (events, places, dates, people, definitions).
Use low confidence only when information is genuinely uncertain, disputed, or unavailable.
Do not refuse to answer when the facts are widely known.
Return ONLY JSON:
{
  "summary": "2-4 sentence overview",
  "sections": [{ "title": "section", "body": "details", "citations": [] }],
  "confidence": "high|medium|low",
  "followUpQuestions": ["question"]
}`;

function fallbackAnswer(question, evidence) {
  if (evidence.length === 0) {
    return {
      summary: "I couldn't find enough information to answer that question right now.",
      sections: [],
      confidence: "low",
      followUpQuestions: ["Can you rephrase the question or add more context?"],
    };
  }

  return {
    summary: `Based on ${evidence.length} retrieved source(s), here is what is known about: ${question}`,
    sections: evidence.slice(0, 4).map((item) => ({
      title: item.title || item.source,
      body: item.claim,
      citations: [item.evidenceId].filter(Boolean),
    })),
    confidence: "medium",
    followUpQuestions: [],
  };
}

async function reasonWithGrounding(question) {
  const payload = await completeJson({
    model: config.llm.reasonerModel,
    system: GROUNDED_REASONER_SYSTEM,
    user: `Question:\n${question}`,
    temperature: config.llm.temperature.reasoner,
    googleSearch: config.llm.googleSearchGrounding,
  });
  return normalizeAnswer(payload);
}

async function reasonAnswer({ question, plan, evidence, compressedEvidence }) {
  if (!compressedEvidence) {
    if (config.llm.enabled) {
      try {
        const answer = await reasonWithGrounding(question);
        if (answer.summary) return answer;
      } catch (error) {
        return { ...fallbackAnswer(question, evidence), reasonerError: error.message };
      }
    }
    return fallbackAnswer(question, evidence);
  }

  try {
    const evidenceIds = evidence.map((item) => item.evidenceId).filter(Boolean);
    const payload = await completeJson({
      model: config.llm.reasonerModel,
      system: `You are an expert assistant writing a Google AI Overview-style answer.
Return ONLY JSON:
{
  "summary": "2-4 sentence overview",
  "sections": [
    { "title": "Main reasons|Key points|Impact", "body": "paragraph with numbered points if useful", "citations": ["evidence-id"] }
  ],
  "confidence": "high|medium|low",
  "followUpQuestions": ["question"]
}
Rules:
- Use the supplied evidence and answer confidently when it supports a clear conclusion.
- Every section must cite one or more evidence IDs from: ${evidenceIds.join(", ") || "none"}
- Do not invent sources or facts.
- Prefer clear structure: summary, main reasons, confidence.`,
      user: `Question:\n${question}\n\nEvidence:\n${compressedEvidence}\n\nEvidence IDs:\n${JSON.stringify(evidence, null, 2)}`,
      temperature: config.llm.temperature.reasoner,
    });
    return normalizeAnswer(payload);
  } catch (error) {
    return { ...fallbackAnswer(question, evidence), reasonerError: error.message };
  }
}

function normalizeAnswer(payload) {
  return {
    summary: String(payload.summary || "").trim(),
    sections: Array.isArray(payload.sections)
      ? payload.sections.map((section) => ({
          title: String(section.title || "Details").trim(),
          body: String(section.body || "").trim(),
          citations: Array.isArray(section.citations) ? section.citations.map(String) : [],
        }))
      : [],
    confidence: ["high", "medium", "low"].includes(payload.confidence) ? payload.confidence : "medium",
    followUpQuestions: Array.isArray(payload.followUpQuestions)
      ? payload.followUpQuestions.slice(0, config.pipeline.maxFollowUpQuestions).map(String)
      : [],
  };
}

module.exports = {
  reasonAnswer,
  fallbackAnswer,
};
