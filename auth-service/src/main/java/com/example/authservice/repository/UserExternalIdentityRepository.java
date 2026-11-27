package com.example.authservice.repository;

import com.example.authservice.model.UserExternalIdentity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface UserExternalIdentityRepository extends JpaRepository<UserExternalIdentity, String> {
    Optional<UserExternalIdentity> findByProviderAndProviderUserId(String provider, String providerUserId);
    List<UserExternalIdentity> findByUserId(String userId);
    void deleteByUserId(String userId);
}
