package com.example.authservice.service.oauth;

import com.example.authservice.model.UserRecord;
import com.example.authservice.security.JwtService;
import com.example.authservice.service.UserStore;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class OAuthService {
    private static final Logger log = LoggerFactory.getLogger(OAuthService.class);
    private static final Duration STATE_TTL = Duration.ofMinutes(10);
    private static final Duration EXCHANGE_TTL = Duration.ofMinutes(5);

    private final OAuthProperties props;
    private final UserStore userStore;
    private final JwtService jwt;
    private final ObjectMapper json;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    private final SecureRandom random = new SecureRandom();
    private final ConcurrentHashMap<String, PendingState> states = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, ExchangeCode> codes = new ConcurrentHashMap<>();

    public OAuthService(OAuthProperties props, UserStore userStore, JwtService jwt, ObjectMapper json) {
        this.props = props;
        this.userStore = userStore;
        this.jwt = jwt;
        this.json = json;
    }

    public Map<String, Object> listProviders() {
        Map<String, Object> out = new LinkedHashMap<>();
        props.all().forEach((name, cfg) -> {
            Map<String, Object> p = new LinkedHashMap<>();
            p.put("enabled", cfg.isEnabled());
            p.put("name", displayName(name));
            out.put(name, p);
        });
        return out;
    }

    public String createAuthorizationUrl(String provider, String frontendRedirect) {
        cleanup();
        String p = normalize(provider);
        OAuthProperties.ProviderConfig cfg = props.get(p);
        if (cfg == null || !cfg.isEnabled()) throw new IllegalArgumentException("Provider is not configured: " + provider);
        String state = randomToken(32);
        String verifier = randomToken(48);
        String challenge = codeChallenge(verifier);
        String redirectUri = resolveRedirectUri(p, cfg);
        String fr = sanitizeFrontendRedirect(frontendRedirect);
        states.put(state, new PendingState(p, fr, verifier, Instant.now().plus(STATE_TTL)));

        return switch (p) {
            case "google" -> "https://accounts.google.com/o/oauth2/v2/auth?" + form(Map.of(
                    "client_id", cfg.getClientId(),
                    "redirect_uri", redirectUri,
                    "response_type", "code",
                    "scope", "openid email profile",
                    "state", state,
                    "access_type", "online",
                    "prompt", "select_account"
            ));
            case "yandex" -> "https://oauth.yandex.ru/authorize?" + form(Map.of(
                    "client_id", cfg.getClientId(),
                    "redirect_uri", redirectUri,
                    "response_type", "code",
                    "scope", "login:email login:info login:avatar",
                    "state", state,
                    "force_confirm", "yes"
            ));
            case "vk" -> "https://id.vk.com/authorize?" + form(Map.of(
                    "client_id", cfg.getClientId(),
                    "redirect_uri", redirectUri,
                    "response_type", "code",
                    "state", state,
                    "code_challenge", challenge,
                    "code_challenge_method", "S256",
                    "scope", "email"
            ));
            case "tbank" -> "https://id.tbank.ru/auth/authorize?" + form(Map.of(
                    "client_id", cfg.getClientId(),
                    "redirect_uri", redirectUri,
                    "response_type", "code",
                    "scope", "openid profile email",
                    "state", state
            ));
            default -> throw new IllegalArgumentException("Unsupported provider: " + provider);
        };
    }

    public String handleCallback(String provider, String code, String state, String deviceId) {
        cleanup();
        String p = normalize(provider);
        PendingState pending = state == null ? null : states.remove(state);
        if (pending == null || pending.expiresAt.isBefore(Instant.now()) || !pending.provider.equals(p)) {
            throw new IllegalArgumentException("Invalid or expired OAuth state.");
        }
        if (code == null || code.isBlank()) {
            throw new IllegalArgumentException("Missing OAuth code.");
        }
        OAuthProperties.ProviderConfig cfg = props.get(p);
        if (cfg == null || !cfg.isEnabled()) throw new IllegalArgumentException("Provider is not configured: " + provider);

        OAuthProfile profile = switch (p) {
            case "google" -> handleGoogle(cfg, code, resolveRedirectUri(p, cfg));
            case "yandex" -> handleYandex(cfg, code, resolveRedirectUri(p, cfg));
            case "vk" -> handleVk(cfg, code, resolveRedirectUri(p, cfg), pending.verifier, deviceId);
            case "tbank" -> handleTbank(cfg, code, resolveRedirectUri(p, cfg));
            default -> throw new IllegalArgumentException("Unsupported provider: " + provider);
        };

        try {
            UserRecord user = userStore.findOrCreateOAuthUser(p, profile.providerUserId(), profile.email());
            String exchange = randomToken(32);
            codes.put(exchange, new ExchangeCode(user.id, user.email, Instant.now().plus(EXCHANGE_TTL)));
            String base = pending.frontendRedirect != null ? pending.frontendRedirect : props.getFrontendBaseUrl();
            return appendQuery(base, Map.of("oauth_code", exchange, "oauth_provider", p));
        } catch (Exception e) {
            log.error("OAuth user creation failed for provider {}", p, e);
            throw new RuntimeException("Failed to sign in with " + displayName(p) + ": " + e.getMessage(), e);
        }
    }

    public Map<String, Object> exchange(String code) {
        cleanup();
        if (code == null || code.isBlank()) throw new IllegalArgumentException("Missing exchange code.");
        ExchangeCode entry = codes.remove(code.trim());
        if (entry == null || entry.expiresAt.isBefore(Instant.now())) {
            throw new IllegalArgumentException("Invalid or expired OAuth code.");
        }
        UserRecord user = userStore.findById(entry.userId);
        if (user == null) throw new IllegalArgumentException("User not found.");
        String token = jwt.issue(user.id, user.email);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("email", user.email);
        out.put("token", token);
        out.put("id", user.id);
        return out;
    }

    private OAuthProfile handleGoogle(OAuthProperties.ProviderConfig cfg, String code, String redirectUri) {
        JsonNode token = postForm("https://oauth2.googleapis.com/token", Map.of(
                "client_id", cfg.getClientId(),
                "client_secret", cfg.getClientSecret(),
                "code", code,
                "grant_type", "authorization_code",
                "redirect_uri", redirectUri
        ));
        String accessToken = text(token, "access_token");
        if (accessToken == null) throw new RuntimeException("Google token exchange failed: " + token);
        JsonNode info = getJson("https://openidconnect.googleapis.com/v1/userinfo", accessToken);
        String sub = text(info, "sub");
        String email = text(info, "email");
        if (sub == null) throw new RuntimeException("Google profile missing sub: " + info);
        return new OAuthProfile(sub, email);
    }

    private OAuthProfile handleYandex(OAuthProperties.ProviderConfig cfg, String code, String redirectUri) {
        JsonNode token = postForm("https://oauth.yandex.ru/token", Map.of(
                "client_id", cfg.getClientId(),
                "client_secret", cfg.getClientSecret(),
                "code", code,
                "grant_type", "authorization_code"
        ));
        String accessToken = text(token, "access_token");
        if (accessToken == null) throw new RuntimeException("Yandex token exchange failed: " + token);
        JsonNode info = getJson("https://login.yandex.ru/info?format=json", accessToken);
        String id = text(info, "id");
        String email = text(info, "default_email");
        if ((email == null || email.isBlank()) && info.has("emails") && info.get("emails").isArray() && info.get("emails").size() > 0) {
            email = info.get("emails").get(0).asText();
        }
        if (id == null) throw new RuntimeException("Yandex profile missing id: " + info);
        return new OAuthProfile(id, email);
    }

    private OAuthProfile handleVk(OAuthProperties.ProviderConfig cfg, String code, String redirectUri, String verifier, String deviceId) {
        Map<String, String> form = new LinkedHashMap<>();
        form.put("client_id", cfg.getClientId());
        form.put("code", code);
        form.put("redirect_uri", redirectUri);
        form.put("code_verifier", verifier);
        form.put("grant_type", "authorization_code");
        if (deviceId != null && !deviceId.isBlank()) form.put("device_id", deviceId);
        // VK ID may require client_secret depending on app type; include if present.
        if (cfg.getClientSecret() != null && !cfg.getClientSecret().isBlank()) {
            form.put("client_secret", cfg.getClientSecret());
        }
        JsonNode token = postForm("https://id.vk.com/oauth2/auth", form);
        String accessToken = text(token, "access_token");
        String userId = text(token, "user_id");
        String email = text(token, "email");
        if (accessToken == null) throw new RuntimeException("VK token exchange failed: " + token);

        // Try to fetch user info for more stable id/email.
        try {
            JsonNode info = postForm("https://id.vk.com/oauth2/user_info", Map.of(
                    "client_id", cfg.getClientId(),
                    "access_token", accessToken
            ));
            JsonNode user = info.has("user") ? info.get("user") : info;
            String uid = text(user, "user_id");
            if (uid == null) uid = text(user, "id");
            if (uid != null) userId = uid;
            String mail = text(user, "email");
            if (mail != null && !mail.isBlank()) email = mail;
        } catch (Exception e) {
            log.warn("VK user_info fetch failed, using token response", e);
        }
        if (userId == null) throw new RuntimeException("VK profile missing user_id: " + token);
        return new OAuthProfile(userId, email);
    }

    private OAuthProfile handleTbank(OAuthProperties.ProviderConfig cfg, String code, String redirectUri) {
        JsonNode token = postForm("https://id.tbank.ru/auth/token", Map.of(
                "client_id", cfg.getClientId(),
                "client_secret", cfg.getClientSecret(),
                "code", code,
                "grant_type", "authorization_code",
                "redirect_uri", redirectUri
        ));
        String accessToken = text(token, "access_token");
        if (accessToken == null) throw new RuntimeException("T-Bank token exchange failed: " + token);
        JsonNode info = getJson("https://id.tbank.ru/userinfo/userinfo", accessToken);
        String sub = text(info, "sub");
        if (sub == null) sub = text(info, "id");
        if (sub == null) sub = text(info, "userId");
        String email = text(info, "email");
        if (sub == null) throw new RuntimeException("T-Bank profile missing subject: " + info);
        return new OAuthProfile(sub, email);
    }

    private JsonNode postForm(String url, Map<String, String> form) {
        try {
            HttpRequest req = HttpRequest.newBuilder(URI.create(url))
                    .timeout(Duration.ofSeconds(15))
                    .header("Content-Type", "application/x-www-form-urlencoded")
                    .header("Accept", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(form(form)))
                    .build();
            HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (resp.statusCode() >= 200 && resp.statusCode() < 300) {
                return json.readTree(resp.body());
            }
            log.warn("OAuth POST {} returned {}: {}", url, resp.statusCode(), resp.body());
            try { return json.readTree(resp.body()); } catch (Exception ignored) {}
            throw new RuntimeException("HTTP " + resp.statusCode() + " from " + url);
        } catch (RuntimeException e) {
            throw e;
        } catch (Exception e) {
            throw new RuntimeException("OAuth request failed: " + url, e);
        }
    }

    private JsonNode getJson(String url, String bearer) {
        try {
            HttpRequest req = HttpRequest.newBuilder(URI.create(url))
                    .timeout(Duration.ofSeconds(15))
                    .header("Accept", "application/json")
                    .header("Authorization", "Bearer " + bearer)
                    .GET()
                    .build();
            HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (resp.statusCode() >= 200 && resp.statusCode() < 300) {
                return json.readTree(resp.body());
            }
            log.warn("OAuth GET {} returned {}: {}", url, resp.statusCode(), resp.body());
            throw new RuntimeException("HTTP " + resp.statusCode() + " from " + url);
        } catch (RuntimeException e) {
            throw e;
        } catch (Exception e) {
            throw new RuntimeException("OAuth request failed: " + url, e);
        }
    }

    private String resolveRedirectUri(String provider, OAuthProperties.ProviderConfig cfg) {
        if (cfg.getRedirectUri() != null && !cfg.getRedirectUri().isBlank()) return cfg.getRedirectUri().trim();
        String base = props.getFrontendBaseUrl();
        if (base == null || base.isBlank()) base = "http://localhost:8080";
        while (base.endsWith("/")) base = base.substring(0, base.length() - 1);
        return base + "/api/auth/oauth/" + provider + "/callback";
    }

    private String sanitizeFrontendRedirect(String redirect) {
        String base = props.getFrontendBaseUrl();
        if (base == null || base.isBlank()) base = "http://localhost:8080";
        String normalizedBase = base.endsWith("/") ? base.substring(0, base.length() - 1) : base;
        if (redirect == null || redirect.isBlank()) return normalizedBase + "/";
        String r = redirect.trim();
        // only allow redirects to configured frontend base
        if (r.startsWith(normalizedBase)) return r;
        if (r.startsWith("/")) return normalizedBase + r;
        return normalizedBase + "/";
    }

    private static String normalize(String provider) {
        if (provider == null) return "";
        String p = provider.trim().toLowerCase();
        if (p.equals("t-bank") || p.equals("tinkoff")) return "tbank";
        return p;
    }

    private static String displayName(String provider) {
        return switch (normalize(provider)) {
            case "google" -> "Google";
            case "yandex" -> "Yandex";
            case "vk" -> "VK";
            case "tbank" -> "T-Bank";
            default -> provider;
        };
    }

    private String randomToken(int bytes) {
        byte[] b = new byte[bytes];
        random.nextBytes(b);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(b);
    }

    private String codeChallenge(String verifier) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] digest = md.digest(verifier.getBytes(StandardCharsets.US_ASCII));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(digest);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private static String form(Map<String, String> params) {
        StringBuilder sb = new StringBuilder();
        for (var e : params.entrySet()) {
            if (e.getValue() == null) continue;
            if (sb.length() > 0) sb.append('&');
            sb.append(URLEncoder.encode(e.getKey(), StandardCharsets.UTF_8));
            sb.append('=');
            sb.append(URLEncoder.encode(e.getValue(), StandardCharsets.UTF_8));
        }
        return sb.toString();
    }

    private static String appendQuery(String base, Map<String, String> params) {
        String sep = base.contains("?") ? "&" : "?";
        return base + sep + form(params);
    }

    private static String text(JsonNode node, String field) {
        if (node == null || !node.has(field) || node.get(field).isNull()) return null;
        String v = node.get(field).asText();
        return v == null || v.isBlank() ? null : v;
    }

    private void cleanup() {
        Instant now = Instant.now();
        states.entrySet().removeIf(e -> e.getValue().expiresAt.isBefore(now));
        codes.entrySet().removeIf(e -> e.getValue().expiresAt.isBefore(now));
    }

    private record PendingState(String provider, String frontendRedirect, String verifier, Instant expiresAt) {}
    private record ExchangeCode(String userId, String email, Instant expiresAt) {}
    private record OAuthProfile(String providerUserId, String email) {}
}
