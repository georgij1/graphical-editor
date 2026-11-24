package com.example.fxmleditor.repository;

import com.example.fxmleditor.model.ProjectRecord;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProjectRepository extends JpaRepository<ProjectRecord, String> {
}