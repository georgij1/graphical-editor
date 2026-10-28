FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml ./
RUN mvn -q -o dependency:go-offline 2>/dev/null || mvn -q dependency:go-offline
COPY src ./src
RUN mvn -q -DskipTests package

FROM eclipse-temurin:21-jre AS runtime
WORKDIR /app
COPY --from=build /app/target/fxml-editor-backend-*.jar /app/app.jar
ENV PORT=8080
ENV DATA_DIR=/data
EXPOSE 8080
VOLUME /data
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
