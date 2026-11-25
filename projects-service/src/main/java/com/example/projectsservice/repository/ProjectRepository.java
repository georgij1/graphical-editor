package com.example.projectsservice.repository;

import com.example.projectsservice.model.ProjectRecord;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProjectRepository extends JpaRepository<ProjectRecord, String> {
}