FROM openjdk:17-jdk-slim
ARG JAR_FILE=target/spring-petclinic-*.jar
COPY ${JAR_FILE} app.jar
ENTRYPOINT ["java","-jar","/app.jar"]

RUN curl -LO https://dl.k8s.io/release/v1.33.2/bin/linux/amd64/kubectl && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/kubectl
