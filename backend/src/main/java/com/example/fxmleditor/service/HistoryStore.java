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
            if (!Files.exists(f)) {
                return new java.util.HashMap<>(Map.of(
                        "projectId", projectId,
                        "versions", List.of(),
                        "builds", List.of(),
                        "checks", List.of()));
            }
            try {
                Map<String, Object> data = mapper.readValue(f.toFile(), Map.class);
                if (data == null) data = new java.util.HashMap<>();
                data.putIfAbsent("projectId", projectId);
                data.putIfAbsent("versions", List.of());
                data.putIfAbsent("builds", List.of());
                data.putIfAbsent("checks", List.of());
                return data;
            } catch (Exception e) {
                return new java.util.HashMap<>(Map.of(
                        "projectId", projectId,
                        "versions", List.of(),
                        "builds", List.of(),
                        "checks", List.of()));
            }
        } finally {
            lock.unlock();
        }
    }

    public Map<String, Object> createVersion(String projectId, String summary, int revision, int scenesCount, int filesCount, List<String> sceneNames, String author) {
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
            if (author != null && !author.isBlank()) v.put("author", author);
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

    public Map<String, Object> recordCheck(String projectId, Map<String, Object> check) {
        lock.lock();
        try {
            Map<String, Object> data = get(projectId);
            List<Object> checks = new ArrayList<>((List<Object>) data.getOrDefault("checks", new ArrayList<>()));
            checks.add(0, check);
            if (checks.size() > 200) {
                checks = new ArrayList<>(checks.subList(0, 200));
            }
            data.put("checks", checks);
            save(projectId, data);
            return data;
        } finally {
            lock.unlock();
        }
    }

    public List<Map<String, Object>> getChecks(String projectId, String file, int limit) {
        Map<String, Object> data = get(projectId);
        List<Object> checks = (List<Object>) data.getOrDefault("checks", List.of());
        List<Map<String, Object>> result = new ArrayList<>();
        int max = limit > 0 ? limit : 50;
        for (Object c : checks) {
            if (!(c instanceof Map)) continue;
            Map<String, Object> m = (Map<String, Object>) c;
            if (file != null && !file.isBlank()) {
                Object f = m.get("file");
                String fs = f == null ? "" : f.toString();
                if (!fs.equals(file)) continue;
            }
            result.add(m);
            if (result.size() >= max) break;
        }
        return result;
    }

    private void save(String projectId, Map<String, Object> data) {
        try {
            Files.createDirectories(dataDir.resolve("history"));
            new ObjectMapper().registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule()).disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS).writeValue(file(projectId).toFile(), data);
        } catch (Exception ignored) {
        }
    }
}
