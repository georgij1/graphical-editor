FROM eclipse-temurin:21-jdk AS build
WORKDIR /app

COPY gradlew gradlew.bat ./
COPY gradle/wrapper ./gradle/wrapper
COPY build.gradle settings.gradle ./
RUN chmod +x gradlew && ./gradlew --no-daemon --console=plain dependencies

COPY src ./src
RUN ./gradlew --no-daemon --console=plain bootJar -x test

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/build/libs/auth-service-*.jar /app/app.jar

ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
