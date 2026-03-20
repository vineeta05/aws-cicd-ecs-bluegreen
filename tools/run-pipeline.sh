#!/usr/bin/env bash
set -euo pipefail

PIPELINE="test-pipeline"
STAGE="Approval"
ACTION="manual-approval"
DEPLOY_STAGE="Deploy"
DEPLOY_ACTION="Deploy"

# ─────────────────────────────────────────
# Step 0: Cleanup — Kill old exections
# ─────────────────────────────────────────
echo ">>> Checking for old executions..."

while true; do
  PIPELINE_STATE=$(aws codepipeline get-pipeline-state --name "$PIPELINE")

  DEPLOY_ACTION_STATUS=$(echo "$PIPELINE_STATE" | jq -r \
    --arg s "$DEPLOY_STAGE" \
    --arg a "$DEPLOY_ACTION" \
    '.stageStates[] | select(.stageName==$s) |
     .actionStates[] | select(.actionName==$a) |
     .latestExecution.status // empty')

  STAGE_STATUS=$(echo "$PIPELINE_STATE" | jq -r \
    --arg s "$STAGE" \
    '.stageStates[] | select(.stageName==$s) |
     .latestExecution.status // empty')

  PREV_EXEC_ID=$(echo "$PIPELINE_STATE" | jq -r \
    --arg s "$STAGE" \
    '.stageStates[] | select(.stageName==$s) |
     .latestExecution.pipelineExecutionId // empty')

  echo ">>> Stage status: ${STAGE_STATUS:-none}"
  echo ">>> Deploy status: ${DEPLOY_ACTION_STATUS:-none}"

  if [[ "$DEPLOY_ACTION_STATUS" == "InProgress" ]]; then
    echo ">>> Deploy running — waiting 10s..."
    sleep 10
    continue

  elif [[ "$STAGE_STATUS" == "InProgress" && "$DEPLOY_ACTION_STATUS" != "InProgress" ]]; then
    echo ">>> Stopping old execution: $PREV_EXEC_ID"
    aws codepipeline stop-pipeline-execution \
      --pipeline-name "$PIPELINE" \
      --pipeline-execution-id "$PREV_EXEC_ID" \
      --abandon \
      --reason "Cleanup before fresh run"
    sleep 5
    continue

  else
    echo ">>> Stage is clear! Starting fresh..."
    break
  fi
done

# ─────────────────────────────────────────
# Step 1: Start new execution
# ─────────────────────────────────────────
echo "Starting pipeline: $PIPELINE"
EXEC_ID=$(aws codepipeline start-pipeline-execution \
  --name "$PIPELINE" \
  --query 'pipelineExecutionId' \
  --output text)
echo "Execution started: $EXEC_ID"

# ─────────────────────────────────────────
# Step 2: Wait for Approval token
# ─────────────────────────────────────────
echo "Waiting for approval token..."
TOKEN=""
for i in {1..60}; do
  STAGE_STATE=$(aws codepipeline get-pipeline-state --name "$PIPELINE")

  STAGE_EXEC_ID=$(echo "$STAGE_STATE" | jq -r \
    --arg s "$STAGE" \
    '.stageStates[] | select(.stageName==$s) |
     .latestExecution.pipelineExecutionId // empty')

  if [[ "$STAGE_EXEC_ID" == "$EXEC_ID" ]]; then
    TOKEN=$(echo "$STAGE_STATE" | jq -r \
      --arg s "$STAGE" --arg a "$ACTION" \
      '.stageStates[] | select(.stageName==$s) |
       .actionStates[] | select(.actionName==$a) |
       .latestExecution.token // empty')

    if [[ -n "$TOKEN" ]]; then
      echo "Token received for execution $EXEC_ID"
      break
    fi
  else
    echo "Attempt $i: Waiting for $EXEC_ID to reach Approval..."
  fi
  sleep 10
done

if [[ -z "${TOKEN:-}" ]]; then
  echo "Timed out waiting for approval token." >&2
  exit 1
fi

# ─────────────────────────────────────────
# Step 3: Approve Token
# ─────────────────────────────────────────
aws codepipeline put-approval-result \
  --pipeline-name "$PIPELINE" \
  --stage-name "$STAGE" \
  --action-name "$ACTION" \
  --token "$TOKEN" \
  --result "summary=Approved automatically by script,status=Approved"
echo "Approval submitted."

# ─────────────────────────────────────────
# Step 4: Monitor Pipeline status 
# ─────────────────────────────────────────
echo "Monitoring pipeline execution $EXEC_ID..."
while true; do
  STATUS=$(aws codepipeline get-pipeline-execution \
    --pipeline-name "$PIPELINE" \
    --pipeline-execution-id "$EXEC_ID" \
    --query 'pipelineExecution.status' \
    --output text)
  echo "Status: $STATUS"

  case "$STATUS" in
    Succeeded)
      echo "Pipeline completed successfully!"
      break
      ;;
    Failed|Stopped|Superseded|Cancelled)
      echo "Pipeline ended with: $STATUS"
      break
      ;;
  esac
  sleep 10
done

echo "Pipeline completed with: $STATUS"
