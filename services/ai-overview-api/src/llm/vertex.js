const { VertexAI } = require("@google-cloud/vertexai");
const { config } = require("../config");

let vertexClient;

function clearLocalCredentialsInCloudRun() {
  if (!process.env.K_SERVICE) return;
  delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
}

function getVertexClient() {
  if (!vertexClient) {
    clearLocalCredentialsInCloudRun();
    vertexClient = new VertexAI({
      project: config.llm.vertex.projectId,
      location: config.llm.vertex.location,
    });
  }
  return vertexClient;
}

function withTimeout(promise, timeoutMs, label) {
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      setTimeout(() => reject(new Error(`${label} timed out after ${timeoutMs}ms`)), timeoutMs);
    }),
  ]);
}

function extractText(response) {
  const parts = response?.candidates?.[0]?.content?.parts || [];
  return parts
    .map((part) => part.text || "")
    .join("")
    .trim();
}

async function generateContent({
  model,
  system,
  user,
  temperature = 0.2,
  json = false,
  googleSearch = false,
  timeoutMs = config.llm.timeoutMs,
}) {
  const generationConfig = {
    temperature,
    maxOutputTokens: 8192,
  };

  if (json) {
    generationConfig.responseMimeType = "application/json";
  }

  const modelOptions = {
    model,
    generationConfig,
  };

  if (googleSearch) {
    modelOptions.tools = [{ googleSearch: {} }];
  }

  const generativeModel = getVertexClient().getGenerativeModel(modelOptions);
  const request = {
    contents: [{ role: "user", parts: [{ text: user }] }],
  };

  if (system) {
    request.systemInstruction = { parts: [{ text: system }] };
  }

  const result = await withTimeout(
    generativeModel.generateContent(request),
    timeoutMs,
    `vertex:${model}`,
  );

  const text = extractText(result.response);
  if (!text) {
    throw new Error("Vertex AI response missing text content");
  }
  return text;
}

module.exports = {
  generateContent,
};
