package com.example.fxmleditor.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.Instant;

@JsonInclude(JsonInclude.Include.NON_NULL)
public class UserRecord {
    public String id;
    public String email;
    public String salt;
    public String hash;
    public Instant createdAt;
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
