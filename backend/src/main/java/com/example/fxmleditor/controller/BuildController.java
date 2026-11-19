package com.example.fxmleditor.controller;

import com.example.fxmleditor.service.BuildService;
import com.example.fxmleditor.service.BuildService.BuildException;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;

@RestController
@RequestMapping("/build")
@Tag(name = "Build")
public class BuildController {

    private final BuildService buildService;

    public BuildController(BuildService buildService) {
        this.buildService = buildService;
    }

    @PostMapping
    @Operation(summary = "Compile an exported project into a runnable JAR")
    public ResponseEntity<byte[]> buildJar(@RequestBody byte[] archive) {
        try {
            byte[] artifact = buildService.build(archive, false);
            return ResponseEntity.ok()
                    .header("Content-Disposition", "attachment; filename=\"app.jar\"")
                    .header("X-Artifact", "app.jar")
                    .contentType(MediaType.APPLICATION_OCTET_STREAM)
                    .body(artifact);
        } catch (BuildException e) {
            return ResponseEntity.badRequest()
                    .contentType(MediaType.TEXT_PLAIN)
                    .body(e.getMessage().getBytes());
        } catch (Exception e) {
            return ResponseEntity.status(500)
                    .contentType(MediaType.TEXT_PLAIN)
                    .body(("Build failed: " + e).getBytes());
        }
    }

    @PostMapping("/bundle")
    @Operation(summary = "Compile an exported project into a self-contained bundle (JAR + JavaFX + run scripts)")
    public ResponseEntity<byte[]> buildBundle(@RequestBody byte[] archive) {
        try {
            byte[] artifact = buildService.build(archive, true);
            return ResponseEntity.ok()
                    .header("Content-Disposition", "attachment; filename=\"bundle.zip\"")
                    .header("X-Artifact", "bundle.zip")
                    .contentType(MediaType.APPLICATION_OCTET_STREAM)
                    .body(artifact);
        } catch (BuildException e) {
            return ResponseEntity.badRequest()
                    .contentType(MediaType.TEXT_PLAIN)
                    .body(e.getMessage().getBytes());
        } catch (Exception e) {
            return ResponseEntity.status(500)
                    .contentType(MediaType.TEXT_PLAIN)
                    .body(("Build failed: " + e).getBytes());
        }
    }

    @PostMapping("/check")
    @Operation(summary = "Compile project sources and return compiler diagnostics")
    public ResponseEntity<?> check(@RequestBody byte[] archive) {
        try {
            var diagnostics = buildService.check(archive);
            return ResponseEntity.ok(java.util.Map.of("diagnostics", diagnostics));
        } catch (BuildException e) {
            return ResponseEntity.badRequest()
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(java.util.Map.of("error", e.getMessage(), "diagnostics", java.util.List.of()));
        } catch (Exception e) {
            return ResponseEntity.status(500)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(java.util.Map.of("error", "Check failed: " + e, "diagnostics", java.util.List.of()));
        }
    }

    @GetMapping("/validate-dependency")
    @Operation(summary = "Validate that a Maven/Gradle dependency exists in Maven Central")
    public ResponseEntity<?> validateDependency(
            @RequestParam(required = false) String groupId,
            @RequestParam(required = false) String artifactId,
            @RequestParam(required = false) String version,
            @RequestParam(required = false) String notation) {
        String g = groupId == null ? "" : groupId.trim();
        String a = artifactId == null ? "" : artifactId.trim();
        String v = version == null ? "" : version.trim();

        if ((g.isEmpty() || a.isEmpty()) && notation != null && !notation.trim().isEmpty()) {
            String[] parts = notation.trim().split(":");
            if (parts.length >= 2) {
                g = parts[0].trim();
                a = parts[1].trim();
                if (parts.length >= 3 && v.isEmpty()) {
                    v = parts[2].trim();
                }
            }
        }

        if (g.isEmpty() || a.isEmpty()) {
            return ResponseEntity.badRequest().body(java.util.Map.of(
                    "valid", false,
                    "message", "Group ID and Artifact ID are required"));
        }
        if (g.contains("..") || a.contains("..") || v.contains("..")
                || g.contains("/") || a.contains("/") || g.contains("\\") || a.contains("\\")) {
            return ResponseEntity.badRequest().body(java.util.Map.of(
                    "valid", false,
                    "message", "Invalid dependency coordinates"));
        }

        String groupPath = g.replace('.', '/');
        String base = "https://repo1.maven.org/maven2/" + groupPath + "/" + a + "/";
        java.util.List<String> urls = new java.util.ArrayList<>();
        if (!v.isEmpty()) {
            urls.add(base + v + "/" + a + "-" + v + ".pom");
            urls.add(base + v + "/" + a + "-" + v + ".jar");
        }
        urls.add(base + "maven-metadata.xml");

        try {
            HttpClient client = HttpClient.newBuilder()
                    .connectTimeout(Duration.ofSeconds(5))
                    .followRedirects(HttpClient.Redirect.NORMAL)
                    .build();
            boolean found = false;
            for (String url : urls) {
                try {
                    HttpRequest req = HttpRequest.newBuilder(URI.create(url))
                            .timeout(Duration.ofSeconds(6))
                            .method("HEAD", HttpRequest.BodyPublishers.noBody())
                            .header("User-Agent", "graphical-editor-dependency-validator")
                            .build();
                    HttpResponse<Void> resp = client.send(req, HttpResponse.BodyHandlers.discarding());
                    int code = resp.statusCode();
                    if (code >= 200 && code < 300) {
                        found = true;
                        break;
                    }
                    if (code == 405) { // HEAD not allowed, try GET
                        HttpRequest getReq = HttpRequest.newBuilder(URI.create(url))
                                .timeout(Duration.ofSeconds(6))
                                .GET()
                                .header("User-Agent", "graphical-editor-dependency-validator")
                                .build();
                        HttpResponse<Void> getResp = client.send(getReq, HttpResponse.BodyHandlers.discarding());
                        int gcode = getResp.statusCode();
                        if (gcode >= 200 && gcode < 300) {
                            found = true;
                            break;
                        }
                    }
                } catch (Exception ignored) {
                    // try next URL
                }
            }
            if (found) {
                // If a specific version was requested, ensure that specific version exists
                // (metadata existence alone means artifact exists but maybe not that version).
                if (!v.isEmpty()) {
                    boolean versionFound = false;
                    for (String url : urls) {
                        if (!url.contains("/" + v + "/")) continue;
                        try {
                            HttpRequest req = HttpRequest.newBuilder(URI.create(url))
                                    .timeout(Duration.ofSeconds(6))
                                    .method("HEAD", HttpRequest.BodyPublishers.noBody())
                                    .header("User-Agent", "graphical-editor-dependency-validator")
                                    .build();
                            HttpResponse<Void> resp = client.send(req, HttpResponse.BodyHandlers.discarding());
                            int code = resp.statusCode();
                            if (code == 405) {
                                HttpRequest getReq = HttpRequest.newBuilder(URI.create(url))
                                        .timeout(Duration.ofSeconds(6))
                                        .GET()
                                        .header("User-Agent", "graphical-editor-dependency-validator")
                                        .build();
                                HttpResponse<Void> getResp = client.send(getReq, HttpResponse.BodyHandlers.discarding());
                                code = getResp.statusCode();
                            }
                            if (code >= 200 && code < 300) {
                                versionFound = true;
                                break;
                            }
                        } catch (Exception ignored) {
                        }
                    }
                    if (!versionFound) {
                        return ResponseEntity.ok(java.util.Map.of(
                                "valid", false,
                                "message", "Dependency version not found in Maven Central"));
                    }
                }
                return ResponseEntity.ok(java.util.Map.of("valid", true));
            }
            return ResponseEntity.ok(java.util.Map.of(
                    "valid", false,
                    "message", "Dependency not found in Maven Central"));
        } catch (Exception e) {
            return ResponseEntity.status(502).body(java.util.Map.of(
                    "valid", false,
                    "message", "Could not validate dependency: " + e.getMessage()));
        }
    }

    @GetMapping("/health")
    @Operation(summary = "Health check for the build service")
    public ResponseEntity<?> health() {
        return ResponseEntity.ok(java.util.Map.of("status", "ok"));
    }
}
