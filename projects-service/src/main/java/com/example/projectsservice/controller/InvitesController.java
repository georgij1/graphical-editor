package com.example.projectsservice.controller;

import com.example.projectsservice.model.ProjectMember;
import com.example.projectsservice.model.SharedProject;
import com.example.projectsservice.security.JwtService;
import com.example.projectsservice.service.ProjectStore;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api")
@Tag(name = "Invites")
public class InvitesController {
    private final ProjectStore projects;
    private final JwtService jwt;

    public InvitesController(ProjectStore projects, JwtService jwt) {
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
        Object v = body == null ? null : body.get(key);
        return v == null ? "" : v.toString();
    }

    @PostMapping("/projects/{id}/invite")
    @Operation(summary = "Create an invitation link")
    public ResponseEntity<?> createInvite(@RequestHeader("Authorization") String auth, @PathVariable String id, @RequestBody Map<String, Object> body) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        String uid = jwt.userId(claims);
        SharedProject project = projects.find(id);
        if (project == null) return ResponseEntity.status(404).body(Map.of("error", "Project not found."));
        if (!project.ownerId.equals(uid)) return ResponseEntity.status(403).body(Map.of("error", "Only the owner can invite people."));
        String role = str(body, "role");
        if (role.isEmpty()) role = "editor";
        String token = project.createInvite(role);
        projects.save(project);
        return ResponseEntity.ok(Map.of("token", token, "role", role, "projectId", project.id));
    }

    @GetMapping("/invites/{token}")
    @Operation(summary = "Resolve an invitation link")
    public ResponseEntity<?> getInvite(@RequestHeader(value = "Authorization", required = false) String auth, @PathVariable String token) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        SharedProject project = projects.findByInvite(token);
        if (project == null) return ResponseEntity.status(404).body(Map.of("error", "The invitation is not valid."));
        Map<String, Object> resp = new java.util.HashMap<>();
        resp.put("token", token);
        resp.put("role", project.inviteRole);
        resp.put("projectId", project.id);
        resp.put("projectName", project.name);
        resp.put("ownerEmail", project.ownerEmail);
        return ResponseEntity.ok(resp);
    }

    @PostMapping("/projects/{id}/join")
    @Operation(summary = "Join a project via invitation")
    public ResponseEntity<?> joinProject(@RequestHeader("Authorization") String auth, @PathVariable String id, @RequestBody Map<String, Object> body) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        String uid = jwt.userId(claims);
        String email = jwt.email(claims);
        String inviteToken = str(body, "token");
        SharedProject project = projects.find(id);
        if (project == null) return ResponseEntity.status(404).body(Map.of("error", "Project not found."));
        if (!project.matchesInvite(inviteToken)) return ResponseEntity.status(400).body(Map.of("error", "The invitation is not valid."));
        if (!project.members.stream().anyMatch(m -> m.email.equalsIgnoreCase(email)) && !project.ownerEmail.equalsIgnoreCase(email)) {
            project.members.add(new ProjectMember(email, "editor"));
        }
        SharedProject saved = projects.save(project);
        return ResponseEntity.ok(saved);
    }
}
