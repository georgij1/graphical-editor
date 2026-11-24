package com.example.fxmleditor.model;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "user_workspaces")
public class UserWorkspaceRecord {
    @Id
    @Column(name = "user_id", nullable = false, updatable = false)
    public String userId;

    @Column(name = "data", columnDefinition = "TEXT", nullable = false)
    public String data;

    @Column(name = "updated_at")
    public Instant updatedAt;

    public UserWorkspaceRecord() {}

    public UserWorkspaceRecord(String userId, String data, Instant updatedAt) {
        this.userId = userId;
        this.data = data;
        this.updatedAt = updatedAt;
    }
}