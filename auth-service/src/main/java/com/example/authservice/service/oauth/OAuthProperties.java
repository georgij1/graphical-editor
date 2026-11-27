package com.example.authservice.service.oauth;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.util.EnumMap;
import java.util.Map;

@Component
@ConfigurationProperties(prefix = "app.oauth")
public class OAuthProperties {
    private String frontendBaseUrl = "http://localhost:8080";
    private ProviderConfig google = new ProviderConfig();
    private ProviderConfig yandex = new ProviderConfig();
    private ProviderConfig vk = new ProviderConfig();
    private ProviderConfig tbank = new ProviderConfig();

    public String getFrontendBaseUrl() { return frontendBaseUrl; }
    public void setFrontendBaseUrl(String frontendBaseUrl) { this.frontendBaseUrl = frontendBaseUrl; }
    public ProviderConfig getGoogle() { return google; }
    public void setGoogle(ProviderConfig google) { this.google = google; }
    public ProviderConfig getYandex() { return yandex; }
    public void setYandex(ProviderConfig yandex) { this.yandex = yandex; }
    public ProviderConfig getVk() { return vk; }
    public void setVk(ProviderConfig vk) { this.vk = vk; }
    public ProviderConfig getTbank() { return tbank; }
    public void setTbank(ProviderConfig tbank) { this.tbank = tbank; }

    public ProviderConfig get(String provider) {
        if (provider == null) return null;
        return switch (provider.toLowerCase()) {
            case "google" -> google;
            case "yandex" -> yandex;
            case "vk" -> vk;
            case "tbank", "t-bank", "tinkoff" -> tbank;
            default -> null;
        };
    }

    public Map<String, ProviderConfig> all() {
        Map<String, ProviderConfig> map = new java.util.LinkedHashMap<>();
        map.put("google", google);
        map.put("yandex", yandex);
        map.put("vk", vk);
        map.put("tbank", tbank);
        return map;
    }

    public static class ProviderConfig {
        private String clientId;
        private String clientSecret;
        private String redirectUri; // optional override; defaults to {frontendBaseUrl}/api/auth/oauth/{provider}/callback

        public String getClientId() { return clientId; }
        public void setClientId(String clientId) { this.clientId = clientId; }
        public String getClientSecret() { return clientSecret; }
        public void setClientSecret(String clientSecret) { this.clientSecret = clientSecret; }
        public String getRedirectUri() { return redirectUri; }
        public void setRedirectUri(String redirectUri) { this.redirectUri = redirectUri; }

        public boolean isEnabled() {
            return clientId != null && !clientId.isBlank() && clientSecret != null && !clientSecret.isBlank();
        }
    }
}
