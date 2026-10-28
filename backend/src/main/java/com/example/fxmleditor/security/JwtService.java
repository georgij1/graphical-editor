package com.example.fxmleditor.security;

import io.jsonwebtoken.Claims;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.Map;

@Service
public class JwtService {
    @Value("${app.jwt-secret}")
    private String secret;

    @Value("${app.jwt-expiration-hours:240}")
    private long expirationHours;

    public String issue(String userId, String email) {
        return Security.signJwt(Map.of("sub", userId, "email", email), secret, expirationHours * 3600_000L);
    }

    public Claims verify(String token) {
        return Security.verifyJwt(token, secret);
    }

    public String userId(Claims c) {
        return c == null ? null : (String) c.get("sub");
    }

    public String email(Claims c) {
        return c == null ? null : (String) c.get("email");
    }
}
