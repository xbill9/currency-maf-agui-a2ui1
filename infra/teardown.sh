#!/usr/bin/env bash
# Delete everything deploy.sh created: it all lives in one resource group.
# The AI account is soft-deleted by Azure; purge it so the name can be reused.
set -euo pipefail
RG="${RG:-currency-maf-rg}"
LOC="${LOC:-eastus2}"
SUFFIX="$(az account show --query id -o tsv | cut -c1-6)"
AI="${AI:-currency-maf-ai$SUFFIX}"
az group delete -n "$RG" --yes
az cognitiveservices account purge -g "$RG" -n "$AI" -l "$LOC" 2>/dev/null || true
