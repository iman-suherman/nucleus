const { config } = require("../config");
const { completeJson, completeText } = require("../llm/client");

function flattenSearchResults(searchRuns) {
  const items = [];
  for (const run of searchRuns || []) {
    for (const result of run.results || []) {
      items.push(result);
    }
  }
  return items;
}

function formatRawEvidence(results) {
  return results
    .map((item, index) => {
      const lines = [
        `Result ${index + 1}:`,
        `Source: ${item.source}`,
        `Title: ${item.title}`,
        `Snippet: ${item.snippet}`,
      ];
      if (item.url) lines.push(`URL: ${item.url}`);
      return lines.join("\n");
    })
    .join("\n\n");
}

function heuristicEvidence(results) {
  return results.slice(0, config.pipeline.maxEvidenceItems).map((item) => ({
    claim: item.snippet || item.title,
    source: item.source,
    title: item.title,
    url: item.url,
    evidenceId: item.id,
  }));
}

async function buildContext({ question, plan, searchRuns }) {
  const rawResults = flattenSearchResults(searchRuns);
  if (rawResults.length === 0) {
    return {
      evidence: [],
      compressedEvidence: "",
      rawResultCount: 0,
    };
  }

  const rawBlock = formatRawEvidence(rawResults.slice(0, 20));

  try {
    const payload = await completeJson({
      model: config.llm.contextModel,
      system: `You compress retrieval results into concise evidence bullets for an AI overview.
Return ONLY JSON:
{
  "evidence": [
    { "claim": "fact", "source": "source name", "title": "article title", "url": "optional url", "evidenceId": "id from input" }
  ]
}
Rules:
- Keep 3-${config.pipeline.maxEvidenceItems} distinct, non-duplicative bullets.
- Every bullet must map to one retrieved result.
- Do not invent facts.`,
      user: `Question:\n${question}\n\nRetrieved results:\n${rawBlock}`,
      temperature: config.llm.temperature.context,
    });

    const evidence = Array.isArray(payload.evidence) ? payload.evidence.slice(0, config.pipeline.maxEvidenceItems) : [];
    return {
      evidence,
      compressedEvidence: evidence.map((item) => `• ${item.claim} (${item.source})`).join("\n"),
      rawResultCount: rawResults.length,
    };
  } catch (error) {
    const evidence = heuristicEvidence(rawResults);
    return {
      evidence,
      compressedEvidence: evidence.map((item) => `• ${item.claim} (${item.source})`).join("\n"),
      rawResultCount: rawResults.length,
      contextError: error.message,
    };
  }
}

module.exports = {
  buildContext,
  flattenSearchResults,
  formatRawEvidence,
};
