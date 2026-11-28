package com.example.analyzerservice.service;

import com.example.analyzerservice.model.ProjectHistoryRecord;
import com.example.analyzerservice.repository.ProjectHistoryRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Service
public class HistoryStore {
    private final ProjectHistoryRepository repo;
    private final ObjectMapper mapper = new ObjectMapper()
            .registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule())
            .disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    public HistoryStore(ProjectHistoryRepository repo) {
        this.repo = repo;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> get(String projectId) {
        return readData(projectId);
    }

    private Map<String, Object> readData(String projectId) {
        return repo.findById(projectId)
                .map(r -> parse(r.data, projectId))
                .orElseGet(() -> defaultData(projectId));
    }

    private Map<String, Object> parse(String json, String projectId) {
        try {
            Map<String, Object> parsed = mapper.readValue(json, Map.class);
            if (parsed == null) parsed = new java.util.HashMap<>();
            parsed.putIfAbsent("projectId", projectId);
            parsed.putIfAbsent("versions", List.of());
            parsed.putIfAbsent("builds", List.of());
            parsed.putIfAbsent("checks", List.of());
            return parsed;
        } catch (Exception e) {
            return defaultData(projectId);
        }
    }

    private Map<String, Object> defaultData(String projectId) {
        return new java.util.HashMap<>(Map.of(
                "projectId", projectId,
                "versions", List.of(),
                "builds", List.of(),
                "checks", List.of()));
    }

    @Transactional
    public Map<String, Object> createVersion(String projectId, String summary, int revision, int scenesCount, int filesCount, List<String> sceneNames, String author) {
        Map<String, Object> data = readData(projectId);
        List<Object> versions = new ArrayList<>((List<Object>) data.getOrDefault("versions", new ArrayList<>()));
        Map<String, Object> v = new java.util.HashMap<>();
        v.put("revision", revision);
        v.put("date", Instant.now().toString());
        v.put("summary", summary);
        v.put("scenesCount", scenesCount);
        v.put("filesCount", filesCount);
        v.put("sceneNames", sceneNames == null ? List.of() : sceneNames);
        if (author != null && !author.isBlank()) v.put("author", author);
        versions.add(0, v);
        data.put("versions", versions);
        save(projectId, data);
        return data;
    }

    @Transactional
    public Map<String, Object> recordBuild(String projectId, Map<String, Object> build) {
        Map<String, Object> data = readData(projectId);
        List<Object> builds = new ArrayList<>((List<Object>) data.getOrDefault("builds", new ArrayList<>()));
        builds.add(0, build);
        data.put("builds", builds);
        save(projectId, data);
        return data;
    }

    @Transactional
    public Map<String, Object> recordCheck(String projectId, Map<String, Object> check) {
        Map<String, Object> data = readData(projectId);
        List<Object> checks = new ArrayList<>((List<Object>) data.getOrDefault("checks", new ArrayList<>()));
        checks.add(0, check);
        if (checks.size() > 200) {
            checks = new ArrayList<>(checks.subList(0, 200));
        }
        data.put("checks", checks);
        save(projectId, data);
        return data;
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> getChecks(String projectId, String file, int limit) {
        Map<String, Object> data = readData(projectId);
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
            String json = mapper.writeValueAsString(data);
            ProjectHistoryRecord rec = repo.findById(projectId).orElse(new ProjectHistoryRecord(projectId, json, Instant.now()));
            rec.data = json;
            rec.updatedAt = Instant.now();
            repo.save(rec);
        } catch (Exception ignored) {
        }
    }
}