package com.example.fxmleditor.service;

import io.minio.*;
import io.minio.messages.Item;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

@Service
public class MinioStorageService {
    private final MinioClient client;
    private final String bucket;

    public MinioStorageService(
            @Value("${app.minio-url}") String url,
            @Value("${app.minio-access-key}") String accessKey,
            @Value("${app.minio-secret-key}") String secretKey,
            @Value("${app.minio-bucket}") String bucket) {
        this.bucket = bucket;
        this.client = MinioClient.builder()
                .endpoint(url)
                .credentials(accessKey, secretKey)
                .build();
    }

    @PostConstruct
    public void init() {
        try {
            boolean exists = client.bucketExists(BucketExistsArgs.builder().bucket(bucket).build());
            if (!exists) {
                client.makeBucket(MakeBucketArgs.builder().bucket(bucket).build());
            }
        } catch (Exception e) {
            throw new RuntimeException("Failed to initialize MinIO bucket: " + bucket, e);
        }
    }

    public void put(String key, byte[] data, String contentType) {
        try (ByteArrayInputStream bais = new ByteArrayInputStream(data)) {
            client.putObject(PutObjectArgs.builder()
                    .bucket(bucket)
                    .object(key)
                    .stream(bais, data.length, -1)
                    .contentType(contentType == null ? "application/octet-stream" : contentType)
                    .build());
        } catch (Exception e) {
            throw new RuntimeException("Failed to put object to MinIO: " + key, e);
        }
    }

    public byte[] get(String key) {
        try (InputStream is = client.getObject(GetObjectArgs.builder().bucket(bucket).object(key).build())) {
            return is.readAllBytes();
        } catch (io.minio.errors.ErrorResponseException e) {
            if ("NoSuchKey".equals(e.errorResponse().code()) || e.errorResponse().code().contains("NoSuchKey")) {
                return null;
            }
            return null;
        } catch (Exception e) {
            return null;
        }
    }

    public List<String> list(String prefix) {
        List<String> keys = new ArrayList<>();
        try {
            Iterable<Result<Item>> results = client.listObjects(ListObjectsArgs.builder()
                    .bucket(bucket)
                    .prefix(prefix)
                    .recursive(true)
                    .build());
            for (Result<Item> r : results) {
                try {
                    Item item = r.get();
                    if (item != null && !item.isDir()) keys.add(item.objectName());
                } catch (Exception ignored) {
                }
            }
        } catch (Exception ignored) {
        }
        return keys;
    }

    public void delete(String key) {
        try {
            client.removeObject(RemoveObjectArgs.builder().bucket(bucket).object(key).build());
        } catch (Exception ignored) {
        }
    }
}