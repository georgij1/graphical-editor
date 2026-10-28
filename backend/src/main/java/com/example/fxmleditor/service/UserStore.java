package com.example.fxmleditor.service;

import com.example.fxmleditor.model.UserRecord;
import com.example.fxmleditor.security.Security;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.locks.ReentrantLock;

@Service
public class UserStore {
    private final Path dataDir;
    private final Path usersFile;
    private final Path workspacesDir;
    private final ObjectMapper mapper = new ObjectMapper().registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule()).disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
    private final ReentrantLock lock = new ReentrantLock();

    public UserStore(@Value("${app.data-dir}") String dataDir) {
        this.dataDir = Paths.get(dataDir);
        this.usersFile = this.dataDir.resolve("users.json");
        this.workspacesDir = this.dataDir.resolve("workspaces");
    }

    public void init() throws IOException {
        Files.createDirectories(dataDir);
        Files.createDirectories(workspacesDir);
    }

    public List<UserRecord> loadUsers() {
        lock.lock();
        try {
            if (!Files.exists(usersFile)) return new ArrayList<>();
            try {
                return mapper.readValue(usersFile.toFile(), new TypeReference<List<UserRecord>>() {});
            } catch (Exception e) {
                return new ArrayList<>();
            }
        } finally {
            lock.unlock();
        }
    }

    public void saveUsers(List<UserRecord> users) throws IOException {
        lock.lock();
        try {
            Files.createDirectories(dataDir);
            mapper.writeValue(usersFile.toFile(), users);
        } finally {
            lock.unlock();
        }
    }

    public UserRecord findByEmail(String email) {
        for (UserRecord u : loadUsers()) {
            if (u.email != null && u.email.equalsIgnoreCase(email.trim())) return u;
        }
        return null;
    }

    public UserRecord findById(String id) {
        for (UserRecord u : loadUsers()) {
            if (id.equals(u.id)) return u;
        }
        return null;
    }

    public List<UserRecord> listAccounts() {
        List<UserRecord> users = loadUsers();
        users.sort((a, b) -> a.email.compareTo(b.email));
        return users;
    }

    public UserRecord createUser(String email, String password) throws Exception {
        lock.lock();
        try {
            List<UserRecord> users = loadUsers();
            for (UserRecord u : users) {
                if (u.email != null && u.email.equalsIgnoreCase(email.trim())) {
                    throw new EmailTakenException();
                }
            }
            String salt = Security.generateSalt();
            UserRecord record = new UserRecord(
                    String.valueOf(System.currentTimeMillis()) + "_" + UUID.randomUUID().toString().substring(0, 8),
                    email.trim().toLowerCase(),
                    salt,
                    Security.hashPassword(password, salt),
                    Instant.now());
            users.add(record);
            saveUsers(users);
            return record;
        } finally {
            lock.unlock();
        }
    }

    public UserRecord updateEmail(String userId, String email) throws Exception {
        lock.lock();
        try {
            String normalized = email.trim().toLowerCase();
            List<UserRecord> users = loadUsers();
            UserRecord target = null;
            for (UserRecord u : users) {
                if (u.id.equals(userId)) target = u;
                else if (u.email != null && u.email.equalsIgnoreCase(normalized)) {
                    throw new EmailTakenException();
                }
            }
            if (target == null) throw new IllegalStateException("Unknown user " + userId);
            target.email = normalized;
            saveUsers(users);
            return target;
        } finally {
            lock.unlock();
        }
    }

    public UserRecord updatePassword(String userId, String currentPassword, String newPassword) throws Exception {
        lock.lock();
        try {
            List<UserRecord> users = loadUsers();
            UserRecord target = null;
            for (UserRecord u : users) {
                if (u.id.equals(userId)) target = u;
            }
            if (target == null) throw new IllegalStateException("Unknown user " + userId);
            if (!Security.verifyPassword(currentPassword, target.salt, target.hash)) {
                throw new WrongPasswordException();
            }
            String salt = Security.generateSalt();
            target.salt = salt;
            target.hash = Security.hashPassword(newPassword, salt);
            saveUsers(users);
            return target;
        } finally {
            lock.unlock();
        }
    }

    public UserRecord updateAvatar(String userId, String avatar) throws Exception {
        if (avatar != null && avatar.length() > 600 * 1024) {
            throw new AvatarTooLargeException();
        }
        lock.lock();
        try {
            List<UserRecord> users = loadUsers();
            UserRecord target = null;
            for (UserRecord u : users) {
                if (u.id.equals(userId)) target = u;
            }
            if (target == null) throw new IllegalStateException("Unknown user " + userId);
            target.avatar = avatar;
            saveUsers(users);
            return target;
        } finally {
            lock.unlock();
        }
    }

    public String readWorkspace(String userId) {
        lock.lock();
        try {
            Path file = workspacesDir.resolve(userId + ".json");
            if (!Files.exists(file)) return null;
            try {
                return Files.readString(file);
            } catch (Exception e) {
                return null;
            }
        } finally {
            lock.unlock();
        }
    }

    public void writeWorkspace(String userId, String json) throws IOException {
        lock.lock();
        try {
            Files.createDirectories(workspacesDir);
            Files.writeString(workspacesDir.resolve(userId + ".json"), json);
        } finally {
            lock.unlock();
        }
    }

    public static class EmailTakenException extends Exception {}
    public static class WrongPasswordException extends Exception {}
    public static class AvatarTooLargeException extends Exception {}
}
