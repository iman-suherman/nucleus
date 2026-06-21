const { config } = require("../config");

function withTimeout(promise, timeoutMs, label) {
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      setTimeout(() => reject(new Error(`${label} timed out after ${timeoutMs}ms`)), timeoutMs);
    }),
  ]);
}

async function chatCompletion({
  model,
  messages,
  temperature = 0.2,
  json = false,
  timeoutMs = config.llm.timeoutMs,
}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const headers = { "Content-Type": "application/json" };
    if (config.llm.apiKey) {
      headers.Authorization = `Bearer ${config.llm.apiKey}`;
    }

    const body = {
      model,
      messages,
      temperature,
      stream: false,
    };

    if (json) {
      body.format = "json";
      body.response_format = { type: "json_object" };
    }

    const response = await fetch(`${config.llm.baseUrl.replace(/\/$/, "")}/v1/chat/completions`, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    if (!response.ok) {
      const detail = await response.text().catch(() => "");
      throw new Error(`LLM request failed (${response.status}): ${detail.slice(0, 400)}`);
    }

    const payload = await response.json();
    const content = payload?.choices?.[0]?.message?.content;
    if (!content) {
      throw new Error("LLM response missing message content");
    }
    return content;
  } finally {
    clearTimeout(timer);
  }
}

async function generateContent({
  model,
  system,
  user,
  temperature = 0.2,
  json = false,
  timeoutMs = config.llm.timeoutMs,
}) {
  const messages = [];
  if (system) messages.push({ role: "system", content: system });
  messages.push({ role: "user", content: user });
  return withTimeout(
    chatCompletion({ model, messages, temperature, json, timeoutMs }),
    timeoutMs,
    `openai:${model}`,
  );
}

module.exports = {
  generateContent,
};
