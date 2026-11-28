package com.example.analyzerservice.model;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "projects")
public class ProjectRecord {
    @Id
    @Column(name = "project_id", nullable = false, updatable = false)
    public String projectId;

    @Column(name = "owner_id")
    public String ownerId;

    @Column(name = "name")
    public String name;

    @Column(name = "data", columnDefinition = "TEXT", nullable = false)
    public String data;

    @Column(name = "updated_at")
    public Instant updatedAt;

    public ProjectRecord() {}

    public ProjectRecord(String projectId, String ownerId, String name, String data, Instant updatedAt) {
        this.projectId = projectId;
        this.ownerId = ownerId;
        this.name = name;
        this.data = data;
        this.updatedAt = updatedAt;
    }
}