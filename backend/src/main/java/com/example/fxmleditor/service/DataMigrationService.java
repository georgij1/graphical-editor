package com.example.fxmleditor.service;

import com.example.fxmleditor.model.ProjectHistoryRecord;
import com.example.fxmleditor.model.ProjectRecord;
import com.example.fxmleditor.model.SharedProject;
import com.example.fxmleditor.model.UserRecord;
import com.example.fxmleditor.repository.ProjectHistoryRepository;
import com.example.fxmleditor.repository.ProjectRepository;
import com.example.fxmleditor.repository.UserRepository;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.stream.Stream;

@Service
public class DataMigrationService {
    private final MinioStorageService storage;
    private final UserRepository users;
    private final ProjectHistoryRepository history;
    private final ProjectRepository projects;
    private final Path dataDir;
    private final ObjectMapper mapper = new ObjectMapper()
            .registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule())
            .disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    public DataMigrationService(MinioStorageService storage, UserRepository users, ProjectHistoryRepository history, ProjectRepository projects, @Value("${app.data-dir:/data}") String dataDir) {
        this.storage = storage;
        this.users = users;
        this.history = history;
        this.projects = projects;
        this.dataDir = Paths.get(dataDir);
    }

    @PostConstruct
    public void migrate() {
        migrateUsersToPostgres();
        migrateHistoryToPostgres();
        migrateProjectsToPostgres();
        migrateFile(dataDir.resolve("users.json"), "users/users.json");
        migrateDir(dataDir.resolve("projects"), "projects/");
        migrateDir(dataDir.resolve("history"), "history/");
        migrateDir(dataDir.resolve("workspaces"), "workspaces/");
    }

    private void migrateProjectsToPostgres() {
        try {
            for (String key : storage.list("projects/")) {
                if (!key.endsWith(".json")) continue;
                String projectId = key.substring("projects/".length(), key.length() - ".json".length());
                if (projectId.isBlank() || projects.existsById(projectId)) continue;
                try {
                    byte[] data = storage.get(key);
                    if (data == null) continue;
                    String json = new String(data, java.nio.charset.StandardCharsets.UTF_8);
                    SharedProject p = mapper.readValue(json, SharedProject.class);
                    String name = p == null ? null : p.name;
                    String ownerId = p == null ? null : p.ownerId;
                    java.time.Instant updatedAt = p == null ? null : p.updatedAt;
                    projects.save(new ProjectRecord(projectId, ownerId, name, json, updatedAt));
                } catch (Exception ignored) {
                }
            }
        } catch (Exception ignored) {
        }
    }

    private void migrateHistoryToPostgres() {
        try {
            for (String key : storage.list("history/")) {
                if (!key.endsWith(".json")) continue;
                String projectId = key.substring("history/".length(), key.length() - ".json".length());
                if (projectId.isBlank() || history.existsById(projectId)) continue;
                try {
                    byte[] data = storage.get(key);
                    if (data == null) continue;
                    String json = new String(data, java.nio.charset.StandardCharsets.UTF_8);
                    history.save(new ProjectHistoryRecord(projectId, json, java.time.Instant.now()));
                } catch (Exception ignored) {
                }
            }
        } catch (Exception ignored) {
        }
    }

    private void migrateUsersToPostgres() {
        try {
            if (users.count() > 0) return;
            byte[] data = storage.get("users/users.json");
            if (data == null) {
                Path disk = dataDir.resolve("users.json");
                if (Files.exists(disk)) data = Files.readAllBytes(disk);
            }
            if (data == null) return;
            List<UserRecord> list = mapper.readValue(data, new TypeReference<List<UserRecord>>() {});
            if (list == null || list.isEmpty()) return;
            for (UserRecord u : list) {
                if (u == null || u.id == null) continue;
                try {
                    if (!users.existsById(u.id)) {
                        users.save(u);
                    }
                } catch (Exception ignored) {
                }
            }
        } catch (Exception ignored) {
        }
    }

    private void migrateFile(Path file, String key) {
        try {
            if (!Files.exists(file) || storage.get(key) != null) return;
            byte[] bytes = Files.readAllBytes(file);
            storage.put(key, bytes, "application/json");
        } catch (Exception ignored) {
        }
    }

    private void migrateDir(Path dir, String prefix) {
        try {
            if (!Files.exists(dir) || !Files.isDirectory(dir)) return;
            try (Stream<Path> stream = Files.list(dir)) {
                stream.filter(Files::isRegularFile).forEach(p -> {
                    String name = p.getFileName().toString();
                    String key = prefix + name;
                    try {
                        if (storage.get(key) != null) return;
                        byte[] bytes = Files.readAllBytes(p);
                        storage.put(key, bytes, "application/json");
                    } catch (Exception ignored) {
                    }
                });
            }
        } catch (Exception ignored) {
        }
    }
}