package com.example.analyzerservice.controller;

import com.example.analyzerservice.model.SharedProject;
import com.example.analyzerservice.security.JwtService;
import com.example.analyzerservice.service.HistoryStore;
import com.example.analyzerservice.service.ProjectStore;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.*;

@RestController
@RequestMapping("/api")
@Tag(name = "Checks")
public class ChecksController {
    private final ProjectStore projects;
    private final JwtService jwt;
    private final HistoryStore history;

    public ChecksController(ProjectStore projects, JwtService jwt, HistoryStore history) {
        this.projects = projects;
        this.jwt = jwt;
        this.history = history;
    }

    private String bearer(String auth) {
        if (auth == null || !auth.toLowerCase().startsWith("bearer ")) return null;
        return auth.substring(7).trim();
    }

    private io.jsonwebtoken.Claims auth(String authHeader) {
        String t = bearer(authHeader);
        if (t == null) return null;
        return jwt.verify(t);
    }

    @GetMapping("/projects/{id}/checks")
    @Operation(summary = "File check/compilation history")
    public ResponseEntity<?> getChecks(@RequestHeader("Authorization") String auth,
                                       @PathVariable String id,
                                       @RequestParam(required = false) String file,
                                       @RequestParam(defaultValue = "50") int limit) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        SharedProject project = projects.find(id);
        if (project == null) return ResponseEntity.status(404).body(Map.of("error", "Project not found."));
        if (!project.canRead(jwt.userId(claims), jwt.email(claims))) {
            return ResponseEntity.status(403).body(Map.of("error", "You cannot open this project."));
        }
        return ResponseEntity.ok(Map.of("checks", history.getChecks(id, file, Math.max(1, Math.min(limit, 200)))));
    }

    @PostMapping("/projects/{id}/checks")
    @Operation(summary = "Record a file check/compilation result")
    public ResponseEntity<?> recordCheck(@RequestHeader("Authorization") String auth,
                                         @PathVariable String id,
                                         @RequestBody Map<String, Object> body) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        SharedProject project = projects.find(id);
        if (project == null) return ResponseEntity.status(404).body(Map.of("error", "Project not found."));
        if (!project.canRead(jwt.userId(claims), jwt.email(claims))) {
            return ResponseEntity.status(403).body(Map.of("error", "You cannot open this project."));
        }
        String file = String.valueOf(body == null ? "" : body.getOrDefault("file", "")).trim();
        if (file.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "File is required."));
        }
        Map<String, Object> check = new HashMap<>();
        check.put("id", UUID.randomUUID().toString());
        check.put("file", file);
        check.put("date", Instant.now().toString());
        check.put("author", jwt.email(claims));
        Object diags = body == null ? null : body.get("diagnostics");
        if (diags instanceof List) {
            check.put("diagnostics", diags);
        } else {
            check.put("diagnostics", List.of());
        }
        Object contentHash = body == null ? null : body.get("contentHash");
        if (contentHash != null && !String.valueOf(contentHash).isBlank()) {
            check.put("contentHash", contentHash);
        }
        if (body != null && body.containsKey("content") && body.get("content") != null) {
            check.put("content", String.valueOf(body.get("content")));
        }
        history.recordCheck(id, check);
        return ResponseEntity.ok(check);
    }
}
