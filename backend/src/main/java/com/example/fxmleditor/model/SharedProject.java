package com.example.fxmleditor.model;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@JsonInclude(JsonInclude.Include.NON_NULL)
public class SharedProject {
    public String id;
    public String name;
    @com.fasterxml.jackson.annotation.JsonProperty("package")
    public String packageName;
    public String mainClass = "MainApp";
    public boolean shared = true;
    public String description = "";
    public String ownerId = "";
    public String ownerEmail = "";
    public int revision = 1;
    public String inviteToken;
    public String inviteRole = "editor";
    public List<ProjectMember> members = new ArrayList<>();
    public List<Map<String, Object>> scenes = new ArrayList<>();
    public Map<String, String> sources = new java.util.HashMap<>();
    public Instant updatedAt = Instant.now();

    public boolean isOwner(String userId, String email) {
        return ownerId != null && !ownerId.isEmpty() && ownerId.equals(userId);
    }

    public boolean canRead(String userId, String email) {
        if (ownerId != null && !ownerId.isEmpty() && ownerId.equals(userId)) return true;
        if (ownerEmail != null && !ownerEmail.isEmpty() && ownerEmail.equalsIgnoreCase(email)) return true;
        for (ProjectMember m : members) {
            if (m.email != null && m.email.equalsIgnoreCase(email)) return true;
        }
        return false;
    }

    public String createInvite(String role) {
        inviteRole = (role == null || role.isEmpty()) ? "editor" : role;
        inviteToken = java.util.Base64.getUrlEncoder().withoutPadding()
                .encodeToString(java.util.UUID.randomUUID().toString().getBytes());
        return inviteToken;
    }

    public boolean matchesInvite(String token) {
        return inviteToken != null && !inviteToken.isEmpty() && inviteToken.equals(token);
    }

    public boolean canEdit(String userId, String email) {
        if (ownerId != null && !ownerId.isEmpty() && ownerId.equals(userId)) return true;
        for (ProjectMember m : members) {
            if (m.email != null && m.email.equalsIgnoreCase(email) && "editor".equals(m.role)) return true;
        }
        return false;
    }

    public ProjectMember memberOf(String email) {
        for (ProjectMember m : members) {
            if (m.email != null && m.email.equalsIgnoreCase(email)) return m;
        }
        return null;
    }
}
