# AWS CI/CD Pipeline for Java Applications

A working CI/CD pipeline built with AWS services. This repo contains everything needed to automatically build and deploy a Java application using CodeCommit, CodeBuild, and CodeDeploy.

## What's in here

The pipeline handles the full flow: code → compile → Docker image → deploy. Each component is defined in CloudFormation, so you can spin it up or tear it down with a few commands.

## Getting started

### What you need
- AWS account with CLI configured
- Git
- Docker
- Maven 3+
- Java 11

### Deploy it

```bash
# Create the CodeCommit repo
aws codecommit create-repository --repository-name java-cicd-repo --region us-east-1

# Push your code
cd java-cicd
git remote set-url origin https://git-codecommit.us-east-1.amazonaws.com/v1/repos/java-cicd-repo
git push -u origin main

# Deploy the pipeline
cd ../cloudformation
aws cloudformation create-stack \
  --stack-name test-pipeline-stack \
  --template-body file://pipeline.yml \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Check the status
aws cloudformation describe-stacks \
  --stack-name test-pipeline-stack \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'
```

## How it's organized

```
devops-shared-scripts/
├── cloudformation/
│   └── pipeline.yml              # All AWS resources defined here
├── java-cicd/
│   ├── src/main/java/com/demo/
│   │   └── App.java              # The Java app
│   ├── pom.xml                   # Maven config
│   ├── Dockerfile                # Multi-stage Docker build
│   ├── buildspec.yml             # What CodeBuild does
│   └── appspec.yml               # What CodeDeploy does
└── README.md
```

## The pipeline stages

1. **Source** - Watches CodeCommit for changes
2. **Build** - Compiles Java code and builds Docker image via CodeBuild
3. **Approval** - Manual gate before deploying
4. **Deploy** - Rolls out the new image via CodeDeploy

## How the IAM roles work

Each AWS service gets its own role with only what it needs:

- **CodeBuildServiceRole** - Can compile code and push to ECR
- **CodePipelineRole** - Can orchestrate the stages
- **CodeDeployRole** - Can deploy to target servers

This follows the principle of least privilege. If something gets compromised, the damage is limited to what that role can do.

## Why we use ECR Public for base images

Initially tried pulling Docker base images from Docker Hub, but ran into rate limiting on repeated builds. Switched to AWS ECR Public instead, which mirrors common images (maven, java, etc) and has no rate limits.

**Before:**
```dockerfile
FROM maven:3-eclipse-temurin-11
```

**After:**
```dockerfile
FROM public.ecr.aws/docker/library/maven:3-eclipse-temurin-11
```

Same image, but pulled from ECR Public. Builds are reliable now.

## Multi-stage Docker builds

The Dockerfile uses two stages:
- **Build stage** (400MB) - Has Maven and build tools, compiles the code
- **Runtime stage** (70MB) - Only has Java runtime, runs the compiled JAR

Final image is about 7x smaller than if we shipped everything. Faster deploys, less storage.

## Infrastructure as Code

The entire pipeline is defined in `pipeline.yml` using CloudFormation. No manual clicking around in the AWS console. You can version control it, review changes, and deploy consistently.

## Troubleshooting

### Stack creation fails with "role already exists"
Check CloudWatch logs for the exact error. Usually means a role from a previous deployment is interfering. Delete the old stack and manually remove conflicting IAM roles, then try again.

### Build fails with permission errors
Check the IAM role permissions in CloudFormation. The error message usually tells you which permission is missing. Add it to the policy and redeploy.

### Can't push to CodeCommit
Make sure you're using AWS credentials (not GitHub credentials). If you're using SSH, set up the SSH keys properly in your AWS account.

## Cleanup

If you're done and want to delete everything to save costs:

```bash
# Empty the S3 bucket first
aws s3 rm s3://devops-shared-scripts-bucket --recursive --region us-east-1

# Delete the stack
aws cloudformation delete-stack --stack-name test-pipeline-stack --region us-east-1

# Delete the CodeCommit repo
aws codecommit delete-repository --repository-name java-cicd-repo --region us-east-1
```

## Cost

Most of this fits in AWS free tier:
- CodeCommit, CodeBuild (100 min/month), CodePipeline, S3 (5GB), ECR Public - all free
- Actual monthly cost for development work: $0-5

## References

- [AWS CloudFormation docs](https://docs.aws.amazon.com/cloudformation/)
- [CodePipeline how-to](https://docs.aws.amazon.com/codepipeline/)
- [Docker multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
- [ECR Public Gallery](https://gallery.ecr.aws/)

## What's next

Could add:
- Unit test stage in the pipeline
- Container image security scanning
- Deploy to multiple environments (dev/staging/prod)
- CloudWatch dashboards and alerts
- Automatic rollback on failed deployments
