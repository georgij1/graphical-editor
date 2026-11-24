package com.example.fxmleditor.repository;

import com.example.fxmleditor.model.UserWorkspaceRecord;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserWorkspaceRepository extends JpaRepository<UserWorkspaceRecord, String> {
}