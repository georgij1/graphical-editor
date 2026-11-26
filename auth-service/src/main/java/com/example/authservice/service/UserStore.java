package com.example.authservice.service;

import com.example.authservice.model.UserRecord;
import com.example.authservice.model.UserWorkspaceRecord;
import com.example.authservice.repository.UserRepository;
import com.example.authservice.repository.UserWorkspaceRepository;
import com.example.authservice.security.Security;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.UUID;

@Service
public class UserStore {
    private static final String AVATAR_PREFIX = "avatars/";
    private final UserRepository users;
    private final UserWorkspaceRepository workspaces;
    private final MinioStorageService storage;

    public UserStore(UserRepository users, UserWorkspaceRepository workspaces, MinioStorageService storage) {
        this.users = users;
        this.workspaces = workspaces;
        this.storage = storage;
    }

    public void init() throws IOException {
        // JPA schema is managed by Hibernate.
    }

    @Transactional(readOnly = true)
    public List<UserRecord> loadUsers() {
        return new ArrayList<>(users.findAll());
    }

    @Transactional
    public void saveUsers(List<UserRecord> list) throws IOException {
        users.saveAll(list);
    }

    @Transactional(readOnly = true)
    public UserRecord findByEmail(String email) {
        if (email == null) return null;
        return users.findByEmailIgnoreCase(email.trim()).orElse(null);
    }

    @Transactional(readOnly = true)
    public UserRecord findById(String id) {
        if (id == null) return null;
        return users.findById(id).orElse(null);
    }

    @Transactional(readOnly = true)
    public List<UserRecord> listAccounts() {
        List<UserRecord> all = loadUsers();
        all.sort((a, b) -> String.valueOf(a.email).compareToIgnoreCase(String.valueOf(b.email)));
        return all;
    }

    @Transactional
    public UserRecord createUser(String email, String password) throws Exception {
        String normalized = email.trim().toLowerCase();
        if (users.existsByEmailIgnoreCase(normalized)) {
            throw new EmailTakenException();
        }
        String salt = Security.generateSalt();
        UserRecord record = new UserRecord(
                String.valueOf(System.currentTimeMillis()) + "_" + UUID.randomUUID().toString().substring(0, 8),
                normalized,
                salt,
                Security.hashPassword(password, salt),
                Instant.now());
        try {
            return users.save(record);
        } catch (org.springframework.dao.DataIntegrityViolationException e) {
            throw new EmailTakenException();
        }
    }

    @Transactional
    public UserRecord updateEmail(String userId, String email) throws Exception {
        String normalized = email.trim().toLowerCase();
        UserRecord target = users.findById(userId).orElseThrow(() -> new IllegalStateException("Unknown user " + userId));
        var existing = users.findByEmailIgnoreCase(normalized);
        if (existing.isPresent() && !existing.get().id.equals(userId)) {
            throw new EmailTakenException();
        }
        target.email = normalized;
        try {
            return users.save(target);
        } catch (org.springframework.dao.DataIntegrityViolationException e) {
            throw new EmailTakenException();
        }
    }

    @Transactional
    public UserRecord updatePassword(String userId, String currentPassword, String newPassword) throws Exception {
        UserRecord target = users.findById(userId).orElseThrow(() -> new IllegalStateException("Unknown user " + userId));
        if (!Security.verifyPassword(currentPassword, target.salt, target.hash)) {
            throw new WrongPasswordException();
        }
        String salt = Security.generateSalt();
        target.salt = salt;
        target.hash = Security.hashPassword(newPassword, salt);
        return users.save(target);
    }

    @Transactional
    public UserRecord updateAvatar(String userId, String avatar) throws Exception {
        UserRecord target = users.findById(userId).orElseThrow(() -> new IllegalStateException("Unknown user " + userId));
        if (avatar == null || avatar.isBlank()) {
            deleteAvatarObject(target);
            target.avatar = null;
            return users.save(target);
        }
        String dataUrl = avatar.trim();
        if (dataUrl.startsWith("minio:") || dataUrl.startsWith("/api/users/")) {
            // already a stored reference
            target.avatar = dataUrl;
            return users.save(target);
        }
        if (dataUrl.length() > 600 * 1024) {
            throw new AvatarTooLargeException();
        }
        byte[] bytes;
        String contentType = "image/png";
        if (dataUrl.startsWith("data:")) {
            int comma = dataUrl.indexOf(',');
            if (comma <= 0) throw new IllegalArgumentException("Invalid avatar data.");
            String meta = dataUrl.substring(5, comma);
            if (meta.contains(";")) meta = meta.substring(0, meta.indexOf(';'));
            if (!meta.isBlank()) contentType = meta;
            String b64 = dataUrl.substring(comma + 1);
            bytes = Base64.getDecoder().decode(b64);
        } else {
            bytes = Base64.getDecoder().decode(dataUrl);
        }
        if (bytes.length > 400 * 1024) {
            throw new AvatarTooLargeException();
        }
        String key = AVATAR_PREFIX + userId;
        storage.put(key, bytes, contentType);
        target.avatar = "minio:" + key;
        return users.save(target);
    }

    public AvatarData getAvatar(String userId) {
        UserRecord user = findById(userId);
        if (user == null || user.avatar == null || user.avatar.isBlank()) return null;
        String avatar = user.avatar;
        if (avatar.startsWith("minio:")) {
            String key = avatar.substring("minio:".length());
            byte[] data = storage.get(key);
            if (data == null) return null;
            String ct = guessContentType(key, data);
            return new AvatarData(data, ct);
        }
        // legacy data URL stored in DB
        if (avatar.startsWith("data:")) {
            int comma = avatar.indexOf(',');
            if (comma > 0) {
                String meta = avatar.substring(5, comma);
                if (meta.contains(";")) meta = meta.substring(0, meta.indexOf(';'));
                String ct = meta.isBlank() ? "image/png" : meta;
                try {
                    byte[] data = Base64.getDecoder().decode(avatar.substring(comma + 1));
                    return new AvatarData(data, ct);
                } catch (Exception ignored) {
                }
            }
        }
        return null;
    }

    public String avatarUrl(String userId) {
        UserRecord user = findById(userId);
        if (user == null || user.avatar == null || user.avatar.isBlank()) return "";
        return "/api/users/" + userId + "/avatar";
    }

    private void deleteAvatarObject(UserRecord user) {
        if (user == null || user.avatar == null) return;
        if (user.avatar.startsWith("minio:")) {
            storage.delete(user.avatar.substring("minio:".length()));
        }
    }

    private static String guessContentType(String key, byte[] data) {
        if (data != null && data.length > 3) {
            if ((data[0] & 0xFF) == 0x89 && data[1] == 0x50) return "image/png";
            if ((data[0] & 0xFF) == 0xFF && (data[1] & 0xFF) == 0xD8) return "image/jpeg";
            if (data[0] == 0x47 && data[1] == 0x49) return "image/gif";
            if (data[0] == 0x52 && data[1] == 0x49) return "image/webp";
        }
        return "application/octet-stream";
    }

    @Transactional(readOnly = true)
    public String readWorkspace(String userId) {
        return workspaces.findById(userId).map(r -> r.data).orElse(null);
    }

    @Transactional
    public void writeWorkspace(String userId, String json) throws IOException {
        UserWorkspaceRecord rec = workspaces.findById(userId).orElse(new UserWorkspaceRecord(userId, json, Instant.now()));
        rec.data = json;
        rec.updatedAt = Instant.now();
        workspaces.save(rec);
    }

    public record AvatarData(byte[] bytes, String contentType) {}

    public static class EmailTakenException extends Exception {}
    public static class WrongPasswordException extends Exception {}
    public static class AvatarTooLargeException extends Exception {}
}
