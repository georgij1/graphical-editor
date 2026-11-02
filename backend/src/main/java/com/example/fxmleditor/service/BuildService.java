package com.example.fxmleditor.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.Comparator;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

@Service
public class BuildService {

    private static final int MAX_BODY = 64 * 1024 * 1024;
    private final Path javafxLib;
    private final String javaModules;

    private static final Pattern PACKAGE = Pattern.compile("(?m)^\\s*package\\s+([\\w.]+)\\s*;");
    private static final Pattern APPLICATION_CLASS =
            Pattern.compile("public\\s+class\\s+(\\w+)\\s+extends\\s+Application");

    public BuildService(@Value("${app.javafx-lib:/opt/javafx/lib}") String javafxLib,
                        @Value("${app.java-modules:javafx.controls,javafx.fxml}") String javaModules) {
        this.javafxLib = Paths.get(javafxLib);
        this.javaModules = javaModules;
    }

    public static class BuildException extends Exception {
        public BuildException(String message) { super(message); }
    }

    public byte[] build(byte[] archive, boolean bundle) throws IOException, BuildException {
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
            List<String> javac = new ArrayList<>(List.of(
                    "javac", "-nowarn", "-encoding", "UTF-8", "--release", "21",
                    "-cp", javafxLib + "/*",
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

    private byte[] bundle(Path work, Path jar, String mainClass) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(buffer)) {
            zip.putNextEntry(new ZipEntry("app.jar"));
            Files.copy(jar, zip);
            zip.closeEntry();

            try (var jars = Files.list(javafxLib)) {
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

    private String detectMainClass(List<Path> sources) throws IOException, BuildException {
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

    private Path unzip(byte[] archive, Path target) throws IOException, BuildException {
        Path nested = target.resolve("project");
        Files.createDirectories(nested);
        try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(archive))) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                String name = entry.getName().replace('\\', '/');
                Path destination = nested.resolve(name).normalize();
                if (!destination.startsWith(nested)) {
                    throw new BuildException("Archive contains an unsafe path: " + name);
                }
                if (name.endsWith("/")) {
                    Files.createDirectories(destination);
                    continue;
                }
                Files.createDirectories(destination.getParent());
                Files.copy(zip, destination, StandardCopyOption.REPLACE_EXISTING);
            }
        }
        stripByteOrderMarks(nested);
        return nested;
    }

    private void stripByteOrderMarks(Path root) throws IOException {
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

    private Path singleRoot(Path extracted) throws IOException {
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

    private void run(List<String> command, Path workDir, String message)
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

    private void deleteRecursively(Path path) throws IOException {
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

    private String trim(String value) {
        String trimmed = value.strip();
        return trimmed.length() > 4000 ? trimmed.substring(0, 4000) + "…" : trimmed;
    }
}
