const { config } = require("../config");
const { completeJson, completeText } = require("../llm/client");

function fallbackAnswer(question, evidence) {
  if (evidence.length === 0) {
    return {
      summary: "I do not have enough retrieved evidence to answer confidently.",
      sections: [],
      confidence: "low",
      followUpQuestions: ["Can you provide more context or enable additional sources?"],
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

async function reasonAnswer({ question, plan, evidence, compressedEvidence }) {
  if (!compressedEvidence && plan?.needs_llm) {
    try {
      const payload = await completeJson({
        model: config.llm.reasonerModel,
        system: `You are an expert assistant writing a concise AI overview.
Use current, accurate information. When uncertain, say so and lower confidence.
Return ONLY JSON:
{
  "summary": "2-4 sentence overview",
  "sections": [{ "title": "section", "body": "details", "citations": [] }],
  "confidence": "high|medium|low",
  "followUpQuestions": ["question"]
}`,
        user: `Question:\n${question}`,
        temperature: config.llm.temperature.reasoner,
        googleSearch: config.llm.googleSearchGrounding,
      });
      return normalizeAnswer(payload);
    } catch (error) {
      return { ...fallbackAnswer(question, evidence), reasonerError: error.message };
    }
  }

  if (!compressedEvidence) {
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
- Use ONLY the supplied evidence.
- Every section must cite one or more evidence IDs from: ${evidenceIds.join(", ") || "none"}
- Do not hallucinate sources or facts.
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
