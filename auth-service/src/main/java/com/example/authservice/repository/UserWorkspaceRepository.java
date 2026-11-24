package com.example.authservice.repository;

import com.example.authservice.model.UserWorkspaceRecord;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserWorkspaceRepository extends JpaRepository<UserWorkspaceRecord, String> {
}