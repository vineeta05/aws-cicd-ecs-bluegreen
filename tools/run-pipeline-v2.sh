#!/usr/bin/env bash
set -euo pipefail

PIPELINE="test-pipeline"
STAGE="Approval"
ACTION="manual-approval"
DEPLOY_STAGE="Deploy"
DEPLOY_ACTION="Deploy"

# ---------------------------------------------------------
# Step 0: Pre-check - Stop all old executions before start
# ---------------------------------------------------------
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

  echo ">>> Stage status: ${STAGE_STATUS:-none}"
  echo ">>> Deploy status: ${DEPLOY_ACTION_STATUS:-none}"

  # Case 1: Deploy is running - wait for it to complete
  if [[ "$DEPLOY_ACTION_STATUS" == "InProgress" ]]; then
    echo ">>> Deployment is running - waiting 10s..."
    sleep 10
    continue

  # Case 2: Stage is blocked but deploy is not running - kill all
  elif [[ "$STAGE_STATUS" == "InProgress" && \
          "$DEPLOY_ACTION_STATUS" != "InProgress" ]]; then

    echo ">>> Finding all pending executions..."
    ALL_EXEC_IDS=$(aws codepipeline list-pipeline-executions \
      --pipeline-name "$PIPELINE" \
      --query 'pipelineExecutionSummaries[?status==`InProgress`].pipelineExecutionId' \
      --output text)

    echo ">>> Executions to kill: $ALL_EXEC_IDS"

    for EXEC in $ALL_EXEC_IDS; do
      echo ">>> Stopping execution: $EXEC"
      aws codepipeline stop-pipeline-execution \
        --pipeline-name "$PIPELINE" \
        --pipeline-execution-id "$EXEC" \
        --abandon \
        --reason "Cleanup before fresh run"
    done

    echo ">>> All old executions stopped - rechecking..."
    sleep 5
    continue

  # Case 3: Stage is clear - start fresh
  else
    echo ">>> Stage is clear - starting fresh execution..."
    break
  fi
done

# ---------------------------------------------------------
# Step 1: Start new pipeline execution
# ---------------------------------------------------------
echo "Starting pipeline: $PIPELINE"
EXEC_ID=$(aws codepipeline start-pipeline-execution \
  --name "$PIPELINE" \
  --query 'pipelineExecutionId' \
  --output text)
echo "Execution started: $EXEC_ID"

# ---------------------------------------------------------
# Step 2: Wait for approval token for THIS execution only
# ---------------------------------------------------------
echo "Waiting for approval token for execution $EXEC_ID..."
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
      echo "Approval token received for execution $EXEC_ID"
      break
    fi
  else
    echo "Attempt $i: Approval stage owned by ${STAGE_EXEC_ID:-none}, waiting for $EXEC_ID..."
  fi
  sleep 10
done

if [[ -z "${TOKEN:-}" ]]; then
  echo "Timed out waiting for approval token." >&2
  exit 1
fi

# ---------------------------------------------------------
# Step 3: Approve the pipeline
# ---------------------------------------------------------
aws codepipeline put-approval-result \
  --pipeline-name "$PIPELINE" \
  --stage-name "$STAGE" \
  --action-name "$ACTION" \
  --token "$TOKEN" \
  --result "summary=Approved automatically by script,status=Approved"
echo "Approval submitted for execution $EXEC_ID."

# ---------------------------------------------------------
# Step 4: Monitor pipeline until terminal state
# ---------------------------------------------------------
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
