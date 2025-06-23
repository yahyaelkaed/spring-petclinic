FROM openjdk:17-jdk-slim
COPY target/spring-petclinic-3.5.0.jar app.jar
ENTRYPOINT ["java","-jar","/app.jar"]
