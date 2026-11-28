package com.example.analyzerservice.service;

import com.example.analyzerservice.model.ProjectRecord;
import com.example.analyzerservice.model.SharedProject;
import com.example.analyzerservice.repository.ProjectRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

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
}
