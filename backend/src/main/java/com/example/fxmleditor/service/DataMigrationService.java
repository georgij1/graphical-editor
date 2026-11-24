package com.example.fxmleditor.service;

import com.example.fxmleditor.model.ProjectHistoryRecord;
import com.example.fxmleditor.model.ProjectRecord;
import com.example.fxmleditor.model.SharedProject;
import com.example.fxmleditor.model.UserRecord;
import com.example.fxmleditor.model.UserWorkspaceRecord;
import com.example.fxmleditor.repository.ProjectHistoryRepository;
import com.example.fxmleditor.repository.ProjectRepository;
import com.example.fxmleditor.repository.UserRepository;
import com.example.fxmleditor.repository.UserWorkspaceRepository;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

@Service
public class DataMigrationService {
    private final MinioStorageService storage;
    private final UserRepository users;
    private final ProjectHistoryRepository history;
    private final ProjectRepository projects;
    private final UserWorkspaceRepository workspaces;
    private final Path dataDir;
    private final ObjectMapper mapper = new ObjectMapper()
            .registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule())
            .disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    public DataMigrationService(MinioStorageService storage, UserRepository users, ProjectHistoryRepository history, ProjectRepository projects, UserWorkspaceRepository workspaces, @Value("${app.data-dir:/data}") String dataDir) {
        this.storage = storage;
        this.users = users;
        this.history = history;
        this.projects = projects;
        this.workspaces = workspaces;
        this.dataDir = Paths.get(dataDir);
    }

    @PostConstruct
    public void migrate() {
        migrateUsersToPostgres();
        migrateHistoryToPostgres();
        migrateProjectsToPostgres();
        migrateWorkspacesToPostgres();
    }

    private void migrateWorkspacesToPostgres() {
        try {
            for (String key : storage.list("workspaces/")) {
                if (!key.endsWith(".json")) continue;
                String userId = key.substring("workspaces/".length(), key.length() - ".json".length());
                if (userId.isBlank() || workspaces.existsById(userId)) continue;
                try {
                    byte[] data = storage.get(key);
                    if (data == null) continue;
                    String json = new String(data, java.nio.charset.StandardCharsets.UTF_8);
                    workspaces.save(new UserWorkspaceRecord(userId, json, java.time.Instant.now()));
                } catch (Exception ignored) {
                }
            }
        } catch (Exception ignored) {
        }
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

}