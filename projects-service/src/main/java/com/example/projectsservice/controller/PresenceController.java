package com.example.projectsservice.controller;

import com.example.projectsservice.model.SharedProject;
import com.example.projectsservice.security.JwtService;
import com.example.projectsservice.service.ProjectStore;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

@RestController
@RequestMapping("/api")
@Tag(name = "Presence")
public class PresenceController {
    private final ProjectStore projects;
    private final JwtService jwt;
    private final Map<String, Map<String, Map<String, Object>>> presence = new ConcurrentHashMap<>();

    public PresenceController(ProjectStore projects, JwtService jwt) {
        this.projects = projects;
        this.jwt = jwt;
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

    @PostMapping("/projects/{id}/presence")
    @Operation(summary = "Heartbeat: announce that the project is open")
    public ResponseEntity<?> heartbeat(@RequestHeader("Authorization") String auth, @PathVariable String id, @RequestBody(required = false) Map<String, Object> body) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        String uid = jwt.userId(claims);
        String email = jwt.email(claims);
        SharedProject project = projects.find(id);
        if (project == null) return ResponseEntity.status(404).body(Map.of("error", "Project not found."));
        if (!project.canRead(uid, email)) return ResponseEntity.status(403).body(Map.of("error", "You cannot open this project."));
        var bucket = presence.computeIfAbsent(id, k -> new ConcurrentHashMap<>());
        Map<String, Object> entry = new HashMap<>();
        entry.put("id", uid);
        entry.put("email", email);
        entry.put("avatar", "");
        entry.put("lastSeen", Instant.now().toString());
        if (body != null) {
            if (body.containsKey("cursorX")) {
                Object v = body.get("cursorX");
                if (v instanceof Number) entry.put("cursorX", ((Number) v).doubleValue());
                else entry.remove("cursorX");
            }
            if (body.containsKey("cursorY")) {
                Object v = body.get("cursorY");
                if (v instanceof Number) entry.put("cursorY", ((Number) v).doubleValue());
                else entry.remove("cursorY");
            }
            if (body.containsKey("selectedNodeId")) {
                Object v = body.get("selectedNodeId");
                if (v == null) entry.remove("selectedNodeId");
                else entry.put("selectedNodeId", v.toString());
            }
        }
        bucket.put(uid, entry);
        return ResponseEntity.ok(Map.of("ok", true));
    }

    @GetMapping("/projects/{id}/presence")
    @Operation(summary = "Who is currently in the project")
    public ResponseEntity<?> listPresence(@RequestHeader("Authorization") String auth, @PathVariable String id) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        String uid = jwt.userId(claims);
        String email = jwt.email(claims);
        SharedProject project = projects.find(id);
        if (project == null) return ResponseEntity.status(404).body(Map.of("error", "Project not found."));
        if (!project.canRead(uid, email)) return ResponseEntity.status(403).body(Map.of("error", "You cannot open this project."));
        var bucket = presence.get(id);
        Instant cutoff = Instant.now().minusSeconds(60);
        List<Map<String, Object>> result = new ArrayList<>();
        if (bucket != null) {
            List<String> stale = new ArrayList<>();
            for (var e : bucket.entrySet()) {
                Instant lastSeen = null;
                try { lastSeen = Instant.parse((String) e.getValue().get("lastSeen")); } catch (Exception ignored) {}
                if (lastSeen == null || lastSeen.isBefore(cutoff)) {
                    stale.add(e.getKey());
                } else {
                    result.add(e.getValue());
                }
            }
            for (String k : stale) bucket.remove(k);
        }
        return ResponseEntity.ok(Map.of("participants", result));
    }
}
