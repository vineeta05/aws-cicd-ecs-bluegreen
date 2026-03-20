# Stage 1 — Build
FROM public.ecr.aws/docker/library/maven:3-eclipse-temurin-11 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests

# Stage 2 — Run
FROM public.ecr.aws/docker/library/eclipse-temurin:11-jre
WORKDIR /app

# Copy JAR from build stage
COPY --from=build /app/target/cicd-demo.jar app.jar

# App version passed from buildspec
ARG APP_VERSION=1.0.0
ENV APP_VERSION=${APP_VERSION}

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
