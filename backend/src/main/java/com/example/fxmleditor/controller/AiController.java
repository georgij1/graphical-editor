package com.example.fxmleditor.controller;

import com.example.fxmleditor.security.JwtService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.*;

@RestController
@RequestMapping("/api/ai")
@Tag(name = "AI")
public class AiController {
    private final JwtService jwt;
    private final String ollamaUrl;
    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    public AiController(JwtService jwt, @Value("${app.ollama-url:http://host.docker.internal:11434}") String ollamaUrl) {
        this.jwt = jwt;
        this.ollamaUrl = ollamaUrl.replaceAll("/+$", "");
    }

    private String bearer(String auth) {
        if (auth == null || !auth.toLowerCase().startsWith("bearer ")) return null;
        return auth.substring(7).trim();
    }

    private ResponseEntity<?> unauthorized() {
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Not authenticated."));
    }

    private boolean isAuthenticated(String auth) {
        String token = bearer(auth);
        if (token == null || token.isEmpty()) return false;
        try {
            return jwt.verify(token) != null;
        } catch (Exception e) {
            return false;
        }
    }

    @GetMapping("/models")
    @Operation(summary = "List AI models available in Ollama")
    public ResponseEntity<?> listModels(@RequestHeader(value = "Authorization", required = false) String auth) {
        if (!isAuthenticated(auth)) return unauthorized();
        try {
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(ollamaUrl + "/api/tags"))
                    .timeout(Duration.ofSeconds(30))
                    .GET()
                    .build();
            HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (resp.statusCode() != 200) {
                return ResponseEntity.status(resp.statusCode()).body(Map.of("error", "Ollama returned " + resp.statusCode(), "body", resp.body()));
            }
            return ResponseEntity.ok()
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(resp.body());
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY).body(Map.of("error", "Cannot reach Ollama: " + e.getMessage()));
        }
    }

    @PostMapping(value = "/generate")
    @Operation(summary = "Generate AI response via Ollama")
    public ResponseEntity<?> generate(@RequestHeader(value = "Authorization", required = false) String auth,
                                      @RequestBody Map<String, Object> body) {
        if (!isAuthenticated(auth)) return unauthorized();
        boolean stream = body != null && Boolean.TRUE.equals(body.get("stream"));
        String jsonBody;
        try {
            jsonBody = new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(body == null ? Map.of() : body);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("error", "Invalid request body"));
        }

        HttpRequest req = HttpRequest.newBuilder()
                .uri(URI.create(ollamaUrl + "/api/generate"))
                .timeout(Duration.ofMinutes(10))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(jsonBody))
                .build();

        if (!stream) {
            try {
                HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
                return ResponseEntity.status(resp.statusCode())
                        .contentType(MediaType.APPLICATION_JSON)
                        .body(resp.body());
            } catch (Exception e) {
                return ResponseEntity.status(HttpStatus.BAD_GATEWAY).body(Map.of("error", "Cannot reach Ollama: " + e.getMessage()));
            }
        }

        try {
            HttpResponse<InputStream> resp = http.send(req, HttpResponse.BodyHandlers.ofInputStream());
            if (resp.statusCode() != 200) {
                String errBody;
                try (InputStream is = resp.body()) { errBody = new String(is.readAllBytes()); }
                return ResponseEntity.status(resp.statusCode()).contentType(MediaType.APPLICATION_JSON).body(errBody);
            }
            StreamingResponseBody streamBody = outputStream -> {
                try (InputStream is = resp.body(); OutputStream os = outputStream) {
                    byte[] buf = new byte[8192];
                    int n;
                    while ((n = is.read(buf)) != -1) {
                        os.write(buf, 0, n);
                        os.flush();
                    }
                } catch (IOException ignored) {
                    // client disconnected or stream closed
                }
            };
            return ResponseEntity.ok()
                    .contentType(MediaType.parseMediaType("application/x-ndjson"))
                    .body(streamBody);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY).body(Map.of("error", "Cannot reach Ollama: " + e.getMessage()));
        }
    }
}