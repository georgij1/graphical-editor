package com.example.projectsservice.service;

import com.example.projectsservice.model.ProjectHistoryRecord;
import com.example.projectsservice.model.ProjectRecord;
import com.example.projectsservice.model.SharedProject;
import com.example.projectsservice.repository.ProjectHistoryRepository;
import com.example.projectsservice.repository.ProjectRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.nio.file.Path;
import java.nio.file.Paths;

@Service
public class DataMigrationService {
    private final MinioStorageService storage;
    private final ProjectHistoryRepository history;
    private final ProjectRepository projects;
    private final ProjectFileStorageService projectFiles;
    private final Path dataDir;
    private final ObjectMapper mapper = new ObjectMapper()
            .registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule())
            .disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    public DataMigrationService(MinioStorageService storage, ProjectHistoryRepository history, ProjectRepository projects, ProjectFileStorageService projectFiles, @Value("${app.data-dir:/data}") String dataDir) {
        this.storage = storage;
        this.history = history;
        this.projects = projects;
        this.projectFiles = projectFiles;
        this.dataDir = Paths.get(dataDir);
    }

    @PostConstruct
    public void migrate() {
        migrateHistoryToPostgres();
        migrateProjectsToPostgres();
        syncProjectsToMinioFiles();
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

    private void syncProjectsToMinioFiles() {
        try {
            for (ProjectRecord r : projects.findAll()) {
                if (r == null || r.data == null) continue;
                try {
                    SharedProject p = mapper.readValue(r.data, SharedProject.class);
                    projectFiles.syncProject(p);
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
}
