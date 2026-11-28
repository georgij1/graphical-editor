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
@Tag(name = "Members")
public class MembersController {
    private final ProjectStore projects;
    private final JwtService jwt;

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
}
