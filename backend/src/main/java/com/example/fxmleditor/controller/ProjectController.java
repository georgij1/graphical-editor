package com.example.fxmleditor.controller;

import com.example.fxmleditor.model.ProjectMember;
import com.example.fxmleditor.model.SharedProject;
import com.example.fxmleditor.security.JwtService;
import com.example.fxmleditor.service.ProjectStore;
import com.example.fxmleditor.service.UserStore;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api")
@Tag(name = "Projects")
public class ProjectController {
    private final ProjectStore projects;
    private final UserStore users;
    private final JwtService jwt;

    public ProjectController(ProjectStore projects, UserStore users, JwtService jwt) {
        this.projects = projects;
        this.users = users;
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

    @GetMapping("/projects")
    @Operation(summary = "List shared projects readable by the user")
    public ResponseEntity<?> listProjects(@RequestHeader("Authorization") String auth) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        String uid = jwt.userId(claims);
        String email = jwt.email(claims);
        var list = projects.listFor(uid, email);
        return ResponseEntity.ok(Map.of("projects", list));
    }

    @GetMapping("/projects/{id}")
    @Operation(summary = "Get one shared project")
    public ResponseEntity<?> getProject(@RequestHeader("Authorization") String auth, @PathVariable String id) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        SharedProject p = projects.find(id);
        if (p == null) return ResponseEntity.status(404).body(Map.of("error", "Project not found."));
        String uid = jwt.userId(claims);
        String email = jwt.email(claims);
        if (!p.canRead(uid, email)) return ResponseEntity.status(403).body(Map.of("error", "You cannot open this project."));
        return ResponseEntity.ok(p);
    }

    @PutMapping("/projects/{id}")
    @Operation(summary = "Create or update a shared project")
    public ResponseEntity<?> saveProject(@RequestHeader("Authorization") String auth, @PathVariable String id, @RequestBody Map<String, Object> body) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        String uid = jwt.userId(claims);
        String email = jwt.email(claims);
        SharedProject existing = projects.find(id);
        if (existing != null && !existing.canEdit(uid, email)) {
            return ResponseEntity.status(403).body(Map.of("error", "You cannot change this project."));
        }
        SharedProject project = fromJson(body, id, existing, uid, email);
        SharedProject saved = projects.save(project);
        return ResponseEntity.ok(saved);
    }

    @PostMapping("/projects/{id}/members")
    @Operation(summary = "Add a participant")
    public ResponseEntity<?> addMember(@RequestHeader("Authorization") String auth, @PathVariable String id, @RequestBody Map<String, Object> body) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        String uid = jwt.userId(claims);
        String email = jwt.email(claims);
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

    @DeleteMapping("/projects/{id}")
    @Operation(summary = "Delete a shared project")
    public ResponseEntity<?> deleteProject(@RequestHeader("Authorization") String auth, @PathVariable String id) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        String uid = jwt.userId(claims);
        SharedProject project = projects.find(id);
        if (project == null) return ResponseEntity.status(404).body(Map.of("error", "Project not found."));
        if (!project.ownerId.equals(uid)) return ResponseEntity.status(403).body(Map.of("error", "Only the owner can delete the project."));
        projects.delete(id);
        return ResponseEntity.noContent().build();
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

    // ---------- presence ----------

    // In-memory presence
    private final Map<String, Map<String, Map<String, Object>>> presence = new java.util.concurrent.ConcurrentHashMap<>();

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
        var user = users.findById(uid);
        var bucket = presence.computeIfAbsent(id, k -> new java.util.concurrent.ConcurrentHashMap<>());
        Map<String, Object> entry = new java.util.HashMap<>();
        entry.put("id", uid);
        entry.put("email", email);
        entry.put("avatar", user == null || user.avatar == null ? "" : user.avatar);
        entry.put("lastSeen", java.time.Instant.now().toString());
        if (body != null) {
            if (body.get("cursorX") instanceof Number) entry.put("cursorX", ((Number) body.get("cursorX")).doubleValue());
            if (body.get("cursorY") instanceof Number) entry.put("cursorY", ((Number) body.get("cursorY")).doubleValue());
            if (body.get("selectedNodeId") != null) entry.put("selectedNodeId", body.get("selectedNodeId").toString());
            else entry.put("selectedNodeId", null);
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
        java.time.Instant cutoff = java.time.Instant.now().minusSeconds(60);
        List<Map<String, Object>> result = new ArrayList<>();
        if (bucket != null) {
            List<String> stale = new ArrayList<>();
            for (var e : bucket.entrySet()) {
                java.time.Instant lastSeen = null;
                try { lastSeen = java.time.Instant.parse((String) e.getValue().get("lastSeen")); } catch (Exception ignored) {}
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

    // ---------- history ----------

    @GetMapping("/projects/{id}/history")
    @Operation(summary = "Project version/build history")
    public ResponseEntity<?> getHistory(@RequestHeader("Authorization") String auth, @PathVariable String id) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        // history store is separate; return empty for now
        return ResponseEntity.ok(Map.of("projectId", id, "versions", List.of(), "builds", List.of()));
    }

    @PostMapping("/projects/{id}/versions")
    @Operation(summary = "Create a version")
    public ResponseEntity<?> createVersion(@RequestHeader("Authorization") String auth, @PathVariable String id, @RequestBody Map<String, Object> body) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        return ResponseEntity.ok(Map.of("ok", true));
    }

    @PostMapping("/projects/{id}/builds")
    @Operation(summary = "Record a build")
    public ResponseEntity<?> recordBuild(@RequestHeader("Authorization") String auth, @PathVariable String id, @RequestBody Map<String, Object> body) {
        var claims = auth(auth);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        return ResponseEntity.ok(Map.of("ok", true));
    }

    private SharedProject fromJson(Map<String, Object> body, String id, SharedProject existing, String uid, String email) {
        SharedProject p = new SharedProject();
        p.id = id;
        p.name = str(body, "name");
        if (p.name.isEmpty()) p.name = existing == null ? "Untitled" : existing.name;
        p.packageName = str(body, "package");
        if (p.packageName.isEmpty() && existing != null) p.packageName = existing.packageName;
        p.mainClass = str(body, "mainClass");
        if (p.mainClass.isEmpty()) p.mainClass = existing == null ? "MainApp" : existing.mainClass;
        p.description = str(body, "description");
        p.ownerId = existing == null ? uid : existing.ownerId;
        p.ownerEmail = existing == null ? email : existing.ownerEmail;
        p.revision = existing == null ? 0 : existing.revision;
        Object members = body.get("members");
        if (members instanceof List) {
            p.members.clear();
            for (Object m : (List<?>) members) {
                if (m instanceof Map) {
                    Map<?, ?> mm = (Map<?, ?>) m;
                    p.members.add(new ProjectMember(strMap(mm, "email"), strMap(mm, "role").isEmpty() ? "editor" : strMap(mm, "role")));
                }
            }
        } else if (existing != null) {
            p.members = existing.members;
        }
        Object scenes = body.get("scenes");
        if (scenes instanceof List) {
            p.scenes = new ArrayList<>();
            for (Object s : (List<?>) scenes) {
                if (s instanceof Map) p.scenes.add(new java.util.HashMap<>((Map<String, Object>) s));
            }
        } else if (existing != null) {
            p.scenes = existing.scenes;
        }
        Object sources = body.get("sources");
        if (sources instanceof Map) {
            p.sources = new java.util.HashMap<>();
            for (var e : ((Map<?, ?>) sources).entrySet()) {
                p.sources.put(String.valueOf(e.getKey()), String.valueOf(e.getValue()));
            }
        } else if (existing != null) {
            p.sources = existing.sources;
        }
        if (body.get("inviteToken") != null) p.inviteToken = body.get("inviteToken").toString();
        if (body.get("inviteRole") != null) p.inviteRole = body.get("inviteRole").toString();
        return p;
    }

    private String str(Map<String, Object> body, String key) {
        Object v = body.get(key);
        return v == null ? "" : v.toString();
    }

    private String strMap(Map<?, ?> m, String key) {
        Object v = m.get(key);
        return v == null ? "" : v.toString();
    }
}
