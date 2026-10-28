package com.example.fxmleditor.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.locks.ReentrantLock;

@Service
public class HistoryStore {
    private final Path dataDir;
    private final ObjectMapper mapper = new ObjectMapper().registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule()).disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
    private final ReentrantLock lock = new ReentrantLock();

    public HistoryStore(@Value("${app.data-dir}") String dataDir) {
        this.dataDir = Paths.get(dataDir);
    }

    public void init() throws IOException {
        Files.createDirectories(dataDir.resolve("history"));
    }

    private Path file(String projectId) {
        return dataDir.resolve("history").resolve(projectId + ".json");
    }

    public Map<String, Object> get(String projectId) {
        lock.lock();
        try {
            Path f = file(projectId);
            if (!Files.exists(f)) return Map.of("projectId", projectId, "versions", List.of(), "builds", List.of());
            try {
                return mapper.readValue(f.toFile(), Map.class);
            } catch (Exception e) {
                return Map.of("projectId", projectId, "versions", List.of(), "builds", List.of());
            }
        } finally {
            lock.unlock();
        }
    }

    public Map<String, Object> createVersion(String projectId, String summary, int revision, int scenesCount, int filesCount, List<String> sceneNames) {
        lock.lock();
        try {
            Map<String, Object> data = get(projectId);
            List<Object> versions = new ArrayList<>((List<Object>) data.getOrDefault("versions", new ArrayList<>()));
            Map<String, Object> v = new java.util.HashMap<>();
            v.put("revision", revision);
            v.put("date", java.time.Instant.now().toString());
            v.put("summary", summary);
            v.put("scenesCount", scenesCount);
            v.put("filesCount", filesCount);
            v.put("sceneNames", sceneNames == null ? List.of() : sceneNames);
            versions.add(0, v);
            data.put("versions", versions);
            save(projectId, data);
            return data;
        } finally {
            lock.unlock();
        }
    }

    public Map<String, Object> recordBuild(String projectId, Map<String, Object> build) {
        lock.lock();
        try {
            Map<String, Object> data = get(projectId);
            List<Object> builds = new ArrayList<>((List<Object>) data.getOrDefault("builds", new ArrayList<>()));
            builds.add(0, build);
            data.put("builds", builds);
            save(projectId, data);
            return data;
        } finally {
            lock.unlock();
        }
    }

    private void save(String projectId, Map<String, Object> data) {
        try {
            Files.createDirectories(dataDir.resolve("history"));
            new ObjectMapper().registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule()).disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS).writeValue(file(projectId).toFile(), data);
        } catch (Exception ignored) {
        }
    }
}
