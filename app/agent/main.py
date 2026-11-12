"""AG-UI endpoint for the Agent Framework currency agent.

POST /invocations takes an AG-UI ``RunAgentInput`` and streams AG-UI events;
GET /ping is the health check. The same app runs locally (``python3 main.py``)
and on Azure Container Apps.
"""

import logging
import os

import uvicorn
from agent_framework_ag_ui import add_agent_framework_fastapi_endpoint
from currency_agent.agent import build_agent, mcp_tool
from fastapi import FastAPI

logging.basicConfig(format="[%(levelname)s] %(name)s: %(message)s", level=logging.INFO)

agent = build_agent([mcp_tool()])

app = FastAPI(title="Agent Framework currency agent")
# The agent sits behind internal ingress and only the UI server calls it, so it
# serves one caller; thread snapshots are not scoped per end user.
add_agent_framework_fastapi_endpoint(
    app, agent, "/invocations", allow_origins=["*"], single_user=True
)


@app.get("/ping")
def ping() -> dict:
    return {"status": "healthy"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
