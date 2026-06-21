const { config } = require("../config");
const { completeJson, completeText } = require("../llm/client");

const PLANNER_SYSTEM = `You are the intent planner for Nucleus AI Overview.
Given a user question and optional local-data hints, decide what information must be retrieved before answering.

Return ONLY valid JSON with this shape:
{
  "question": "restated question",
  "needs_search": boolean,
  "needs_news": boolean,
  "needs_llm": boolean,
  "needs_gmail": boolean,
  "needs_calendar": boolean,
  "needs_notes": boolean,
  "needs_clipboard": boolean,
  "needs_documents": boolean,
  "searches": ["query 1", "query 2"],
  "reasoning": "short explanation"
}

Rules:
- Use needs_search/needs_news for current events, stocks, outages, product news, or anything time-sensitive.
- Use needs_gmail/needs_calendar/needs_notes/needs_clipboard when the question references the user's inbox, schedule, notes, or copied items.
- Use needs_llm true for stable general knowledge that may not need retrieval.
- Provide 1-3 focused search queries when retrieval is needed.
- Prefer local sources when the question is personal ("my emails", "my meetings", "what should I focus on today").`;

function heuristicPlan(question, localData = {}) {
  const text = String(question || "").toLowerCase();
  const hasLocal = (key) => Array.isArray(localData?.[key]) && localData[key].length > 0;

  const needsGmail = /\b(email|emails|inbox|gmail|unread)\b/.test(text) || hasLocal("gmail");
  const needsCalendar =
    /\b(calendar|meeting|meetings|schedule|my day|what should i focus)\b/.test(text) || hasLocal("calendar");
  const needsNotes = /\b(note|notes|memo|journal)\b/.test(text) || hasLocal("notes");
  const needsClipboard = /\b(clipboard|copied|paste)\b/.test(text) || hasLocal("clipboard");
  const needsDocuments = /\b(document|documents|pdf|file|files|repo|project)\b/.test(text) || hasLocal("documents") || hasLocal("pdfs");
  const needsNews = /\b(today|latest|news|outage|stock|market|breaking)\b/.test(text);
  const needsSearch = needsNews || /\b(why|what happened|current|recent|explain)\b/.test(text);
  const needsLocal = needsGmail || needsCalendar || needsNotes || needsClipboard || needsDocuments;
  const needsLlm = !needsSearch && !needsLocal;

  const searches = [];
  if (needsSearch || needsNews) searches.push(String(question).trim());

  return {
    question: String(question || "").trim(),
    needs_search: needsSearch,
    needs_news: needsNews,
    needs_llm: needsLlm,
    needs_gmail: needsGmail,
    needs_calendar: needsCalendar,
    needs_notes: needsNotes,
    needs_clipboard: needsClipboard,
    needs_documents: needsDocuments,
    searches,
    reasoning: "Heuristic planner fallback",
  };
}

async function planQuestion({ question, localData, hints }) {
  const fallback = heuristicPlan(question, localData);
  const localSummary = summarizeLocalHints(localData);

  try {
    const plan = await completeJson({
      model: config.llm.plannerModel,
      system: PLANNER_SYSTEM,
      user: [
        `Question: ${question}`,
        hints ? `Hints: ${JSON.stringify(hints)}` : null,
        localSummary ? `Available local data:\n${localSummary}` : "Available local data: none",
      ]
        .filter(Boolean)
        .join("\n\n"),
      temperature: config.llm.temperature.planner,
    });

    return normalizePlan(plan, question, fallback);
  } catch (error) {
    return { ...fallback, plannerError: error.message };
  }
}

function summarizeLocalHints(localData = {}) {
  const parts = [];
  for (const [key, items] of Object.entries(localData)) {
    if (Array.isArray(items) && items.length > 0) {
      parts.push(`- ${key}: ${items.length} item(s)`);
    }
  }
  return parts.join("\n");
}

function normalizePlan(plan, question, fallback) {
  return {
    question: plan.question || question || fallback.question,
    needs_search: Boolean(plan.needs_search ?? fallback.needs_search),
    needs_news: Boolean(plan.needs_news ?? fallback.needs_news),
    needs_llm: Boolean(plan.needs_llm ?? fallback.needs_llm),
    needs_gmail: Boolean(plan.needs_gmail ?? fallback.needs_gmail),
    needs_calendar: Boolean(plan.needs_calendar ?? fallback.needs_calendar),
    needs_notes: Boolean(plan.needs_notes ?? fallback.needs_notes),
    needs_clipboard: Boolean(plan.needs_clipboard ?? fallback.needs_clipboard),
    needs_documents: Boolean(plan.needs_documents ?? fallback.needs_documents),
    searches: Array.isArray(plan.searches) && plan.searches.length > 0 ? plan.searches.slice(0, 3) : fallback.searches,
    reasoning: plan.reasoning || fallback.reasoning,
  };
}

module.exports = {
  planQuestion,
  heuristicPlan,
};
