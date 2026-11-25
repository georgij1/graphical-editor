package com.example.projectsservice.service;

import com.example.projectsservice.model.SharedProject;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

@Service
public class ProjectFileStorageService {
    private static final String PREFIX = "project-files/";
    private final MinioStorageService storage;
    private final ObjectMapper mapper = new ObjectMapper()
            .registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule())
            .disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    public ProjectFileStorageService(MinioStorageService storage) {
        this.storage = storage;
    }

    public void syncProject(SharedProject project) {
        if (project == null || project.id == null || project.id.isBlank()) return;
        String base = PREFIX + project.id + "/";
        Map<String, byte[]> files = projectFiles(project);
        Set<String> desired = new HashSet<>();
        for (Map.Entry<String, byte[]> e : files.entrySet()) {
            String key = base + e.getKey();
            desired.add(key);
            storage.put(key, e.getValue(), contentType(e.getKey()));
        }
        for (String existing : storage.list(base)) {
            if (!desired.contains(existing)) {
                storage.delete(existing);
            }
        }
    }

    public void deleteProject(String projectId) {
        if (projectId == null || projectId.isBlank()) return;
        String base = PREFIX + projectId + "/";
        for (String key : storage.list(base)) {
            storage.delete(key);
        }
    }

    public byte[] downloadZip(String projectId) {
        if (projectId == null || projectId.isBlank()) return null;
        String base = PREFIX + projectId + "/";
        List<String> keys = storage.list(base);
        if (keys.isEmpty()) return null;
        try (ByteArrayOutputStream baos = new ByteArrayOutputStream();
             ZipOutputStream zos = new ZipOutputStream(baos, StandardCharsets.UTF_8)) {
            keys.sort(String::compareTo);
            for (String key : keys) {
                String rel = key.substring(base.length());
                if (rel.isBlank()) continue;
                byte[] data = storage.get(key);
                if (data == null) continue;
                ZipEntry entry = new ZipEntry(rel);
                zos.putNextEntry(entry);
                zos.write(data);
                zos.closeEntry();
            }
            zos.finish();
            return baos.toByteArray();
        } catch (Exception e) {
            throw new RuntimeException("Failed to create project zip: " + projectId, e);
        }
    }

    private Map<String, byte[]> projectFiles(SharedProject project) {
        Map<String, byte[]> files = new LinkedHashMap<>();
        try {
            files.put("project.json", mapper.writerWithDefaultPrettyPrinter().writeValueAsBytes(project));
        } catch (Exception ignored) {
        }

        String pkgPath = packagePath(project.packageName);
        if (project.scenes != null) {
            for (Map<String, Object> s : project.scenes) {
                if (s == null) continue;
                String name = str(s.get("name"));
                String fxml = str(s.get("fxml"));
                if (name.isBlank() || fxml == null) continue;
                String fileName = name.endsWith(".fxml") ? name : name + ".fxml";
                String path = pkgPath.isEmpty()
                        ? "src/main/resources/" + fileName
                        : "src/main/resources/" + pkgPath + "/" + fileName;
                files.put(path, fxml.getBytes(StandardCharsets.UTF_8));
            }
        }

        if (project.sources != null) {
            for (Map.Entry<String, String> e : project.sources.entrySet()) {
                if (e.getKey() == null || e.getKey().isBlank()) continue;
                String value = e.getValue() == null ? "" : e.getValue();
                files.put(normalizePath(e.getKey()), value.getBytes(StandardCharsets.UTF_8));
            }
        }
        return files;
    }

    private static String packagePath(String packageName) {
        if (packageName == null) return "";
        String p = packageName.trim();
        if (p.isEmpty()) return "";
        return p.replace('.', '/');
    }

    private static String normalizePath(String path) {
        String p = path.replace('\\', '/');
        while (p.startsWith("/")) p = p.substring(1);
        return p;
    }

    private static String str(Object o) {
        return o == null ? "" : String.valueOf(o);
    }

    private static String contentType(String path) {
        String p = path.toLowerCase(Locale.ROOT);
        if (p.endsWith(".json")) return "application/json";
        if (p.endsWith(".xml") || p.endsWith(".fxml")) return "application/xml";
        if (p.endsWith(".java")) return "text/x-java-source";
        if (p.endsWith(".kt")) return "text/x-kotlin-source";
        if (p.endsWith(".gradle") || p.endsWith(".kts") || p.endsWith(".properties") || p.endsWith(".md") || p.endsWith(".txt")) return "text/plain";
        if (p.endsWith(".css")) return "text/css";
        return "application/octet-stream";
    }
}
