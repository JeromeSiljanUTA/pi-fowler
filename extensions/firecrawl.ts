/**
 * Firecrawl Extension for pi
 *
 * Registers firecrawl_scrape and firecrawl_search tools that talk to a
 * self-hosted Firecrawl instance — no Firecrawl API key required.
 *
 * Vendored from shockwaves-lab/searxng-firecrawl/firecrawl.pi-extension.ts.
 * The pi-fowler flake installs this file and injects it with `--extension`,
 * so it does not need to live in the agent directory or node_modules.
 *
 * Configuration:
 *   FIRECRAWL_API_URL  Base URL of the Firecrawl API.
 *                      Defaults to http://firecrawl.nemesis.home.arpa.
 */

import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "@earendil-works/pi-ai";

const BASE_URL = (process.env.FIRECRAWL_API_URL ?? "http://firecrawl.nemesis.home.arpa").replace(/\/+$/, "");

async function firecrawl(path: string, body: unknown, signal?: AbortSignal) {
	const res = await fetch(`${BASE_URL}/v1/${path}`, {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify(body),
		signal,
	});
	const text = await res.text();
	if (!res.ok) {
		throw new Error(`Firecrawl ${path} failed (${res.status}): ${text.slice(0, 500)}`);
	}
	try {
		return JSON.parse(text);
	} catch {
		throw new Error(`Firecrawl ${path} returned non-JSON: ${text.slice(0, 500)}`);
	}
}

const SCRAPE_PARAMS = Type.Object({
	url: Type.String({ description: "URL to scrape" }),
	formats: Type.Optional(
		Type.Array(Type.String(), {
			description: 'Output formats, e.g. ["markdown","html","links"]. Defaults to ["markdown"].',
		}),
	),
	onlyMainContent: Type.Optional(Type.Boolean({ description: "Strip nav/boilerplate (default true)" })),
});

const SEARCH_PARAMS = Type.Object({
	query: Type.String({ description: "Search query" }),
	limit: Type.Optional(Type.Number({ description: "Max results (default 5)" })),
});

export default function firecrawlExtension(pi: ExtensionAPI) {
	pi.registerTool({
		name: "firecrawl_scrape",
		label: "Firecrawl Scrape",
		description: "Scrape a single URL and return its content as markdown/text via the self-hosted Firecrawl API.",
		promptSnippet: "Scrape a web page to clean markdown",
		promptGuidelines: [
			"Use firecrawl_scrape when you need the readable content of a specific URL.",
			"Prefer firecrawl_search to discover URLs first, then firecrawl_scrape the best ones.",
		],
		parameters: SCRAPE_PARAMS,
		async execute(_id, params, signal, _onUpdate, _ctx) {
			const data = await firecrawl(
				"scrape",
				{
					url: params.url,
					formats: params.formats ?? ["markdown"],
					onlyMainContent: params.onlyMainContent ?? true,
				},
				signal,
			);
			const md = data?.data?.markdown ?? data?.data?.content ?? JSON.stringify(data);
			return {
				content: [{ type: "text", text: typeof md === "string" ? md : JSON.stringify(md) }],
				details: { url: params.url, status: data?.data?.metadata?.statusCode },
			};
		},
	});

	pi.registerTool({
		name: "firecrawl_search",
		label: "Firecrawl Search",
		description: "Search the web via the self-hosted Firecrawl API and return result titles/URLs/snippets.",
		promptSnippet: "Web search through Firecrawl",
		promptGuidelines: ["Use firecrawl_search to find current information or URLs on a topic."],
		parameters: SEARCH_PARAMS,
		async execute(_id, params, signal, _onUpdate, _ctx) {
			const data = await firecrawl(
				"search",
				{ query: params.query, limit: params.limit ?? 5 },
				signal,
			);
			const results: Array<{ title?: string; url?: string; description?: string }> =
				data?.data?.web ?? data?.data ?? [];
			const text = results
				.map((r, i) => `${i + 1}. ${r.title ?? ""}\n   ${r.url ?? ""}\n   ${r.description ?? ""}`)
				.join("\n\n");
			return {
				content: [{ type: "text", text: text || JSON.stringify(data) }],
				details: { query: params.query, count: results.length },
			};
		},
	});
}
