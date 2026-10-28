package com.example.fxmleditor.controller;

import com.example.fxmleditor.model.UserRecord;
import com.example.fxmleditor.security.JwtService;
import com.example.fxmleditor.service.UserStore;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api")
@Tag(name = "Auth")
public class AuthController {
    private final UserStore userStore;
    private final JwtService jwt;

    public AuthController(UserStore userStore, JwtService jwt) {
        this.userStore = userStore;
        this.jwt = jwt;
    }

    @PostMapping("/auth/register")
    @Operation(summary = "Register a new account")
    public ResponseEntity<?> register(@RequestBody Map<String, Object> body) {
        String email = str(body, "email").trim();
        String password = str(body, "password");
        if (!email.matches("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")) {
            return ResponseEntity.badRequest().body(Map.of("error", "Enter a valid email address."));
        }
        if (password.length() < 6) {
            return ResponseEntity.badRequest().body(Map.of("error", "Password must be at least 6 characters."));
        }
        try {
            UserRecord user = userStore.createUser(email, password);
            String token = jwt.issue(user.id, user.email);
            return ResponseEntity.ok(Map.of("email", user.email, "token", token, "id", user.id));
        } catch (UserStore.EmailTakenException e) {
            return ResponseEntity.status(409).body(Map.of("error", "This email is already registered."));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    @PostMapping("/auth/login")
    @Operation(summary = "Log in")
    public ResponseEntity<?> login(@RequestBody Map<String, Object> body) {
        String email = str(body, "email").trim();
        String password = str(body, "password");
        UserRecord user = userStore.findByEmail(email);
        if (user == null) return ResponseEntity.status(401).body(Map.of("error", "Invalid email or password."));
        if (!com.example.fxmleditor.security.Security.verifyPassword(password, user.salt, user.hash)) {
            return ResponseEntity.status(401).body(Map.of("error", "Invalid email or password."));
        }
        String token = jwt.issue(user.id, user.email);
        return ResponseEntity.ok(Map.of("email", user.email, "token", token, "id", user.id));
    }

    @GetMapping("/me")
    @Operation(summary = "Current profile")
    public ResponseEntity<?> me(@RequestHeader("Authorization") String auth) {
        String token = bearer(auth);
        var claims = jwt.verify(token);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        UserRecord user = userStore.findById(jwt.userId(claims));
        if (user == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        return ResponseEntity.ok(Map.of("email", user.email, "id", user.id, "avatar", user.avatar == null ? "" : user.avatar));
    }

    @PatchMapping("/me")
    @Operation(summary = "Update email")
    public ResponseEntity<?> updateEmail(@RequestHeader("Authorization") String auth, @RequestBody Map<String, Object> body) {
        String token = bearer(auth);
        var claims = jwt.verify(token);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        String email = str(body, "email");
        try {
            UserRecord user = userStore.updateEmail(jwt.userId(claims), email);
            String newToken = jwt.issue(user.id, user.email);
            return ResponseEntity.ok(Map.of("email", user.email, "token", newToken, "id", user.id));
        } catch (UserStore.EmailTakenException e) {
            return ResponseEntity.badRequest().body(Map.of("error", "This email is already registered."));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    @PostMapping("/me/password")
    @Operation(summary = "Change password")
    public ResponseEntity<?> changePassword(@RequestHeader("Authorization") String auth, @RequestBody Map<String, Object> body) {
        String token = bearer(auth);
        var claims = jwt.verify(token);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        try {
            userStore.updatePassword(jwt.userId(claims), str(body, "currentPassword"), str(body, "newPassword"));
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
    @Operation(summary = "Update avatar")
    public ResponseEntity<?> updateAvatar(@RequestHeader("Authorization") String auth, @RequestBody Map<String, Object> body) {
        String token = bearer(auth);
        var claims = jwt.verify(token);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        String avatar = body.get("avatar") == null ? null : body.get("avatar").toString();
        try {
            UserRecord user = userStore.updateAvatar(jwt.userId(claims), avatar);
            return ResponseEntity.ok(Map.of("avatar", user.avatar == null ? "" : user.avatar));
        } catch (UserStore.AvatarTooLargeException e) {
            return ResponseEntity.badRequest().body(Map.of("error", "Avatar too large."));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    @GetMapping("/users")
    @Operation(summary = "List accounts")
    public ResponseEntity<?> listAccounts(@RequestHeader("Authorization") String auth) {
        String token = bearer(auth);
        var claims = jwt.verify(token);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        var accounts = userStore.listAccounts();
        return ResponseEntity.ok(Map.of("accounts", accounts.stream().map(u -> Map.of("id", u.id, "email", u.email)).toList()));
    }

    @GetMapping("/workspace")
    @Operation(summary = "Read workspace")
    public ResponseEntity<?> getWorkspace(@RequestHeader("Authorization") String auth) {
        String token = bearer(auth);
        var claims = jwt.verify(token);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        String raw = userStore.readWorkspace(jwt.userId(claims));
        if (raw == null || raw.trim().isEmpty()) {
            return ResponseEntity.ok(Map.of("projects", java.util.List.of()));
        }
        return ResponseEntity.ok(raw);
    }

    @PutMapping("/workspace")
    @Operation(summary = "Write workspace")
    public ResponseEntity<?> putWorkspace(@RequestHeader("Authorization") String auth, @RequestBody String body) {
        String token = bearer(auth);
        var claims = jwt.verify(token);
        if (claims == null) return ResponseEntity.status(401).body(Map.of("error", "Not authenticated."));
        try {
            userStore.writeWorkspace(jwt.userId(claims), body);
            return ResponseEntity.ok(Map.of("ok", true));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    private String str(Map<String, Object> body, String key) {
        Object v = body.get(key);
        return v == null ? "" : v.toString();
    }

    private String bearer(String auth) {
        if (auth == null || !auth.toLowerCase().startsWith("bearer ")) return null;
        return auth.substring(7).trim();
    }
}
