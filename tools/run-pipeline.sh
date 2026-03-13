#!/usr/bin/env bash
set -euo pipefail

PIPELINE="test-pipeline"
STAGE="Approval"
ACTION="manual-approval"

echo "Starting pipeline: $PIPELINE"
EXEC_ID=$(aws codepipeline start-pipeline-execution --name "$PIPELINE" --query 'pipelineExecutionId' --output text)
echo "Execution started: $EXEC_ID"

echo "Waiting for approval token..."
for i in {1..60}; do
TOKEN=$(aws codepipeline get-pipeline-state --name "$PIPELINE" | jq -r \
  --arg s "$STAGE" \
  --arg a "$ACTION" \
  --arg exec "$EXEC_ID" \
  '.stageStates[] | 
   select(.stageName==$s) | 
   .actionStates[] | 
   select(.actionName==$a) | 
   select(.latestExecution.pipelineExecutionId==$exec) |
   .latestExecution.token // empty')
  if [[ -n "$TOKEN" ]]; then
    echo "Token received."
    break
  fi
  sleep 10
done

if [[ -z "${TOKEN:-}" ]]; then
  echo "Timed out waiting for approval token." >&2
  exit 1
fi

aws codepipeline put-approval-result --pipeline-name "$PIPELINE" --stage-name "$STAGE" --action-name "$ACTION" --token "$TOKEN" --result "summary=Approved automatically by script,status=Approved"
echo "Approval submitted."

while true; do
  STATUS=$(aws codepipeline get-pipeline-execution --pipeline-name "$PIPELINE" --pipeline-execution-id "$EXEC_ID" --query 'pipelineExecution.status' --output text)
  echo "Status: $STATUS"
  [[ "$STATUS" == "Succeeded" || "$STATUS" == "Failed" || "$STATUS" == "Stopped" || "$STATUS" == "Superseded" ]] && break
  sleep 10
done

echo "Pipeline completed with: $STATUS"
