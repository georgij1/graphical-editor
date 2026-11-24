package com.example.fxmleditor.repository;

import com.example.fxmleditor.model.UserRecord;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface UserRepository extends JpaRepository<UserRecord, String> {
    Optional<UserRecord> findByEmailIgnoreCase(String email);
    boolean existsByEmailIgnoreCase(String email);
}