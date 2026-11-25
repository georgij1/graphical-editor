package com.example.storageservice.controller;

import com.example.storageservice.security.JwtService;
import com.example.storageservice.service.MinioStorageService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Map;

@RestController
@RequestMapping("/api/minio")
@Tag(name = "MinIO")
public class MinioController {
    private final JwtService jwt;
    private final MinioStorageService storage;

    public MinioController(JwtService jwt, MinioStorageService storage) {
        this.jwt = jwt;
        this.storage = storage;
    }

    private boolean isAuthenticated(String auth) {
        if (auth == null || !auth.toLowerCase().startsWith("bearer ")) return false;
        String token = auth.substring(7).trim();
        if (token.isEmpty()) return false;
        try {
            return jwt.verify(token) != null;
        } catch (Exception e) {
            return false;
        }
    }

    private ResponseEntity<?> unauthorized() {
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Not authenticated."));
    }

    @GetMapping("/objects")
    @Operation(summary = "List objects in MinIO bucket")
    public ResponseEntity<?> list(@RequestHeader(value = "Authorization", required = false) String auth,
                                  @RequestParam(value = "prefix", required = false, defaultValue = "") String prefix) {
        if (!isAuthenticated(auth)) return unauthorized();
        return ResponseEntity.ok(Map.of("objects", storage.list(prefix == null ? "" : prefix)));
    }

    @GetMapping("/object")
    @Operation(summary = "Download object from MinIO")
    public ResponseEntity<?> get(@RequestHeader(value = "Authorization", required = false) String auth,
                                 @RequestParam("key") String key) {
        if (!isAuthenticated(auth)) return unauthorized();
        if (key == null || key.isBlank()) return ResponseEntity.badRequest().body(Map.of("error", "key is required"));
        byte[] data = storage.get(key);
        if (data == null) return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", "Object not found"));
        String filename = key.contains("/") ? key.substring(key.lastIndexOf('/') + 1) : key;
        String encoded = URLEncoder.encode(filename, StandardCharsets.UTF_8).replace("+", "%20");
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename*=UTF-8''" + encoded)
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .body(data);
    }

    @PutMapping(value = "/object", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @Operation(summary = "Upload object to MinIO")
    public ResponseEntity<?> put(@RequestHeader(value = "Authorization", required = false) String auth,
                                 @RequestParam("key") String key,
                                 @RequestPart("file") MultipartFile file) {
        if (!isAuthenticated(auth)) return unauthorized();
        if (key == null || key.isBlank()) return ResponseEntity.badRequest().body(Map.of("error", "key is required"));
        if (file == null || file.isEmpty()) return ResponseEntity.badRequest().body(Map.of("error", "file is required"));
        try {
            String contentType = file.getContentType();
            storage.put(key, file.getBytes(), contentType == null ? "application/octet-stream" : contentType);
            return ResponseEntity.ok(Map.of("ok", true, "key", key, "size", file.getSize()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(Map.of("error", e.getMessage()));
        }
    }

    @DeleteMapping("/object")
    @Operation(summary = "Delete object from MinIO")
    public ResponseEntity<?> delete(@RequestHeader(value = "Authorization", required = false) String auth,
                                    @RequestParam("key") String key) {
        if (!isAuthenticated(auth)) return unauthorized();
        if (key == null || key.isBlank()) return ResponseEntity.badRequest().body(Map.of("error", "key is required"));
        storage.delete(key);
        return ResponseEntity.ok(Map.of("ok", true, "key", key));
    }
}