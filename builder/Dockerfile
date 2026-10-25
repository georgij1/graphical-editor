# JavaFX build service: compiles an exported project (zip) into a runnable JAR
# or a self-contained bundle. No Maven/Gradle resolution happens at request
# time, so builds are fast and work offline.
FROM eclipse-temurin:21-jdk

ARG JAVAFX_VERSION=21.0.2

# JavaFX SDK in the Gluon layout: the plain jars hold the API and the
# per-platform jars carry the natives, so a bundle built from this directory
# runs on Linux, Windows and macOS.
RUN set -eux; \
    mkdir -p /opt/javafx/lib; \
    base="https://repo1.maven.org/maven2/org/openjfx"; \
    for module in javafx-base javafx-graphics javafx-controls javafx-fxml; do \
      curl -fsSL -o "/opt/javafx/lib/${module}.jar" \
        "${base}/${module}/${JAVAFX_VERSION}/${module}-${JAVAFX_VERSION}.jar"; \
      for platform in linux win mac; do \
        curl -fsSL -o "/opt/javafx/lib/${module}-${platform}.jar" \
          "${base}/${module}/${JAVAFX_VERSION}/${module}-${JAVAFX_VERSION}-${platform}.jar"; \
      done; \
    done; \
    chmod -R a+rX /opt/javafx/lib

WORKDIR /app
COPY BuildServer.java /app/BuildServer.java
RUN javac -d /app/classes /app/BuildServer.java

ENV PORT=8081 \
    JAVAFX_LIB=/opt/javafx/lib \
    JAVA_MODULES=javafx.controls,javafx.fxml

EXPOSE 8081
ENTRYPOINT ["java", "-cp", "/app/classes", "BuildServer"]