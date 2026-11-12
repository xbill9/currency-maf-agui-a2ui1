import { Hono } from "hono";
import { handle } from "hono/vercel";
import {
  CopilotRuntime,
  createCopilotRuntimeHandler,
  InMemoryAgentRunner,
} from "@copilotkit/runtime/v2";
import { HttpAgent } from "@ag-ui/client";

// AGENT_URL points at the agent's AG-UI endpoint: the agent running locally
// (python3 app/agent/main.py, PORT=8095), or its internal address on Azure
// Container Apps.
const agentUrl = process.env.AGENT_URL || "http://127.0.0.1:8095/invocations";

const runtime = new CopilotRuntime({
  agents: {
    currency_agent: new HttpAgent({ url: agentUrl }),
  },
  runner: new InMemoryAgentRunner(),
  // A2UI 1.0 is rendered client-side by @a2ui/react (see A2uiMessages.tsx);
  // CopilotKit's built-in A2UI middleware speaks v0.9, so it is not enabled.
});

const multiRouteHandler = createCopilotRuntimeHandler({
  runtime,
  basePath: "/api/copilotkit",
  mode: "multi-route",
  cors: true,
});

const singleRouteHandler = createCopilotRuntimeHandler({
  runtime,
  basePath: "/api/copilotkit",
  mode: "single-route",
  cors: true,
});

const app = new Hono().basePath("/api/copilotkit");

// Root path handler - resolves single-route requests (like POST /api/copilotkit with {method: "info"})
app.all("/", async (c) => singleRouteHandler(c.req.raw));

// Subpath handler - resolves multi-route requests (like GET /info and POST /agent/:agentId/run)
app.all("*", async (c) => {
  const path = c.req.path;
  if (path === "/api/copilotkit" || path === "/api/copilotkit/") {
    return singleRouteHandler(c.req.raw);
  }
  return multiRouteHandler(c.req.raw);
});

export const GET = handle(app);
export const POST = handle(app);
