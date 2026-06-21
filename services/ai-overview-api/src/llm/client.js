const { config } = require("../config");
const vertex = require("./vertex");
const openaiCompatible = require("./openai-compatible");

function stripJsonFence(text) {
  const trimmed = String(text || "").trim();
  const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)```$/i);
  return fenced ? fenced[1].trim() : trimmed;
}

function extractJsonObject(text) {
  const cleaned = stripJsonFence(text);
  try {
    return JSON.parse(cleaned);
  } catch {
    const start = cleaned.indexOf("{");
    const end = cleaned.lastIndexOf("}");
    if (start >= 0 && end > start) {
      return JSON.parse(cleaned.slice(start, end + 1));
    }
    throw new Error("Model response did not contain valid JSON");
  }
}

function getProvider() {
  return config.llm.provider;
}

function assertEnabled() {
  if (!config.llm.enabled) {
    throw new Error("LLM not configured");
  }
}

async function generateContent(options) {
  assertEnabled();
  if (getProvider() === "vertex") {
    return vertex.generateContent(options);
  }
  return openaiCompatible.generateContent(options);
}

async function completeText({ model, system, user, temperature, json = false, googleSearch = false }) {
  return generateContent({ model, system, user, temperature, json, googleSearch });
}

async function completeJson({ model, system, user, temperature, googleSearch = false }) {
  const content = await completeText({ model, system, user, temperature, json: true, googleSearch });
  return extractJsonObject(content);
}

module.exports = {
  completeText,
  completeJson,
  extractJsonObject,
  stripJsonFence,
  getProvider,
};
