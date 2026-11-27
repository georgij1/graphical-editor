package com.example.authservice.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import jakarta.persistence.*;

import java.time.Instant;

@JsonInclude(JsonInclude.Include.NON_NULL)
@Entity
@Table(name = "app_users")
public class UserRecord {
    @Id
    @Column(nullable = false, updatable = false)
    public String id;

    @Column(nullable = false, unique = true)
    public String email;

    @Column
    public String salt;

    @Column
    public String hash;

    @Column(name = "created_at")
    public Instant createdAt;

    @Column(columnDefinition = "TEXT")
    public String avatar;

    public UserRecord() {}

    public UserRecord(String id, String email, String salt, String hash, Instant createdAt) {
        this.id = id;
        this.email = email;
        this.salt = salt;
        this.hash = hash;
        this.createdAt = createdAt;
    }
}
