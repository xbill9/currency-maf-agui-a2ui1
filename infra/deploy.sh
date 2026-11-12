#!/usr/bin/env bash
# Deploy the currency agent to Azure: an Azure OpenAI model deployment, the agent
# and the Next.js UI as two Azure Container Apps in one environment. Images are
# built in Azure Container Registry. Re-running updates everything in place.
#
# Identities: the agent app runs as a user-assigned managed identity holding only
# "Cognitive Services OpenAI User" on the AI account; both apps pull images with a
# second identity holding only AcrPull. No keys or connection strings anywhere.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RG="${RG:-currency-maf-rg}"
LOC="${LOC:-eastus2}"
SUFFIX="$(az account show --query id -o tsv | cut -c1-6)"
AI="${AI:-currency-maf-ai$SUFFIX}"
MODEL="${MODEL:-gpt-5.4-mini}"
MODEL_CAPACITY="${MODEL_CAPACITY:-200}"
ACR="${ACR:-currencymaf$SUFFIX}"
ENV_NAME="${ENV_NAME:-currency-maf-env}"
AGENT_APP="${AGENT_APP:-currency-maf-agent}"
UI_APP="${UI_APP:-currency-maf-ui}"
TAG="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || date +%s)"

echo "=== 1/6 resource group, AI account, model deployment ==="
az group create -n "$RG" -l "$LOC" -o none
az cognitiveservices account show -g "$RG" -n "$AI" -o none 2>/dev/null ||
  az cognitiveservices account create -g "$RG" -n "$AI" -l "$LOC" --kind AIServices \
    --sku S0 --custom-domain "$AI" --yes -o none
VERSION="$(az cognitiveservices model list -l "$LOC" \
  --query "[?model.name=='$MODEL'].model.version" -o tsv | sort -u | tail -1)"
az cognitiveservices account deployment show -g "$RG" -n "$AI" --deployment-name "$MODEL" -o none 2>/dev/null ||
  az cognitiveservices account deployment create -g "$RG" -n "$AI" --deployment-name "$MODEL" \
    --model-name "$MODEL" --model-version "$VERSION" --model-format OpenAI \
    --sku-name GlobalStandard --sku-capacity "$MODEL_CAPACITY" -o none
AI_ID="$(az cognitiveservices account show -g "$RG" -n "$AI" --query id -o tsv)"
AI_ENDPOINT="$(az cognitiveservices account show -g "$RG" -n "$AI" --query properties.endpoint -o tsv)"

echo "=== 2/6 container registry and images (built in ACR) ==="
az acr show -g "$RG" -n "$ACR" -o none 2>/dev/null ||
  az acr create -g "$RG" -n "$ACR" --sku Basic -o none
az acr build -r "$ACR" -t "currency-maf-agent:$TAG" "$REPO_ROOT/app/agent" -o none
az acr build -r "$ACR" -t "currency-maf-ui:$TAG" "$REPO_ROOT/frontend-react" -o none
ACR_ID="$(az acr show -g "$RG" -n "$ACR" --query id -o tsv)"
REGISTRY="$ACR.azurecr.io"

echo "=== 3/6 managed identities and roles ==="
identity() {
  az identity show -g "$RG" -n "$1" -o none 2>/dev/null || az identity create -g "$RG" -n "$1" -o none
  az identity show -g "$RG" -n "$1" --query "[id,principalId,clientId]" -o tsv
}
read -r PULL_ID PULL_PRINCIPAL _ <<<"$(identity currency-maf-pull | paste -sd' ')"
read -r AGENT_ID AGENT_PRINCIPAL AGENT_CLIENT <<<"$(identity currency-maf-agent | paste -sd' ')"
grant() {  # principal, role, scope
  az role assignment list --assignee "$1" --role "$2" --scope "$3" --query "[0].id" -o tsv | grep -q . ||
    az role assignment create --assignee-object-id "$1" --assignee-principal-type ServicePrincipal \
      --role "$2" --scope "$3" -o none
}
grant "$PULL_PRINCIPAL" AcrPull "$ACR_ID"
grant "$AGENT_PRINCIPAL" "Cognitive Services OpenAI User" "$AI_ID"

echo "=== 4/6 Container Apps environment ==="
az containerapp env show -g "$RG" -n "$ENV_NAME" -o none 2>/dev/null ||
  az containerapp env create -g "$RG" -n "$ENV_NAME" -l "$LOC" -o none

echo "=== 5/6 agent app (internal ingress) ==="
AGENT_ENV=(AZURE_OPENAI_ENDPOINT="$AI_ENDPOINT" AZURE_OPENAI_DEPLOYMENT="$MODEL" AZURE_CLIENT_ID="$AGENT_CLIENT")
if az containerapp show -g "$RG" -n "$AGENT_APP" -o none 2>/dev/null; then
  az containerapp update -g "$RG" -n "$AGENT_APP" --image "$REGISTRY/currency-maf-agent:$TAG" \
    --set-env-vars "${AGENT_ENV[@]}" -o none
else
  az containerapp create -g "$RG" -n "$AGENT_APP" --environment "$ENV_NAME" \
    --image "$REGISTRY/currency-maf-agent:$TAG" \
    --user-assigned "$PULL_ID" "$AGENT_ID" --registry-server "$REGISTRY" --registry-identity "$PULL_ID" \
    --ingress internal --target-port 8080 --transport http \
    --cpu 1 --memory 2Gi --min-replicas 1 --max-replicas 2 \
    --env-vars "${AGENT_ENV[@]}" -o none
fi

echo "=== 6/6 UI app (external ingress) ==="
UI_ENV=(AGENT_URL="http://$AGENT_APP/invocations")
if az containerapp show -g "$RG" -n "$UI_APP" -o none 2>/dev/null; then
  az containerapp update -g "$RG" -n "$UI_APP" --image "$REGISTRY/currency-maf-ui:$TAG" \
    --set-env-vars "${UI_ENV[@]}" -o none
else
  az containerapp create -g "$RG" -n "$UI_APP" --environment "$ENV_NAME" \
    --image "$REGISTRY/currency-maf-ui:$TAG" \
    --user-assigned "$PULL_ID" --registry-server "$REGISTRY" --registry-identity "$PULL_ID" \
    --ingress external --target-port 3000 --transport http \
    --cpu 1 --memory 2Gi --min-replicas 1 --max-replicas 2 \
    --env-vars "${UI_ENV[@]}" -o none
fi
echo "https://$(az containerapp show -g "$RG" -n "$UI_APP" --query properties.configuration.ingress.fqdn -o tsv)"
