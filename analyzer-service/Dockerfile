FROM eclipse-temurin:21-jdk AS build
WORKDIR /app

COPY gradlew gradlew.bat ./
COPY gradle/wrapper ./gradle/wrapper
COPY build.gradle settings.gradle ./
RUN chmod +x gradlew && ./gradlew --no-daemon --console=plain dependencies

COPY src ./src
RUN ./gradlew --no-daemon --console=plain bootJar -x test

FROM eclipse-temurin:21-jdk AS runtime
WORKDIR /app

# JavaFX SDK for compilation and bundled runtime.
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
    chmod -R a+rX /opt/javafx/lib; \
    if command -v apt-get >/dev/null 2>&1; then \
      apt-get update && apt-get install -y --no-install-recommends bash maven && rm -rf /var/lib/apt/lists/*; \
    fi

COPY --from=build /app/build/libs/analyzer-service-*.jar /app/app.jar

ENV PORT=8080 \
    JAVAFX_LIB=/opt/javafx/lib \
    JAVA_MODULES=javafx.controls,javafx.fxml
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
