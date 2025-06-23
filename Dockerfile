FROM openjdk:17-jdk-slim
COPY target/spring-petclinic.jar spring-petclinic.jar
ENTRYPOINT ["java","-jar","/spring-petclinic.jar"]
