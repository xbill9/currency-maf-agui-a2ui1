# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Azure sibling of `~/currency-claude-agui-a2ui1` (ADK + Gemini) and `~/currency-strands-agui-a2ui1` (Strands + Amazon Nova on AWS). Here: Microsoft Agent Framework + Azure OpenAI `gpt-5.4-mini`, agent and Next.js UI as two Azure Container Apps, A2UI 1.0.

## Running

Use the active `python3` and install packages into it; never create a virtualenv. The agent authenticates to Azure OpenAI with Entra ID (`DefaultAzureCredential`): `az login` locally, a managed identity on Azure. There are no keys.

| What | Command |
|---|---|
| Agent + MCP (stdio child), :8095 `/invocations`, `/ping` | `cd app/agent && AZURE_OPENAI_ENDPOINT=https://<account>.cognitiveservices.azure.com/ PORT=8095 python3 main.py` |
| UI, :3002 | `cd frontend-react && PORT=3002 AGENT_URL=http://127.0.0.1:8095/invocations npx next dev --webpack -p 3002` |
| Offline tests | `python3 -m pytest tests` |
| Render suite (stack up) | `UI_URL=http://localhost:3002 python3 tools/render_suite.py 10 LABEL evidence/OUT.jsonl` |
| Deploy everything | `infra/deploy.sh` |
| Delete everything | `infra/teardown.sh` |

Ports 3000, 8008, 8080, 10000 (ADK sibling) and 3001, 8090 (Strands sibling) may be in use. Stop processes by port, never by name: `pkill -f main.py` matches all three stacks, and `pkill -f PORT=8095` matches the shell running it. `npm install` needs `--legacy-peer-deps`.

## Rules

- Keep `tools/render_suite.py` at 100% on the default model, locally and against the Azure URL.
- `EndTurnAfterUi` (function middleware) ends the run with `MiddlewareTermination` only after a successful UI send; an error goes back to the model. The tool result it sees is a `list[Content]`: read its text with `_result_text`, since `str()` of the list does not contain it.
- `A2uiRescueMiddleware` (chat middleware, `a2ui_rescue.py`) turns `<a2ui>` reply text into UI tool calls. Chat middleware runs inside the function-invocation loop, so the loop runs the rescued call. Keep it.
- `allow_multiple_tool_calls` stays `False`: two parallel UI sends create the same surface twice and the renderer rejects the second.
- Macro arguments are untrusted: validate and clamp in `macros.py`. The charts catalog id and props must match `custom_catalog.json` and `frontend-react/src/components/A2UICustomCatalog.tsx`.
- The agent app has internal ingress only; the UI reaches it at `http://currency-maf-agent/invocations`. The AG-UI endpoint runs with `single_user=True` for that reason.

## Git

Commit straight to `main` and push.
