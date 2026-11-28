package com.example.projectsservice.controller;

import com.example.projectsservice.model.SharedProject;
import com.example.projectsservice.security.JwtService;
import com.example.projectsservice.service.HistoryStore;
import com.example.projectsservice.service.ProjectStore;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.*;

@RestController
@RequestMapping("/api")
@Tag(name = "History")
public class HistoryController {
    private final ProjectStore projects;
    private final JwtService jwt;
    private final HistoryStore history;

    public HistoryController(ProjectStore projects, JwtService jwt, HistoryStore history) {
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

    private static String str(Map<String, Object> body, String key) {
        Object v = body == null ? null : body.get(key);
        return v == null ? "" : v.toString();
    }

    @GetMapping("/projects/{id}/history")
    @Operation(summary = "Project version/build history")
    public ResponseEntity<?> getHistory(@RequestHeader("Authorization") String auth, @PathVariable String id) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        SharedProject project = projects.find(id);
        if (project == null) return ResponseEntity.status(404).body(Map.of("error", "Project not found."));
        if (!project.canRead(jwt.userId(claims), jwt.email(claims))) {
            return ResponseEntity.status(403).body(Map.of("error", "You cannot open this project."));
        }
        return ResponseEntity.ok(history.get(id));
    }

    @PostMapping("/projects/{id}/versions")
    @Operation(summary = "Create a version")
    public ResponseEntity<?> createVersion(@RequestHeader("Authorization") String auth, @PathVariable String id, @RequestBody Map<String, Object> body) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        SharedProject project = projects.find(id);
        if (project == null) return ResponseEntity.status(404).body(Map.of("error", "Project not found."));
        if (!project.canEdit(jwt.userId(claims), jwt.email(claims))) {
            return ResponseEntity.status(403).body(Map.of("error", "You cannot change this project."));
        }
        String summary = str(body, "summary");
        int revision = 0;
        Object rev = body.get("revision");
        if (rev instanceof Number) revision = ((Number) rev).intValue();
        int scenesCount = 0;
        Object sc = body.get("scenesCount");
        if (sc instanceof Number) scenesCount = ((Number) sc).intValue();
        int filesCount = 0;
        Object fc = body.get("filesCount");
        if (fc instanceof Number) filesCount = ((Number) fc).intValue();
        List<String> sceneNames = new ArrayList<>();
        Object sn = body.get("sceneNames");
        if (sn instanceof List) {
            for (Object o : (List<?>) sn) sceneNames.add(String.valueOf(o));
        }
        String author = jwt.email(claims);
        return ResponseEntity.ok(history.createVersion(id, summary, revision, scenesCount, filesCount, sceneNames, author));
    }

    @PostMapping("/projects/{id}/builds")
    @Operation(summary = "Record a build")
    public ResponseEntity<?> recordBuild(@RequestHeader("Authorization") String auth, @PathVariable String id, @RequestBody Map<String, Object> body) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        SharedProject project = projects.find(id);
        if (project == null) return ResponseEntity.status(404).body(Map.of("error", "Project not found."));
        if (!project.canEdit(jwt.userId(claims), jwt.email(claims))) {
            return ResponseEntity.status(403).body(Map.of("error", "You cannot change this project."));
        }
        Map<String, Object> build = new HashMap<>(body == null ? Map.of() : body);
        if (!build.containsKey("date")) build.put("date", Instant.now().toString());
        if (!build.containsKey("author")) build.put("author", jwt.email(claims));
        return ResponseEntity.ok(history.recordBuild(id, build));
    }
}
