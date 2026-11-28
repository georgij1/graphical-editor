package com.example.analyzerservice.repository;

import com.example.analyzerservice.model.ProjectRecord;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProjectRepository extends JpaRepository<ProjectRecord, String> {
}