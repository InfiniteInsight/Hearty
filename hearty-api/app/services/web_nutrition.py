"""Tier 3: Claude reads Brave web-search results and extracts nutrition. The
search executor and the LLM call are injected so the tool-use loop is testable
without network or model access."""

import json
import os

import httpx
import litellm

HTTP_TIMEOUT = float(os.environ.get("FOOD_HTTP_TIMEOUT", "10.0"))
WEB_MAX_TOOL_ROUNDS = int(os.environ.get("FOOD_WEB_MAX_TOOL_ROUNDS", "4"))
FOOD_LLM_MODEL = os.environ.get("FOOD_LLM_MODEL") or os.environ.get(
    "LLM_MODEL", "claude-sonnet-4-6")
BRAVE_URL = "https://api.search.brave.com/res/v1/web/search"

_WEB_PROMPT = (
    "Find nutrition facts for: {item}. Use the web_search tool to look it up, "
    "then reply with ONLY a JSON object: {{\"item_name\": str, \"calories\": "
    "int|null, \"total_fat_g\": num|null, \"total_carbs_g\": num|null, "
    "\"protein_g\": num|null, \"source_url\": str}}. If you cannot find reliable "
    "nutrition data, reply with exactly NO_DATA."
)

_TOOLS = [{"type": "function", "function": {
    "name": "web_search",
    "description": "Search the web and return result snippets.",
    "parameters": {"type": "object",
                   "properties": {"query": {"type": "string"}},
                   "required": ["query"]}}}]


def brave_search(query: str) -> list[dict]:
    key = os.environ.get("BRAVE_SEARCH_API_KEY")
    if not key:
        return []
    headers = {"X-Subscription-Token": key, "Accept": "application/json"}
    with httpx.Client(timeout=HTTP_TIMEOUT) as client:
        r = client.get(BRAVE_URL, headers=headers,
                       params={"q": query, "count": 5})
        r.raise_for_status()
        results = ((r.json() or {}).get("web") or {}).get("results") or []
    return [{"title": x.get("title"), "url": x.get("url"),
             "description": x.get("description")} for x in results]


def _strip_fence(t: str) -> str:
    t = t.strip()
    if t.startswith("```"):
        t = t.split("\n", 1)[1] if "\n" in t else t
        if t.endswith("```"):
            t = t.rsplit("```", 1)[0]
    return t.strip()


def web_nutrition_lookup(description: str, search=None, complete=None) -> dict | None:
    # Default search needs a Brave key; bail before calling the model if absent.
    if search is None:
        if not os.environ.get("BRAVE_SEARCH_API_KEY"):
            return None
        search = brave_search
    complete = complete or litellm.completion

    messages = [{"role": "user", "content": _WEB_PROMPT.format(item=description)}]
    for _ in range(WEB_MAX_TOOL_ROUNDS):
        resp = complete(model=FOOD_LLM_MODEL, messages=messages, tools=_TOOLS,
                        api_base=os.environ.get("LLM_BASE_URL") or None)
        msg = resp.choices[0].message
        tool_calls = getattr(msg, "tool_calls", None)
        if tool_calls:
            messages.append({"role": "assistant", "content": msg.content or "",
                             "tool_calls": [
                {"id": tc.id, "type": "function",
                 "function": {"name": tc.function.name,
                              "arguments": tc.function.arguments}}
                for tc in tool_calls]})
            for tc in tool_calls:
                try:
                    args = json.loads(tc.function.arguments)
                except (TypeError, ValueError):
                    args = {}
                results = search(args.get("query", description))
                messages.append({"role": "tool", "tool_call_id": tc.id,
                                 "content": json.dumps(results)})
            continue
        content = _strip_fence(msg.content or "")
        if not content or content.strip() == "NO_DATA":
            return None
        try:
            data = json.loads(content)
        except (TypeError, ValueError):
            return None
        return {"item_name": data.get("item_name") or description,
                "calories": data.get("calories"),
                "total_fat_g": data.get("total_fat_g"),
                "total_carbs_g": data.get("total_carbs_g"),
                "protein_g": data.get("protein_g"),
                "source": "web_search",
                "source_url": data.get("source_url") or "",
                "tier": 3}
    return None
