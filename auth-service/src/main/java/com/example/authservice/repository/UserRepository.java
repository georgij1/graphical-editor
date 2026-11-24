package com.example.authservice.repository;

import com.example.authservice.model.UserRecord;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface UserRepository extends JpaRepository<UserRecord, String> {
    Optional<UserRecord> findByEmailIgnoreCase(String email);
    boolean existsByEmailIgnoreCase(String email);
}