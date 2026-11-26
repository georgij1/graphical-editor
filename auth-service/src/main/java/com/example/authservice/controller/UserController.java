package com.example.authservice.controller;

import com.example.authservice.model.UserRecord;
import com.example.authservice.security.JwtService;
import com.example.authservice.service.UserStore;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api")
@Tag(name = "Users")
public class UserController {
    private final UserStore userStore;
    private final JwtService jwt;

    public UserController(UserStore userStore, JwtService jwt) {
        this.userStore = userStore;
        this.jwt = jwt;
    }

    public record TokenRequest(
            @Schema(description = "JWT token", example = "eyJhbGciOi...") String token) {}

    public record UpdateEmailRequest(
            @Schema(description = "JWT token", example = "eyJhbGciOi...") String token,
            @Schema(description = "New email", example = "user@example.com") String email) {}

    public record ChangePasswordRequest(
            @Schema(description = "JWT token", example = "eyJhbGciOi...") String token,
            @Schema(description = "Current password") String currentPassword,
            @Schema(description = "New password") String newPassword) {}

    public record UpdateAvatarRequest(
            @Schema(description = "JWT token", example = "eyJhbGciOi...") String token,
            @Schema(description = "Avatar data URL or null") String avatar) {}

    public record WorkspaceWriteRequest(
            @Schema(description = "JWT token", example = "eyJhbGciOi...") String token,
            @Schema(description = "Workspace JSON payload") Object workspace) {}

    private ResponseEntity<?> unauthorized() {
        return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
    }

    private String token(TokenRequest req) {
        return req == null || req.token() == null ? "" : req.token().trim();
    }

    private io.jsonwebtoken.Claims claims(String token) {
        if (token == null || token.isBlank()) return null;
        return jwt.verify(token);
    }

    @PostMapping("/me")
    @Operation(summary = "Current profile", security = {})
    public ResponseEntity<?> me(@RequestBody TokenRequest body) {
        var claims = claims(token(body));
        if (claims == null) return unauthorized();
        UserRecord user = userStore.findById(jwt.userId(claims));
        if (user == null) return unauthorized();
        return ResponseEntity.ok(Map.of("email", user.email, "id", user.id, "avatar", userStore.avatarUrl(user.id)));
    }

    @PatchMapping("/me")
    @Operation(summary = "Update email", security = {})
    public ResponseEntity<?> updateEmail(@RequestBody UpdateEmailRequest body) {
        var claims = claims(body == null ? "" : body.token());
        if (claims == null) return unauthorized();
        String email = body == null || body.email() == null ? "" : body.email().trim();
        try {
            UserRecord user = userStore.updateEmail(jwt.userId(claims), email);
            String newToken = jwt.issue(user.id, user.email);
            return ResponseEntity.ok(Map.of("email", user.email, "token", newToken, "id", user.id, "avatar", userStore.avatarUrl(user.id)));
        } catch (UserStore.EmailTakenException e) {
            return ResponseEntity.badRequest().body(Map.of("error", "This email is already registered."));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    @PostMapping("/me/password")
    @Operation(summary = "Change password", security = {})
    public ResponseEntity<?> changePassword(@RequestBody ChangePasswordRequest body) {
        var claims = claims(body == null ? "" : body.token());
        if (claims == null) return unauthorized();
        try {
            String current = body == null || body.currentPassword() == null ? "" : body.currentPassword();
            String next = body == null || body.newPassword() == null ? "" : body.newPassword();
            userStore.updatePassword(jwt.userId(claims), current, next);
            return ResponseEntity.ok(Map.of("ok", true));
        } catch (UserStore.WrongPasswordException e) {
            return ResponseEntity.badRequest().body(Map.of("error", "Current password is incorrect."));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    @PutMapping("/me/avatar")
    @Operation(summary = "Update avatar", security = {})
    public ResponseEntity<?> updateAvatar(@RequestBody UpdateAvatarRequest body) {
        var claims = claims(body == null ? "" : body.token());
        if (claims == null) return unauthorized();
        String avatar = body == null ? null : body.avatar();
        try {
            UserRecord user = userStore.updateAvatar(jwt.userId(claims), avatar);
            return ResponseEntity.ok(Map.of("avatar", userStore.avatarUrl(user.id)));
        } catch (UserStore.AvatarTooLargeException e) {
            return ResponseEntity.badRequest().body(Map.of("error", "Avatar too large."));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    @GetMapping("/users/{id}/avatar")
    @Operation(summary = "Get user avatar", security = {})
    public ResponseEntity<?> getAvatar(@PathVariable String id) {
        var avatar = userStore.getAvatar(id);
        if (avatar == null) return ResponseEntity.notFound().build();
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(avatar.contentType()))
                .body(avatar.bytes());
    }

    @PostMapping("/users")
    @Operation(summary = "List accounts", security = {}) 
    public ResponseEntity<?> listAccounts(@RequestBody TokenRequest body) {
        var claims = claims(token(body));
        if (claims == null) return unauthorized();
        var accounts = userStore.listAccounts();
        return ResponseEntity.ok(Map.of("accounts", accounts.stream().map(u -> Map.of("id", u.id, "email", u.email)).toList()));
    }

    @PostMapping("/workspace/read")
    @Operation(summary = "Read workspace", security = {})
    public ResponseEntity<?> getWorkspace(@RequestBody TokenRequest body) {
        var claims = claims(token(body));
        if (claims == null) return unauthorized();
        String raw = userStore.readWorkspace(jwt.userId(claims));
        if (raw == null || raw.trim().isEmpty()) {
            return ResponseEntity.ok(Map.of("projects", java.util.List.of()));
        }
        return ResponseEntity.ok(raw);
    }

    @PutMapping("/workspace")
    @Operation(summary = "Write workspace", security = {})
    public ResponseEntity<?> putWorkspace(@RequestBody WorkspaceWriteRequest body) {
        var claims = claims(body == null ? "" : body.token());
        if (claims == null) return unauthorized();
        try {
            Object ws = body == null ? null : body.workspace();
            String json;
            if (ws == null) {
                json = "{}";
            } else if (ws instanceof String s) {
                json = s;
            } else {
                json = new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(ws);
            }
            userStore.writeWorkspace(jwt.userId(claims), json);
            return ResponseEntity.ok(Map.of("ok", true));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }
}
