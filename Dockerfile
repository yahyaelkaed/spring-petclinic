FROM openjdk:17-jdk-slim

ARG JAR_FILE=target/spring-petclinic-*.jar
COPY ${JAR_FILE} app.jar

# Install curl, download kubectl, set permissions, move it to PATH
RUN apt-get update && apt-get install -y curl && \
    curl -LO https://dl.k8s.io/release/v1.33.2/bin/linux/amd64/kubectl && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/kubectl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["java", "-jar", "/app.jar"]
