package com.example.analyzerservice.model;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "project_history")
public class ProjectHistoryRecord {
    @Id
    @Column(name = "project_id", nullable = false, updatable = false)
    public String projectId;

    @Column(name = "data", columnDefinition = "TEXT", nullable = false)
    public String data;

    @Column(name = "updated_at")
    public Instant updatedAt;

    public ProjectHistoryRecord() {}

    public ProjectHistoryRecord(String projectId, String data, Instant updatedAt) {
        this.projectId = projectId;
        this.data = data;
        this.updatedAt = updatedAt;
    }
}