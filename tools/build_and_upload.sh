#!/bin/bash

# ─── CONFIG ───────────────────────────────────────────────────
REPO_URL="https://github.com/vineeta05/Devops-shared-script.git"
S3_BUCKET="devops-shared-scripts-bucket"
PIPELINE_NAME="test-pipeline"
# ──────────────────────────────────────────────────────────────

WORK_DIR="/tmp/devops-build"
REPO_DIR="$WORK_DIR/Devops-shared-script"

# Step 1: Create S3 bucket if it doesn't already exist
echo ">>> Checking S3 bucket..."
if aws s3 ls "s3://$S3_BUCKET" 2>&1 | grep -q 'NoSuchBucket'; then
  echo ">>> Bucket not found. Creating bucket..."
  aws s3api create-bucket --bucket "$S3_BUCKET" --region us-east-1
  echo ">>> Bucket created!"
else
  echo ">>> Bucket already exists. Skipping creation."
fi

# Step 2: Clean up and clone the repo
echo ">>> Cloning repository..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
git clone "$REPO_URL" "$REPO_DIR"

# Step 3: Loop through each environment and create a zip
for ENV in DEV INT QA; do

  echo ">>> Building zip for $ENV..."

  # Find the deploy script for this environment
  DEPLOY_SCRIPT=$(find "$REPO_DIR/scripts/deploy-scripts/$ENV" -name "*.sh")

  # Create a temporary staging folder
  STAGE_DIR="$WORK_DIR/stage_$ENV"
  mkdir -p "$STAGE_DIR/scripts"

  # Copy appspec.yml and the deploy script into staging folder
  cp "$REPO_DIR/appspec/appspec.yml" "$STAGE_DIR/appspec.yml"
  cp "$DEPLOY_SCRIPT" "$STAGE_DIR/scripts/"

  # Zip it up using Linux zip command
  cd "$STAGE_DIR"
  zip -r "$WORK_DIR/${ENV}.zip" .
  cd -

  echo ">>> Created ${ENV}.zip"

done

# Step 4: Upload each zip to S3
echo ">>> Uploading zips to S3..."
for ENV in DEV INT QA; do
  aws s3 cp "$WORK_DIR/${ENV}.zip" "s3://$S3_BUCKET/appspec/${ENV}.zip"
  echo ">>> Uploaded ${ENV}.zip"
done

# Step 5: Update pipeline source using jq (pure bash)
echo ">>> Updating pipeline source..."

# Install jq if not present
sudo apt-get install -y jq

# Get pipeline JSON
aws codepipeline get-pipeline --name "$PIPELINE_NAME" > /tmp/pipeline_raw.json

# Remove metadata and update bucket/key using jq
jq '.pipeline | 
    (.stages[] | 
    select(.name=="Source") | 
    .actions[].configuration) |= 
    . + {
        "S3Bucket": "devops-shared-scripts-bucket",
        "S3ObjectKey": "appspec/DEV.zip"
    }' /tmp/pipeline_raw.json > /tmp/pipeline.json

# Apply updated pipeline
aws codepipeline update-pipeline --cli-input-json file:///tmp/pipeline.json
echo ">>> Pipeline updated!"

echo ">>> All done!"
