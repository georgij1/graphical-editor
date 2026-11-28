package com.example.projectsservice.controller;

import com.example.projectsservice.model.ProjectMember;
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
@Tag(name = "Members")
public class MembersController {
    private final ProjectStore projects;
    private final JwtService jwt;
    private final Map<String, Map<String, Map<String, Object>>> presence = new ConcurrentHashMap<>();

    public MembersController(ProjectStore projects, JwtService jwt) {
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

    private static String str(Map<String, Object> body, String key) {
        Object v = body.get(key);
        return v == null ? "" : String.valueOf(v);
    }

    @PostMapping("/projects/{id}/members")
    @Operation(summary = "Add a participant")
    public ResponseEntity<?> addMember(@RequestHeader("Authorization") String auth, @PathVariable String id, @RequestBody Map<String, Object> body) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        String uid = jwt.userId(claims);
        SharedProject project = projects.find(id);
        if (project == null) return ResponseEntity.status(404).body(Map.of("error", "Project not found."));
        if (!project.ownerId.equals(uid)) return ResponseEntity.status(403).body(Map.of("error", "Only the owner can invite people."));
        String memberEmail = str(body, "email").trim().toLowerCase();
        if (!memberEmail.matches("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")) {
            return ResponseEntity.badRequest().body(Map.of("error", "Enter a valid email address."));
        }
        String role = str(body, "role");
        if (role.isEmpty()) role = "editor";
        if (!role.equals("editor") && !role.equals("viewer")) {
            return ResponseEntity.badRequest().body(Map.of("error", "Unknown role."));
        }
        ProjectMember member = project.memberOf(memberEmail);
        if (member != null) {
            member.role = role;
        } else {
            project.members.add(new ProjectMember(memberEmail, role));
        }
        SharedProject saved = projects.save(project);
        return ResponseEntity.ok(saved);
    }

    @DeleteMapping("/projects/{id}/members/{email}")
    @Operation(summary = "Remove a participant")
    public ResponseEntity<?> removeMember(@RequestHeader("Authorization") String auth, @PathVariable String id, @PathVariable String email) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        String uid = jwt.userId(claims);
        SharedProject project = projects.find(id);
        if (project == null) return ResponseEntity.status(404).body(Map.of("error", "Project not found."));
        if (!project.ownerId.equals(uid)) return ResponseEntity.status(403).body(Map.of("error", "Only the owner can remove people."));
        project.members.removeIf(m -> m.email != null && m.email.equalsIgnoreCase(email));
        SharedProject saved = projects.save(project);
        return ResponseEntity.ok(saved);
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

    @PostMapping("/projects/{id}/transfer")
    @Operation(summary = "Transfer project ownership")
    public ResponseEntity<?> transferProject(@RequestHeader("Authorization") String auth, @PathVariable String id, @RequestBody Map<String, Object> body) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        String uid = jwt.userId(claims);
        String email = jwt.email(claims);
        SharedProject project = projects.find(id);
        if (project == null) return ResponseEntity.status(404).body(Map.of("error", "Project not found."));
        if (project.ownerId == null || !project.ownerId.equals(uid)) {
            return ResponseEntity.status(403).body(Map.of("error", "Only the owner can transfer the project."));
        }
        String newEmail = str(body, "email").trim().toLowerCase();
        if (!newEmail.matches("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")) {
            return ResponseEntity.badRequest().body(Map.of("error", "Enter a valid email address."));
        }
        if (newEmail.equalsIgnoreCase(email)) {
            return ResponseEntity.badRequest().body(Map.of("error", "You already own this project."));
        }
        ProjectMember targetMember = project.memberOf(newEmail);
        // If not a participant yet, add them as editor so ownership can be transferred.
        if (targetMember == null) {
            project.members.add(new ProjectMember(newEmail, "editor"));
        }
        String newOwnerId = str(body, "userId");
        if (newOwnerId.isBlank()) newOwnerId = str(body, "id");
        if (newOwnerId.isBlank()) {
            // Try to resolve from other projects owned by this email.
            for (SharedProject p : projects.listAll()) {
                if (p != null && newEmail.equalsIgnoreCase(p.ownerEmail) && p.ownerId != null && !p.ownerId.isBlank()) {
                    newOwnerId = p.ownerId;
                    break;
                }
            }
        }
        // Previous owner becomes a participant (editor) so they keep access.
        ProjectMember previous = project.memberOf(email);
        if (previous == null) {
            project.members.add(new ProjectMember(email, "editor"));
        } else {
            previous.role = "editor";
        }
        // Remove new owner from members list.
        final String ne = newEmail;
        project.members.removeIf(m -> m.email != null && m.email.equalsIgnoreCase(ne));

        project.ownerEmail = newEmail;
        if (!newOwnerId.isBlank()) {
            project.ownerId = newOwnerId;
        }
        SharedProject saved = projects.save(project);
        return ResponseEntity.ok(saved);
    }
}
