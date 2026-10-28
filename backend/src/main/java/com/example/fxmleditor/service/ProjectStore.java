package com.example.fxmleditor.service;

import com.example.fxmleditor.model.ProjectMember;
import com.example.fxmleditor.model.SharedProject;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.locks.ReentrantLock;

@Service
public class ProjectStore {
    private final Path projectsDir;
    private final ObjectMapper mapper = new ObjectMapper().registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule()).disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
    private final ReentrantLock lock = new ReentrantLock();

    public ProjectStore(@Value("${app.data-dir}") String dataDir) {
        this.projectsDir = Paths.get(dataDir).resolve("projects");
    }

    public void init() throws IOException {
        Files.createDirectories(projectsDir);
    }

    private Path file(String id) {
        return projectsDir.resolve(id + ".json");
    }

    public SharedProject find(String id) {
        lock.lock();
        try {
            Path f = file(id);
            if (!Files.exists(f)) return null;
            try {
                return mapper.readValue(f.toFile(), SharedProject.class);
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
            if (!Files.exists(projectsDir)) return result;
            try (var stream = Files.list(projectsDir)) {
                stream.filter(p -> p.toString().endsWith(".json")).forEach(p -> {
                    try {
                        result.add(mapper.readValue(p.toFile(), SharedProject.class));
                    } catch (Exception ignored) {
                    }
                });
            } catch (Exception ignored) {
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
            try {
                Files.createDirectories(projectsDir);
            } catch (Exception ignored) {
            }
            project.revision += 1;
            project.updatedAt = java.time.Instant.now();
            try {
                mapper.writeValue(file(project.id).toFile(), project);
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
            try {
                Files.deleteIfExists(file(id));
            } catch (Exception ignored) {
            }
        } finally {
            lock.unlock();
        }
    }
}
