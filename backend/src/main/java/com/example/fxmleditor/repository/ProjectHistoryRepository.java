package com.example.fxmleditor.repository;

import com.example.fxmleditor.model.ProjectHistoryRecord;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProjectHistoryRepository extends JpaRepository<ProjectHistoryRecord, String> {
}