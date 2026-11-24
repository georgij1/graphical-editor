package com.example.fxmleditor.controller;

import com.example.fxmleditor.model.UserRecord;
import com.example.fxmleditor.security.JwtService;
import com.example.fxmleditor.service.UserStore;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
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

    private String str(Map<String, Object> body, String key) {
        Object v = body.get(key);
        return v == null ? "" : v.toString();
    }
}
