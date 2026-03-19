# Java CI/CD Pipeline on AWS

A complete, production-ready CI/CD pipeline that automatically compiles Java code, builds Docker images, and deploys applications to AWS. This project demonstrates best practices in Infrastructure as Code, IAM security, and Docker optimization.

## 📋 Overview

This project implements a complete end-to-end CI/CD pipeline using AWS services that automatically:

1. **Detects** code changes in AWS CodeCommit
2. **Compiles** Java application and builds Docker image using CodeBuild
3. **Approves** manually before deployment
4. **Deploys** the application to production via CodeDeploy

### Pipeline Architecture

```
CodeCommit (Source)
    → Triggered on code push
    ↓
CodePipeline (Orchestrator)
    ├─ Source Stage: Read code from CodeCommit
    ├─ Build Stage: Compile + Build Docker image
    ├─ Approval Stage: Wait for manual approval
    └─ Deploy Stage: Deploy to servers via CodeDeploy
```

## 🚀 Quick Start

### Prerequisites
- AWS Account with CLI configured
- Git installed
- Docker installed
- Maven 3+
- Java 11 JDK

### Deploy Pipeline (5 minutes)

```bash
# 1. Create CodeCommit repository
aws codecommit create-repository --repository-name java-cicd-repo --region us-east-1

# 2. Push code to CodeCommit
cd java-cicd
git remote set-url origin https://git-codecommit.us-east-1.amazonaws.com/v1/repos/java-cicd-repo
git push -u origin main

# 3. Deploy infrastructure
cd ../cloudformation
aws cloudformation create-stack \
  --stack-name test-pipeline-stack \
  --template-body file://pipeline.yml \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# 4. Monitor deployment
aws cloudformation describe-stacks \
  --stack-name test-pipeline-stack \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'
```

## 📁 Project Structure

```
devops-shared-scripts/
├── cloudformation/
│   └── pipeline.yml              # CloudFormation template (all AWS resources)
├── java-cicd/
│   ├── src/main/java/com/demo/
│   │   └── App.java              # Java web application
│   ├── pom.xml                   # Maven build config
│   ├── Dockerfile                # Multi-stage Docker build
│   ├── buildspec.yml             # CodeBuild instructions
│   └── appspec.yml               # CodeDeploy instructions
├── run-pipeline.sh               # Automatic approval script
└── README.md
```

## 🎓 Key Learning Concepts

### 1. IAM Roles & Least Privilege (Critical)

Each AWS service gets its own role with ONLY the permissions it needs:

```yaml
CodeBuildServiceRole:
  ✅ CAN: Build code, push Docker images, write logs
  ❌ CANNOT: Deploy, delete databases, access other services

CodePipelineRole:
  ✅ CAN: Orchestrate stages, read code, trigger builds
  ❌ CANNOT: Build code, actually deploy

CodeDeployRole:
  ✅ CAN: Deploy to servers
  ❌ CANNOT: Build code, create repositories
```

**Why?** If one service is compromised, damage is limited to its permissions only.

### 2. Docker Registry Selection (Real-World Issue!)

**Docker Hub (AVOID)**
```
❌ Rate limited: 100 pulls per 6 hours (unauthenticated)
  Problem: After first build, subsequent builds fail with 429
  Changing image tags DOESN'T help (same registry = same limit)
```

**ECR Public (RECOMMENDED)**
```
✅ NO rate limiting
✅ Free, like Docker Hub
✅ Perfect for CI/CD pipelines
✅ Deploy unlimited times without hitting limits
```

**What we changed:**
```dockerfile
# Before (Rate Limited):
FROM maven:3-eclipse-temurin-11

# After (Unlimited):
FROM public.ecr.aws/docker/library/maven:3-eclipse-temurin-11
```

### 3. Multi-Stage Docker Builds

```dockerfile
# Stage 1: Build (includes Maven - 200MB)
FROM maven:3-eclipse-temurin-11 AS build
RUN mvn clean package -DskipTests
# Result: /app/target/cicd-demo.jar

# Stage 2: Runtime (only Java runtime - 50MB)
FROM eclipse-temurin:11-jre
COPY --from=build /app/target/cicd-demo.jar app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**Benefits:**
- Build stage: 400MB (includes Maven, development tools)
- Runtime stage: 70MB (only what's needed)
- Final image: **7x smaller!**
- Faster deployment and transfers

### 4. Infrastructure as Code (IaC)

**Complete CloudFormation template defines:**
- S3 bucket (artifacts)
- IAM roles (3 services)
- ECR repository
- CodeBuild project
- CodePipeline
- CodeDeploy application

**Result:** Reproducible, version-controlled infrastructure

## 🐛 Challenges Faced & Solutions

| # | Challenge | Problem | Solution | Lesson |
|---|-----------|---------|----------|--------|
| 1 | IAM Roles Not Defined | Template referenced non-existent roles | Added all roles to CloudFormation template | Make templates self-contained |
| 2 | Wrong Policy ARN | `AWSCodeDeployRoleForEC2` doesn't exist | Used `service-role/AWSCodeDeployRole` | Check AWS documentation |
| 3 | Missing Permission | `codecommit:GetUploadArchiveStatus` error | Added exact permission to CodePipelineRole | Check CloudWatch logs |
| 4 | Artifact Flow | Deploy stage used SourceArtifact | Changed to BuildArtifact | Different stages need different artifacts |
| 5 | Rate Limiting (CRITICAL) | `429 Too Many Requests` from Docker Hub | Switched to ECR Public | Never use Docker Hub for CI/CD |

## 📊 Real-World Learning

### The Docker Hub Rate Limiting Issue

**What Happened:**
```
Execution #1: ✅ Build succeeded (99 pulls left on limit)
Execution #2: ❌ Build failed (hit 100 pull limit)
Execution #3: ❌ Still limited after 12 hours

Why waiting didn't help?
- Rate limits are per REGISTRY, not per IP
- Same registry = same limit bucket
- All AWS CodeBuild in us-east-1 shares same limit

Why changing image tags didn't help?
- Tried: maven → openjdk → other images
- Still used docker.io (Docker Hub)
- Rate limit is per registry, not per image
```

**The Fix:**
```
Changed: docker.io/library/maven → public.ecr.aws/docker/library/maven
Result: Unlimited builds, completely solved
Cost: $0 (free, just like Docker Hub)
```

### My Learning Timeline

**Day 1:** Built infrastructure, hit 4 IAM-related issues
→ Learned: Proper role configuration and least-privilege security

**Day 2:** Build stage succeeded, but Docker Hub rate limiting blocked
→ Learned: Registry selection is critical for CI/CD reliability

## 🧹 Cleanup

Delete all resources to avoid AWS costs:

```bash
# 1. Empty S3 bucket
aws s3 rm s3://devops-shared-scripts-bucket --recursive --region us-east-1

# 2. Delete CloudFormation stack
aws cloudformation delete-stack --stack-name test-pipeline-stack --region us-east-1

# 3. Delete CodeCommit repository
aws codecommit delete-repository --repository-name java-cicd-repo --region us-east-1
```

## 💰 Cost Estimation

Most operations are covered by AWS free tier:
- CodeCommit: Free
- CodeBuild: 100 minutes/month free
- CodePipeline: 1 pipeline free
- S3: 5GB free
- ECR Public: Completely free
- CloudFormation: Free

**Typical Cost:** $0-5/month (development)

## 📚 References

- [AWS CloudFormation](https://docs.aws.amazon.com/cloudformation/)
- [AWS CodePipeline](https://docs.aws.amazon.com/codepipeline/)
- [Docker Multi-Stage Builds](https://docs.docker.com/build/building/multi-stage/)
- [ECR Public Gallery](https://gallery.ecr.aws/)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

## 🎯 Next Steps

1. Add integration tests (JUnit)
2. Add container image scanning
3. Deploy to multiple environments (dev/staging/prod)
4. Add CloudWatch monitoring and alerts
5. Implement automatic rollback on failures

## Tech Stack

- **Cloud:** AWS (CodeCommit, CodeBuild, CodePipeline, CodeDeploy, ECR, CloudFormation)
- **Languages:** Java 11, Bash
- **Build:** Maven
- **Containerization:** Docker (multi-stage builds)
- **Infrastructure:** CloudFormation (IaC)
- **Version Control:** Git / CodeCommit
