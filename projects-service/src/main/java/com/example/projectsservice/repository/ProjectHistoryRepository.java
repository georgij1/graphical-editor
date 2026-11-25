package com.example.projectsservice.repository;

import com.example.projectsservice.model.ProjectHistoryRecord;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProjectHistoryRepository extends JpaRepository<ProjectHistoryRecord, String> {
}