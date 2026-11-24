package com.example.fxmleditor.service;

import com.example.fxmleditor.model.ProjectRecord;
import com.example.fxmleditor.model.SharedProject;
import com.example.fxmleditor.repository.ProjectRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

@Service
public class ProjectStore {
    private final ProjectRepository repo;
    private final ObjectMapper mapper = new ObjectMapper()
            .registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule())
            .disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    public ProjectStore(ProjectRepository repo) {
        this.repo = repo;
    }

    @Transactional(readOnly = true)
    public SharedProject find(String id) {
        return repo.findById(id).map(r -> parse(r.data)).orElse(null);
    }

    private SharedProject parse(String json) {
        try {
            return mapper.readValue(json, SharedProject.class);
        } catch (Exception e) {
            return null;
        }
    }

    @Transactional(readOnly = true)
    public List<SharedProject> listAll() {
        List<SharedProject> result = new ArrayList<>();
        for (ProjectRecord r : repo.findAll()) {
            SharedProject p = parse(r.data);
            if (p != null) result.add(p);
        }
        return result;
    }

    @Transactional(readOnly = true)
    public List<SharedProject> listFor(String userId, String email) {
        List<SharedProject> result = new ArrayList<>();
        for (SharedProject p : listAll()) {
            if (p.canRead(userId, email)) result.add(p);
        }
        result.sort((a, b) -> a.name.compareToIgnoreCase(b.name));
        return result;
    }

    @Transactional(readOnly = true)
    public SharedProject findByInvite(String token) {
        for (SharedProject p : listAll()) {
            if (token != null && !token.isEmpty() && token.equals(p.inviteToken)) return p;
        }
        return null;
    }

    @Transactional
    public SharedProject save(SharedProject project) {
        project.revision += 1;
        project.updatedAt = Instant.now();
        try {
            String json = mapper.writeValueAsString(project);
            ProjectRecord rec = repo.findById(project.id).orElse(new ProjectRecord());
            rec.projectId = project.id;
            rec.ownerId = project.ownerId;
            rec.name = project.name;
            rec.data = json;
            rec.updatedAt = project.updatedAt;
            repo.save(rec);
            return project;
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    @Transactional
    public void delete(String id) {
        if (id != null) repo.deleteById(id);
    }
}