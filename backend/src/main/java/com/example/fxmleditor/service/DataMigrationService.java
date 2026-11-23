package com.example.fxmleditor.service;

import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.stream.Stream;

@Service
public class DataMigrationService {
    private final MinioStorageService storage;
    private final Path dataDir;

    public DataMigrationService(MinioStorageService storage, @Value("${app.data-dir:/data}") String dataDir) {
        this.storage = storage;
        this.dataDir = Paths.get(dataDir);
    }

    @PostConstruct
    public void migrate() {
        migrateFile(dataDir.resolve("users.json"), "users/users.json");
        migrateDir(dataDir.resolve("projects"), "projects/");
        migrateDir(dataDir.resolve("history"), "history/");
        migrateDir(dataDir.resolve("workspaces"), "workspaces/");
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