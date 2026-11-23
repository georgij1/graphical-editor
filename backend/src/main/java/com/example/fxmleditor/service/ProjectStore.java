package com.example.fxmleditor.service;

import com.example.fxmleditor.model.SharedProject;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.locks.ReentrantLock;

@Service
public class ProjectStore {
    private static final String PREFIX = "projects/";
    private final MinioStorageService storage;
    private final ObjectMapper mapper = new ObjectMapper()
            .registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule())
            .disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
    private final ReentrantLock lock = new ReentrantLock();

    public ProjectStore(MinioStorageService storage) {
        this.storage = storage;
    }

    private String key(String id) {
        return PREFIX + id + ".json";
    }

    public SharedProject find(String id) {
        lock.lock();
        try {
            byte[] data = storage.get(key(id));
            if (data == null) return null;
            try {
                return mapper.readValue(data, SharedProject.class);
            } catch (Exception e) {
                return null;
            }
        } finally {
            lock.unlock();
        }
    }

    public List<SharedProject> listAll() {
        lock.lock();
        try {
            List<SharedProject> result = new ArrayList<>();
            for (String k : storage.list(PREFIX)) {
                if (!k.endsWith(".json")) continue;
                byte[] data = storage.get(k);
                if (data == null) continue;
                try {
                    result.add(mapper.readValue(data, SharedProject.class));
                } catch (Exception ignored) {
                }
            }
            return result;
        } finally {
            lock.unlock();
        }
    }

    public List<SharedProject> listFor(String userId, String email) {
        List<SharedProject> result = new ArrayList<>();
        for (SharedProject p : listAll()) {
            if (p.canRead(userId, email)) result.add(p);
        }
        result.sort((a, b) -> a.name.compareToIgnoreCase(b.name));
        return result;
    }

    public SharedProject findByInvite(String token) {
        for (SharedProject p : listAll()) {
            if (token != null && !token.isEmpty() && token.equals(p.inviteToken)) return p;
        }
        return null;
    }

    public SharedProject save(SharedProject project) {
        lock.lock();
        try {
            project.revision += 1;
            project.updatedAt = java.time.Instant.now();
            try {
                byte[] bytes = mapper.writeValueAsBytes(project);
                storage.put(key(project.id), bytes, "application/json");
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
            return project;
        } finally {
            lock.unlock();
        }
    }

    public void delete(String id) {
        lock.lock();
        try {
            storage.delete(key(id));
        } finally {
            lock.unlock();
        }
    }
}