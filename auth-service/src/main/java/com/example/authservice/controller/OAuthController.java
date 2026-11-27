package com.example.authservice.controller;

import com.example.authservice.service.oauth.OAuthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Map;

@RestController
@RequestMapping("/api/auth/oauth")
@Tag(name = "Auth")
public class OAuthController {
    private final OAuthService oauth;
    private final String frontendBaseUrl;

    public OAuthController(OAuthService oauth,
                           @Value("${app.oauth.frontend-base-url:http://localhost:8080}") String frontendBaseUrl) {
        this.oauth = oauth;
        this.frontendBaseUrl = frontendBaseUrl;
    }

    public record ExchangeRequest(
            @Schema(example = "abc123", description = "One-time OAuth exchange code") String code,
            @Schema(example = "google", description = "OAuth provider id (optional)") String provider) {}
    public record StartRequest(
            @Schema(example = "google", description = "OAuth provider id: google, yandex, vk, tbank") String provider,
            @Schema(example = "http://localhost:8080/", description = "Frontend redirect URL after OAuth completes") String redirect) {}
    public record OAuthErrorResponse(@Schema(example = "Invalid OAuth state.") String error) {}

    @GetMapping("/providers")
    @Operation(summary = "List OAuth providers", security = {})
    public ResponseEntity<?> providers() {
        return ResponseEntity.ok(Map.of("providers", oauth.listProviders()));
    }

    @PostMapping("/start")
    @Operation(summary = "Start OAuth login", security = {})
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Authorization URL"),
            @ApiResponse(responseCode = "400", description = "Provider not configured",
                    content = @Content(schema = @Schema(implementation = OAuthErrorResponse.class)))
    })
    public ResponseEntity<?> start(@RequestBody StartRequest body) {
        try {
            String provider = body == null ? null : body.provider();
            String redirect = body == null ? null : body.redirect();
            String url = oauth.createAuthorizationUrl(provider, redirect);
            return ResponseEntity.ok(Map.of("url", url));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    @GetMapping("/{provider}/callback")
    @Operation(summary = "OAuth callback", security = {})
    public ResponseEntity<Void> callback(@PathVariable String provider,
                                         @RequestParam(required = false) String code,
                                         @RequestParam(required = false) String state,
                                         @RequestParam(required = false, name = "device_id") String deviceId,
                                         @RequestParam(required = false) String error,
                                         @RequestParam(required = false, name = "error_description") String errorDescription) {
        String base = frontendBaseUrl == null || frontendBaseUrl.isBlank() ? "http://localhost:8080" : frontendBaseUrl.trim();
        while (base.endsWith("/")) base = base.substring(0, base.length() - 1);
        if (error != null && !error.isBlank()) {
            String msg = errorDescription != null && !errorDescription.isBlank() ? errorDescription : error;
            return redirect(base + "/?oauth_error=" + enc(msg) + "&oauth_provider=" + enc(provider));
        }
        try {
            String redirectTo = oauth.handleCallback(provider, code, state, deviceId);
            return redirect(redirectTo);
        } catch (Exception e) {
            String msg = e.getMessage() == null ? "OAuth sign-in failed." : e.getMessage();
            return redirect(base + "/?oauth_error=" + enc(msg) + "&oauth_provider=" + enc(provider));
        }
    }

    @PostMapping("/exchange")
    @Operation(summary = "Exchange OAuth code for JWT", security = {})
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Authenticated"),
            @ApiResponse(responseCode = "400", description = "Invalid code",
                    content = @Content(schema = @Schema(implementation = OAuthErrorResponse.class)))
    })
    public ResponseEntity<?> exchange(@RequestBody ExchangeRequest body) {
        try {
            String code = body == null ? null : body.code();
            return ResponseEntity.ok(oauth.exchange(code));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", e.getMessage()));
        }
    }

    private static ResponseEntity<Void> redirect(String location) {
        return ResponseEntity.status(302).location(URI.create(location)).build();
    }

    private static String enc(String s) {
        return URLEncoder.encode(s == null ? "" : s, StandardCharsets.UTF_8);
    }
}
