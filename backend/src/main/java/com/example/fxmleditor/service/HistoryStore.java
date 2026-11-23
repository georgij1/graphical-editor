package com.example.fxmleditor.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.locks.ReentrantLock;

@Service
public class HistoryStore {
    private static final String PREFIX = "history/";
    private final MinioStorageService storage;
    private final ObjectMapper mapper = new ObjectMapper()
            .registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule())
            .disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
    private final ReentrantLock lock = new ReentrantLock();

    public HistoryStore(MinioStorageService storage) {
        this.storage = storage;
    }

    private String key(String projectId) {
        return PREFIX + projectId + ".json";
    }

    public Map<String, Object> get(String projectId) {
        lock.lock();
        try {
            byte[] data = storage.get(key(projectId));
            if (data == null) {
                return defaultData(projectId);
            }
            try {
                Map<String, Object> parsed = mapper.readValue(data, Map.class);
                if (parsed == null) parsed = new java.util.HashMap<>();
                parsed.putIfAbsent("projectId", projectId);
                parsed.putIfAbsent("versions", List.of());
                parsed.putIfAbsent("builds", List.of());
                parsed.putIfAbsent("checks", List.of());
                return parsed;
            } catch (Exception e) {
                return defaultData(projectId);
            }
        } finally {
            lock.unlock();
        }
    }

    private Map<String, Object> defaultData(String projectId) {
        return new java.util.HashMap<>(Map.of(
                "projectId", projectId,
                "versions", List.of(),
                "builds", List.of(),
                "checks", List.of()));
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
            byte[] bytes = mapper.writeValueAsBytes(data);
            storage.put(key(projectId), bytes, "application/json");
        } catch (Exception ignored) {
        }
    }
}