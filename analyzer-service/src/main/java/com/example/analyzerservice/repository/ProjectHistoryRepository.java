package com.example.analyzerservice.repository;

import com.example.analyzerservice.model.ProjectHistoryRecord;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProjectHistoryRepository extends JpaRepository<ProjectHistoryRecord, String> {
}