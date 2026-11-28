package com.example.projectsservice.controller;

import com.example.projectsservice.model.ProjectMember;
import com.example.projectsservice.model.SharedProject;
import com.example.projectsservice.security.JwtService;
import com.example.projectsservice.service.HistoryStore;
import com.example.projectsservice.service.ProjectFileStorageService;
import com.example.projectsservice.service.ProjectStore;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api")
@Tag(name = "Projects")
public class ProjectController {
    private final ProjectStore projects;
    private final JwtService jwt;
    private final HistoryStore history;
    private final ProjectFileStorageService projectFiles;

    public ProjectController(ProjectStore projects, JwtService jwt, HistoryStore history, ProjectFileStorageService projectFiles) {
        this.projects = projects;
        this.jwt = jwt;
        this.history = history;
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
        String ownerId = project.ownerId == null ? uid : project.ownerId;
        String newName = project.name == null ? "" : project.name.trim();
        if (!newName.isEmpty()) {
            for (SharedProject p : projects.listAll()) {
                if (p == null || p.id == null || p.id.equals(id)) continue;
                if (ownerId != null && ownerId.equals(p.ownerId)
                        && p.name != null && p.name.trim().equalsIgnoreCase(newName)) {
                    return ResponseEntity.status(409).body(Map.of("error", "A project with this name already exists."));
                }
            }
        }
        SharedProject saved = projects.save(project);
        return ResponseEntity.ok(saved);
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
        var bucket = presence.computeIfAbsent(id, k -> new java.util.concurrent.ConcurrentHashMap<>());
        Map<String, Object> entry = new java.util.HashMap<>();
        entry.put("id", uid);
        entry.put("email", email);
        entry.put("avatar", "");
        entry.put("lastSeen", java.time.Instant.now().toString());
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
        Map<String, Object> build = new java.util.HashMap<>(body == null ? Map.of() : body);
        if (!build.containsKey("date")) build.put("date", java.time.Instant.now().toString());
        if (!build.containsKey("author")) build.put("author", jwt.email(claims));
        return ResponseEntity.ok(history.recordBuild(id, build));
    }

    @GetMapping("/projects/{id}/checks")
    @Operation(summary = "File check/compilation history")
    public ResponseEntity<?> getChecks(@RequestHeader("Authorization") String auth,
                                       @PathVariable String id,
                                       @RequestParam(value = "file", required = false) String file,
                                       @RequestParam(value = "limit", required = false, defaultValue = "50") int limit) {
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
        String file = str(body, "file");
        if (file.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "File is required."));
        }
        Map<String, Object> check = new java.util.HashMap<>();
        check.put("id", java.util.UUID.randomUUID().toString());
        check.put("file", file);
        check.put("date", java.time.Instant.now().toString());
        check.put("author", jwt.email(claims));
        Object diags = body == null ? null : body.get("diagnostics");
        if (diags instanceof List) {
            check.put("diagnostics", diags);
        } else {
            check.put("diagnostics", List.of());
        }
        String contentHash = str(body, "contentHash");
        if (!contentHash.isBlank()) {
            check.put("contentHash", contentHash);
        }
        if (body.containsKey("content") && body.get("content") != null) {
            check.put("content", String.valueOf(body.get("content")));
        }
        history.recordCheck(id, check);
        return ResponseEntity.ok(check);
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
        p.buildTool = str(body, "buildTool");
        if (p.buildTool.isEmpty()) p.buildTool = existing == null ? "maven" : (existing.buildTool == null || existing.buildTool.isEmpty() ? "maven" : existing.buildTool);
        if (!"gradle".equals(p.buildTool) && !"maven".equals(p.buildTool)) p.buildTool = "maven";
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
        Object aiModel = body.get("aiModel");
        if (aiModel != null && !String.valueOf(aiModel).trim().isEmpty()) {
            p.aiModel = String.valueOf(aiModel).trim();
        } else if (existing != null) {
            p.aiModel = existing.aiModel;
        }
        Object aiCustomModels = body.get("aiCustomModels");
        if (aiCustomModels instanceof List) {
            p.aiCustomModels = new ArrayList<>();
            for (Object m : (List<?>) aiCustomModels) {
                if (m instanceof Map) {
                    p.aiCustomModels.add(new java.util.HashMap<>((Map<String, Object>) m));
                }
            }
        } else if (existing != null && existing.aiCustomModels != null) {
            p.aiCustomModels = existing.aiCustomModels;
        }
        Object aiHiddenModels = body.get("aiHiddenModels");
        if (aiHiddenModels instanceof List) {
            p.aiHiddenModels = new ArrayList<>();
            for (Object m : (List<?>) aiHiddenModels) {
                if (m != null && !String.valueOf(m).trim().isEmpty()) {
                    p.aiHiddenModels.add(String.valueOf(m).trim());
                }
            }
        } else if (existing != null && existing.aiHiddenModels != null) {
            p.aiHiddenModels = existing.aiHiddenModels;
        }
        Object aiHiddenDefaultsSeeded = body.get("aiHiddenDefaultsSeeded");
        if (aiHiddenDefaultsSeeded instanceof Boolean) {
            p.aiHiddenDefaultsSeeded = (Boolean) aiHiddenDefaultsSeeded;
        } else if (existing != null) {
            p.aiHiddenDefaultsSeeded = existing.aiHiddenDefaultsSeeded;
        }
        if (body.get("inviteToken") != null) p.inviteToken = body.get("inviteToken").toString();
        if (body.get("inviteRole") != null) p.inviteRole = body.get("inviteRole").toString();
        return p;
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

    private String str(Map<String, Object> body, String key) {
        Object v = body.get(key);
        return v == null ? "" : v.toString();
    }

    private String strMap(Map<?, ?> m, String key) {
        Object v = m.get(key);
        return v == null ? "" : v.toString();
    }
}
