import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

/**
 * Tiny JavaFX build service.
 *
 * Accepts a project archive (the very zip the editor exports), compiles the
 * Java sources against a pre-downloaded JavaFX SDK and returns a runnable
 * artifact:
 *
 * <pre>
 *   POST /build         -> application/java-archive (app.jar)
 *   POST /build/bundle  -> application/zip (app.jar + JavaFX SDK + run scripts)
 *   GET  /health        -> {"status":"ok"}
 * </pre>
 *
 * Nothing is resolved from the network at request time, so builds are fast and
 * work offline.
 */
public class BuildServer {

    private static final int MAX_BODY = 64 * 1024 * 1024;
    private static final Path JAVAFX_LIB = Paths.get(env("JAVAFX_LIB", "/opt/javafx/lib"));
    private static final String JAVA_MODULES = env("JAVA_MODULES", "javafx.controls,javafx.fxml");

    private static final Pattern PACKAGE = Pattern.compile("(?m)^\\s*package\\s+([\\w.]+)\\s*;");
    private static final Pattern APPLICATION_CLASS =
            Pattern.compile("public\\s+class\\s+(\\w+)\\s+extends\\s+Application");

    public static void main(String[] args) throws IOException {
        int port = Integer.parseInt(env("PORT", "8081"));
        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);
        server.setExecutor(Executors.newFixedThreadPool(2));
        // Longest prefix wins, so /build/bundle is matched before /build.
        server.createContext("/build/bundle", exchange -> handle(exchange, true));
        server.createContext("/build", exchange -> handle(exchange, false));
        server.createContext("/build/health", exchange -> {
            cors(exchange);
            respond(exchange, 200, "application/json",
                    "{\"status\":\"ok\"}".getBytes(StandardCharsets.UTF_8));
        });
        server.createContext("/health", exchange -> {
            cors(exchange);
            respond(exchange, 200, "application/json",
                    "{\"status\":\"ok\"}".getBytes(StandardCharsets.UTF_8));
        });
        server.start();
        System.out.println("builder listening on port " + port);
    }

    private static void handle(HttpExchange exchange, boolean bundle) throws IOException {
        try {
            cors(exchange);
            if (!"POST".equalsIgnoreCase(exchange.getRequestMethod())) {
                respond(exchange, 405, "text/plain", "Use POST".getBytes(StandardCharsets.UTF_8));
                return;
            }
            byte[] body = exchange.getRequestBody().readNBytes(MAX_BODY + 1);
            if (body.length > MAX_BODY) {
                respond(exchange, 413, "text/plain",
                        "Project is too large".getBytes(StandardCharsets.UTF_8));
                return;
            }
            byte[] artifact;
            try {
                artifact = build(body, bundle);
            } catch (BuildException error) {
                // The reason of the failure is written to the log as well, so
                // it can be read without opening the window of the editor.
                System.err.println("build failed: " + error.getMessage());
                respond(exchange, 400, "text/plain",
                        error.getMessage().getBytes(StandardCharsets.UTF_8));
                return;
            }
            String type = bundle ? "application/zip" : "application/java-archive";
            String name = bundle ? "bundle.zip" : "app.jar";
            exchange.getResponseHeaders().add("Content-Disposition",
                    "attachment; filename=\"" + name + "\"");
            exchange.getResponseHeaders().add("X-Artifact", name);
            respond(exchange, 200, type, artifact);
        } catch (Exception error) {
            error.printStackTrace();
            respond(exchange, 500, "text/plain",
                    ("Build failed: " + error).getBytes(StandardCharsets.UTF_8));
        } finally {
            exchange.close();
        }
    }

    /** Extracts, compiles and packages the project; returns the artifact bytes. */
    private static byte[] build(byte[] archive, boolean bundle) throws IOException, BuildException {
        Path work = Files.createTempDirectory("javafx-build-");
        try {
            Path extracted = unzip(archive, work);
            Path root = singleRoot(extracted);

            Path javaDir = root.resolve("src/main/java");
            if (!Files.isDirectory(javaDir)) {
                throw new BuildException("No src/main/java directory in the archive");
            }
            List<Path> sources = new ArrayList<>();
            try (var stream = Files.walk(javaDir)) {
                stream.filter(Files::isRegularFile)
                        .filter(p -> p.toString().endsWith(".java"))
                        .forEach(sources::add);
            }
            if (sources.isEmpty()) {
                throw new BuildException("The archive contains no Java sources");
            }

            String mainClass = detectMainClass(sources);

            Path out = work.resolve("out");
            Files.createDirectories(out);
            // The JavaFX SDK puts module-info into the per-platform jars, so the
            // full SDK directory cannot be used as a module path (duplicate
            // modules). Compiling against the classpath avoids that entirely.
            List<String> javac = new ArrayList<>(List.of(
                    "javac", "-nowarn", "-encoding", "UTF-8", "--release", "21",
                    "-cp", JAVAFX_LIB + "/*",
                    "-d", out.toString()));
            for (Path source : sources) {
                javac.add(source.toString());
            }
            run(javac, work, "Compilation failed");

            Path resources = root.resolve("src/main/resources");
            Path jar = work.resolve("app.jar");
            List<String> jarCommand = new ArrayList<>(List.of(
                    "jar", "--create", "--file", jar.toString(),
                    "--main-class", mainClass,
                    "-C", out.toString(), "."));
            if (Files.isDirectory(resources)) {
                jarCommand.add("-C");
                jarCommand.add(resources.toString());
                jarCommand.add(".");
            }
            run(jarCommand, work, "Packaging failed");

            if (!bundle) {
                return Files.readAllBytes(jar);
            }
            return bundle(work, jar, mainClass);
        } finally {
            deleteRecursively(work);
        }
    }

    /** app.jar + the JavaFX SDK + launch scripts, ready for the user's machine. */
    private static byte[] bundle(Path work, Path jar, String mainClass) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(buffer)) {
            zip.putNextEntry(new ZipEntry("app.jar"));
            Files.copy(jar, zip);
            zip.closeEntry();

            try (var jars = Files.list(JAVAFX_LIB)) {
                for (Path sdk : jars.filter(p -> p.toString().endsWith(".jar")).toList()) {
                    zip.putNextEntry(new ZipEntry("lib/" + sdk.getFileName()));
                    Files.copy(sdk, zip);
                    zip.closeEntry();
                }
            }

            zip.putNextEntry(new ZipEntry("run.sh"));
            zip.write(("#!/bin/sh\n"
                    + "# Runs the packaged application. Requires a JDK 21+ on PATH.\n"
                    + "DIR=$(cd \"$(dirname \"$0\")\" && pwd)\n"
                    + "exec java -cp \"$DIR/app.jar:$DIR/lib/*\" " + mainClass + " \"$@\"\n")
                    .getBytes(StandardCharsets.UTF_8));
            zip.closeEntry();

            zip.putNextEntry(new ZipEntry("run.bat"));
            zip.write(("@echo off\r\n"
                    + "rem Runs the packaged application. Requires a JDK 21+ on PATH.\r\n"
                    + "java -cp \"%~dp0app.jar;%~dp0lib\\*\" " + mainClass + " %*\r\n")
                    .getBytes(StandardCharsets.UTF_8));
            zip.closeEntry();

            zip.putNextEntry(new ZipEntry("README.txt"));
            zip.write((mainClass + "\n\n"
                    + "This archive was produced by the FXML Editor build service.\n\n"
                    + "  Linux / macOS :  sh run.sh\n"
                    + "  Windows       :  run.bat\n\n"
                    + "Requirements: a JDK 21 or newer available on PATH.\n"
                    + "The lib/ folder holds the JavaFX runtime for all platforms.\n")
                    .getBytes(StandardCharsets.UTF_8));
            zip.closeEntry();
        }
        return buffer.toByteArray();
    }

    /** Finds the `public class X extends Application` entry point. */
    private static String detectMainClass(List<Path> sources) throws IOException, BuildException {
        for (Path source : sources) {
            String code = Files.readString(source);
            Matcher classMatcher = APPLICATION_CLASS.matcher(code);
            if (!classMatcher.find()) {
                continue;
            }
            Matcher packageMatcher = PACKAGE.matcher(code);
            String prefix = packageMatcher.find() ? packageMatcher.group(1) + "." : "";
            return prefix + classMatcher.group(1);
        }
        throw new BuildException("No class extending javafx.application.Application was found");
    }

    private static Path unzip(byte[] archive, Path target) throws IOException, BuildException {
        Path nested = target.resolve("project");
        Files.createDirectories(nested);
        try (ZipInputStream zip = new ZipInputStream(new java.io.ByteArrayInputStream(archive))) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                // Some zip tools write Windows separators; normalise them.
                String name = entry.getName().replace('\\', '/');
                Path destination = nested.resolve(name).normalize();
                // Reject path traversal ("../") from untrusted archives.
                if (!destination.startsWith(nested)) {
                    throw new BuildException("Archive contains an unsafe path: " + name);
                }
                if (name.endsWith("/")) {
                    Files.createDirectories(destination);
                    continue;
                }
                Files.createDirectories(destination.getParent());
                Files.copy(zip, destination, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            }
        }
        stripByteOrderMarks(nested);
        return nested;
    }

    /**
     * javac rejects a UTF-8 byte order mark, and editors on Windows happily add
     * one, so it is removed from every text file we unpacked.
     */
    private static void stripByteOrderMarks(Path root) throws IOException {
        try (var walk = Files.walk(root)) {
            for (Path file : walk.filter(Files::isRegularFile).toList()) {
                byte[] content = Files.readAllBytes(file);
                if (content.length < 3 || content[0] != (byte) 0xEF || content[1] != (byte) 0xBB
                        || content[2] != (byte) 0xBF) {
                    continue;
                }
                byte[] withoutBom = new byte[content.length - 3];
                System.arraycopy(content, 3, withoutBom, 0, withoutBom.length);
                Files.write(file, withoutBom);
            }
        }
    }

    /**
     * Archives are exported with a single top-level project folder; strip it.
     * Archives without such a folder are used as they are.
     */
    private static Path singleRoot(Path extracted) throws IOException {
        if (Files.isDirectory(extracted.resolve("src"))) {
            return extracted;
        }
        try (var entries = Files.list(extracted)) {
            for (Path item : entries.toList()) {
                if (Files.isDirectory(item) && Files.isDirectory(item.resolve("src"))) {
                    return item;
                }
            }
        }
        return extracted;
    }

    private static void run(List<String> command, Path workDir, String message)
            throws IOException, BuildException {
        Process process = new ProcessBuilder(command)
                .directory(workDir.toFile())
                .redirectErrorStream(true)
                .start();
        String output;
        try (InputStream in = process.getInputStream()) {
            output = new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
        int code;
        try {
            code = process.waitFor();
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            throw new BuildException("Build interrupted");
        }
        if (code != 0) {
            System.err.println(output);
            throw new BuildException(message + ":\n" + trim(output));
        }
    }

    private static void deleteRecursively(Path path) throws IOException {
        if (!Files.exists(path)) {
            return;
        }
        try (var walk = Files.walk(path)) {
            walk.sorted(Comparator.reverseOrder()).forEach(p -> {
                try {
                    Files.deleteIfExists(p);
                } catch (IOException ignored) {
                    // Best effort cleanup.
                }
            });
        }
    }

    private static void respond(HttpExchange exchange, int status, String type, byte[] body)
            throws IOException {
        exchange.getResponseHeaders().set("Content-Type", type);
        exchange.sendResponseHeaders(status, body.length == 0 ? -1 : body.length);
        if (body.length > 0) {
            try (OutputStream out = exchange.getResponseBody()) {
                out.write(body);
            }
        }
    }

    private static void cors(HttpExchange exchange) {
        exchange.getResponseHeaders().set("Access-Control-Allow-Origin", "*");
        exchange.getResponseHeaders().set("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
        exchange.getResponseHeaders().set("Access-Control-Allow-Headers", "Content-Type");
    }

    private static String trim(String value) {
        String trimmed = value.strip();
        return trimmed.length() > 4000 ? trimmed.substring(0, 4000) + "…" : trimmed;
    }

    private static String env(String key, String fallback) {
        String value = System.getenv(key);
        return value == null || value.isBlank() ? fallback : value;
    }

    /** A build problem that should be reported to the user, not as a crash. */
    private static final class BuildException extends Exception {
        BuildException(String message) {
            super(message);
        }
    }
}