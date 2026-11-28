package com.example.projectsservice.controller;

import com.example.projectsservice.model.SharedProject;
import com.example.projectsservice.security.JwtService;
import com.example.projectsservice.service.ProjectFileStorageService;
import com.example.projectsservice.service.ProjectStore;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api")
@Tag(name = "Archive")
public class ArchiveController {
    private final ProjectStore projects;
    private final JwtService jwt;
    private final ProjectFileStorageService projectFiles;

    public ArchiveController(ProjectStore projects, JwtService jwt, ProjectFileStorageService projectFiles) {
        this.projects = projects;
        this.jwt = jwt;
        this.projectFiles = projectFiles;
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

    @GetMapping("/projects/{id}/download")
    @Operation(summary = "Download project files as a zip")
    public ResponseEntity<?> downloadProject(@RequestHeader("Authorization") String auth, @PathVariable String id) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        SharedProject p = projects.find(id);
        if (p == null) return ResponseEntity.status(404).body(Map.of("error", "Project not found."));
        String uid = jwt.userId(claims);
        String email = jwt.email(claims);
        if (!p.canRead(uid, email)) return ResponseEntity.status(403).body(Map.of("error", "You cannot open this project."));
        byte[] zip = projectFiles.downloadZip(id);
        if (zip == null || zip.length == 0) {
            try {
                projectFiles.syncProject(p);
                zip = projectFiles.downloadZip(id);
            } catch (Exception ignored) {
            }
        }
        if (zip == null || zip.length == 0) {
            return ResponseEntity.status(404).body(Map.of("error", "No project files found."));
        }
        String name = p.name == null || p.name.isBlank() ? "project" : p.name.trim();
        String safe = name.replaceAll("[^a-zA-Z0-9._-]", "_");
        if (safe.isBlank()) safe = "project";
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + safe + ".zip\"")
                .contentType(MediaType.parseMediaType("application/zip"))
                .body(zip);
    }
}
