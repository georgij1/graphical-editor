FROM eclipse-temurin:21-jdk AS build
WORKDIR /app

# Copy Gradle wrapper (small, cached layer)
COPY gradlew gradlew.bat ./
COPY gradle/wrapper ./gradle/wrapper
COPY build.gradle settings.gradle ./
RUN chmod +x gradlew && ./gradlew --no-daemon --console=plain dependencies

# Copy sources and build
COPY src ./src
RUN ./gradlew --no-daemon --console=plain bootJar -x test

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

COPY --from=build /app/build/libs/fxml-editor-backend-*.jar /app/app.jar

ENV PORT=8080 \
    DATA_DIR=/data \
    DOWNLOADS_DIR=/downloads \
    JAVAFX_LIB=/opt/javafx/lib \
    JAVA_MODULES=javafx.controls,javafx.fxml
EXPOSE 8080
VOLUME /data
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
