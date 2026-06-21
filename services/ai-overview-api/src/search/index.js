const { config } = require("../config");

function withTimeout(promise, timeoutMs, label) {
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      setTimeout(() => reject(new Error(`${label} timed out after ${timeoutMs}ms`)), timeoutMs);
    }),
  ]);
}

function normalizeSearchResult(source, item, index) {
  return {
    id: `${source}-${index + 1}`,
    source,
    title: item.title || "Untitled",
    snippet: item.snippet || item.summary || "",
    url: item.url || null,
    publishedAt: item.publishedAt || null,
    metadata: item.metadata || {},
  };
}

async function fetchJson(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      Accept: "application/json",
      ...(options.headers || {}),
    },
  });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} for ${url}`);
  }
  return response.json();
}

async function searchWeb(query, limit) {
  if (config.search.serperApiKey) {
    const response = await fetch("https://google.serper.dev/search", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-API-KEY": config.search.serperApiKey,
      },
      body: JSON.stringify({ q: query, num: limit }),
    });
    if (!response.ok) throw new Error(`Serper search failed (${response.status})`);
    const payload = await response.json();
    return (payload.organic || []).slice(0, limit).map((item, index) =>
      normalizeSearchResult("web", {
        title: item.title,
        snippet: item.snippet,
        url: item.link,
      }, index)
    );
  }

  if (config.search.braveApiKey) {
    const params = new URLSearchParams({ q: query, count: String(limit) });
    const response = await fetch(`https://api.search.brave.com/res/v1/web/search?${params}`, {
      headers: {
        Accept: "application/json",
        "X-Subscription-Token": config.search.braveApiKey,
      },
    });
    if (!response.ok) throw new Error(`Brave search failed (${response.status})`);
    const payload = await response.json();
    return (payload.web?.results || []).slice(0, limit).map((item, index) =>
      normalizeSearchResult("web", {
        title: item.title,
        snippet: item.description,
        url: item.url,
      }, index)
    );
  }

  const params = new URLSearchParams({ q: query, format: "json", no_html: "1", skip_disambig: "1" });
  const payload = await fetchJson(`https://api.duckduckgo.com/?${params}`);
  const related = (payload.RelatedTopics || [])
    .flatMap((topic) => (topic.Topics ? topic.Topics : [topic]))
    .filter((topic) => topic.Text)
    .slice(0, limit)
    .map((topic, index) =>
      normalizeSearchResult("web", {
        title: topic.Text.split(" - ")[0] || topic.Text,
        snippet: topic.Text,
        url: topic.FirstURL,
      }, index)
    );

  if (related.length > 0) return related;

  if (payload.AbstractText) {
    return [
      normalizeSearchResult("web", {
        title: payload.Heading || query,
        snippet: payload.AbstractText,
        url: payload.AbstractURL,
      }, 0),
    ];
  }

  return [];
}

async function searchNews(query, limit) {
  const encoded = encodeURIComponent(query);
  const feedUrl = `https://news.google.com/rss/search?q=${encoded}&hl=en-US&gl=US&ceid=US:en`;
  const response = await fetch(feedUrl, { headers: { Accept: "application/rss+xml, application/xml, text/xml" } });
  if (!response.ok) throw new Error(`News feed failed (${response.status})`);
  const xml = await response.text();

  const items = [];
  const itemRegex = /<item>([\s\S]*?)<\/item>/gi;
  let match;
  while ((match = itemRegex.exec(xml)) && items.length < limit) {
    const block = match[1];
    const title = block.match(/<title><!\[CDATA\[(.*?)\]\]><\/title>|<title>(.*?)<\/title>/i);
    const link = block.match(/<link>(.*?)<\/link>/i);
    const pubDate = block.match(/<pubDate>(.*?)<\/pubDate>/i);
    const source = block.match(/<source[^>]*>(.*?)<\/source>/i);
    items.push(
      normalizeSearchResult("news", {
        title: (title?.[1] || title?.[2] || "News item").replace(/ - .*$/, ""),
        snippet: source?.[1] ? `${source[1]} headline` : "Google News headline",
        url: link?.[1] || null,
        publishedAt: pubDate?.[1] || null,
        metadata: { outlet: source?.[1] || null },
      }, items.length)
    );
  }
  return items;
}

async function searchWikipedia(query, limit) {
  const params = new URLSearchParams({
    action: "query",
    list: "search",
    srsearch: query,
    format: "json",
    origin: "*",
    utf8: "1",
  });
  const payload = await fetchJson(`https://en.wikipedia.org/w/api.php?${params}`);
  return (payload.query?.search || []).slice(0, limit).map((item, index) =>
    normalizeSearchResult("wikipedia", {
      title: item.title,
      snippet: item.snippet?.replace(/<\/?[^>]+>/g, "") || "",
      url: `https://en.wikipedia.org/wiki/${encodeURIComponent(item.title.replace(/ /g, "_"))}`,
    }, index)
  );
}

async function searchReddit(query, limit) {
  const params = new URLSearchParams({ q: query, sort: "relevance", limit: String(limit), restrict_sr: "false" });
  const payload = await fetchJson(`https://www.reddit.com/search.json?${params}`, {
    headers: { "User-Agent": "nucleus-ai-overview/0.1" },
  });
  return (payload.data?.children || []).slice(0, limit).map(({ data }, index) =>
    normalizeSearchResult("reddit", {
      title: data.title,
      snippet: data.selftext?.slice(0, 280) || `Score ${data.score} in r/${data.subreddit}`,
      url: data.url?.startsWith("http") ? data.url : `https://reddit.com${data.permalink}`,
      metadata: { subreddit: data.subreddit, score: data.score },
    }, index)
  );
}

async function searchGitHub(query, limit) {
  const params = new URLSearchParams({ q: query, sort: "indexed", order: "desc", per_page: String(limit) });
  const headers = { "User-Agent": "nucleus-ai-overview/0.1", Accept: "application/vnd.github+json" };
  if (config.search.githubToken) headers.Authorization = `Bearer ${config.search.githubToken}`;
  const payload = await fetchJson(`https://api.github.com/search/repositories?${params}`, { headers });
  return (payload.items || []).slice(0, limit).map((item, index) =>
    normalizeSearchResult("github", {
      title: item.full_name,
      snippet: item.description || `Stars: ${item.stargazers_count}`,
      url: item.html_url,
      metadata: { stars: item.stargazers_count, language: item.language },
    }, index)
  );
}

function searchLocalData(source, items, limit) {
  return (items || []).slice(0, limit).map((item, index) =>
    normalizeSearchResult(source, {
      title: item.title || item.subject || item.name || `${source} item`,
      snippet: item.snippet || item.body || item.summary || item.content || "",
      url: item.url || null,
      publishedAt: item.date || item.timestamp || item.start || null,
      metadata: item.metadata || {},
    }, index)
  );
}

const SEARCH_HANDLERS = {
  web: (query, limit) => searchWeb(query, limit),
  news: (query, limit) => searchNews(query, limit),
  wikipedia: (query, limit) => searchWikipedia(query, limit),
  reddit: (query, limit) => searchReddit(query, limit),
  github: (query, limit) => searchGitHub(query, limit),
  gmail: (_query, limit, localData) => searchLocalData("gmail", localData?.gmail, limit),
  calendar: (_query, limit, localData) => searchLocalData("calendar", localData?.calendar, limit),
  notes: (_query, limit, localData) => searchLocalData("notes", localData?.notes, limit),
  clipboard: (_query, limit, localData) => searchLocalData("clipboard", localData?.clipboard, limit),
  documents: (_query, limit, localData) => searchLocalData("documents", localData?.documents, limit),
  pdfs: (_query, limit, localData) => searchLocalData("pdfs", localData?.pdfs, limit),
};

async function runSearch(source, query, localData) {
  const handler = SEARCH_HANDLERS[source];
  if (!handler) {
    return { source, results: [], error: `Unknown source: ${source}` };
  }

  try {
    const results = await withTimeout(
      handler(query, config.search.maxResultsPerSource, localData),
      config.search.timeoutMs,
      source
    );
    return { source, results };
  } catch (error) {
    return { source, results: [], error: error.message };
  }
}

async function runPlannedSearches(plan, localData, requestedSources) {
  const limit = config.search.maxResultsPerSource;
  const tasks = [];

  const localSources = ["gmail", "calendar", "notes", "clipboard", "documents", "pdfs"];
  for (const source of localSources) {
    const flag = `needs_${source}`;
    const enabled = plan?.[flag] || requestedSources?.includes(source);
    if (enabled) {
      tasks.push(runSearch(source, plan?.question || "", localData));
    }
  }

  if (plan?.needs_search || plan?.needs_news) {
    const queries = Array.isArray(plan.searches) && plan.searches.length > 0 ? plan.searches : [plan.question];
    const primaryQuery = queries[0];

    if (plan.needs_search !== false) {
      for (const source of ["web", "wikipedia", "reddit", "github"]) {
        if (config.search.enabledSources.includes(source) || requestedSources?.includes(source)) {
          tasks.push(runSearch(source, primaryQuery, localData));
        }
      }
    }

    if (plan.needs_news) {
      for (const query of queries.slice(0, 2)) {
        tasks.push(runSearch("news", query, localData));
      }
    } else if (requestedSources?.includes("news")) {
      tasks.push(runSearch("news", primaryQuery, localData));
    }
  }

  if (tasks.length === 0 && plan?.needs_llm !== false) {
    return [];
  }

  const settled = await Promise.all(tasks);
  return settled;
}

module.exports = {
  runPlannedSearches,
  runSearch,
  searchLocalData,
};
