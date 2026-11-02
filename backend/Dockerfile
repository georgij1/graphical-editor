FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml ./
RUN mvn -q -o dependency:go-offline 2>/dev/null || mvn -q dependency:go-offline
COPY src ./src
RUN mvn -q -DskipTests package

FROM eclipse-temurin:21-jdk AS runtime
WORKDIR /app

# JavaFX SDK (Gluon layout): plain jars hold the API, per-platform jars carry
# the natives. A bundle built from this directory runs on Linux/Windows/macOS.
RUN set -eux; \
    mkdir -p /opt/javafx/lib; \
    base="https://repo1.maven.org/maven2/org/openjfx"; \
    for module in javafx-base javafx-graphics javafx-controls javafx-fxml; do \
      curl -fsSL -o "/opt/javafx/lib/${module}.jar" \
        "${base}/${module}/21.0.2/${module}-21.0.2.jar"; \
      for platform in linux win mac; do \
        curl -fsSL -o "/opt/javafx/lib/${module}-${platform}.jar" \
          "${base}/${module}/21.0.2/${module}-21.0.2-${platform}.jar"; \
      done; \
    done; \
    chmod -R a+rX /opt/javafx/lib

COPY --from=build /app/target/fxml-editor-backend-*.jar /app/app.jar

ENV PORT=8080 \
    DATA_DIR=/data \
    DOWNLOADS_DIR=/downloads \
    JAVAFX_LIB=/opt/javafx/lib \
    JAVA_MODULES=javafx.controls,javafx.fxml
EXPOSE 8080
VOLUME /data
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
