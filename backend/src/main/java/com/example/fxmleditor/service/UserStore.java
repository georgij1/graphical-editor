package com.example.fxmleditor.service;

import com.example.fxmleditor.model.UserRecord;
import com.example.fxmleditor.model.UserWorkspaceRecord;
import com.example.fxmleditor.repository.UserRepository;
import com.example.fxmleditor.repository.UserWorkspaceRepository;
import com.example.fxmleditor.security.Security;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Service
public class UserStore {
    private final UserRepository users;
    private final UserWorkspaceRepository workspaces;

    public UserStore(UserRepository users, UserWorkspaceRepository workspaces) {
        this.users = users;
        this.workspaces = workspaces;
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
        if (avatar != null && avatar.length() > 600 * 1024) {
            throw new AvatarTooLargeException();
        }
        UserRecord target = users.findById(userId).orElseThrow(() -> new IllegalStateException("Unknown user " + userId));
        target.avatar = avatar;
        return users.save(target);
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

    public static class EmailTakenException extends Exception {}
    public static class WrongPasswordException extends Exception {}
    public static class AvatarTooLargeException extends Exception {}
}