package com.example.authservice.model;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "user_external_identities",
        uniqueConstraints = @UniqueConstraint(name = "uk_external_identity_provider_user", columnNames = {"provider", "provider_user_id"}),
        indexes = {
                @Index(name = "idx_external_identity_user_id", columnList = "user_id"),
                @Index(name = "idx_external_identity_email", columnList = "email")
        })
public class UserExternalIdentity {
    @Id
    @Column(nullable = false, updatable = false)
    public String id;

    @Column(name = "user_id", nullable = false)
    public String userId;

    @Column(nullable = false)
    public String provider;

    @Column(name = "provider_user_id", nullable = false)
    public String providerUserId;

    @Column
    public String email;

    @Column(name = "created_at")
    public Instant createdAt;

    public UserExternalIdentity() {}

    public UserExternalIdentity(String id, String userId, String provider, String providerUserId, String email, Instant createdAt) {
        this.id = id;
        this.userId = userId;
        this.provider = provider;
        this.providerUserId = providerUserId;
        this.email = email;
        this.createdAt = createdAt;
    }
}
