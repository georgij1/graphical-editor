package com.example.fxmleditor.controller;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Exposes the downloadable desktop/mobile clients of the editor so they can be
 * discovered and fetched from the Swagger UI as well as from the web frontend.
 */
@RestController
@RequestMapping("/api/clients")
@Tag(name = "Clients")
public class ClientController {

    private static final Map<String, String> FILES = new LinkedHashMap<>();
    private static final Map<String, String> TITLES = new LinkedHashMap<>();
    static {
        FILES.put("windows", "graphical_editor-windows.zip");
        FILES.put("linux", "graphical_editor-linux.tar.gz");
        TITLES.put("windows", "Windows");
        TITLES.put("linux", "Linux");
    }

    private final Path downloadsDir;

    public ClientController(@Value("${app.downloads-dir:/downloads}") String downloadsDir) {
        this.downloadsDir = Paths.get(downloadsDir);
    }

    @GetMapping
    @Operation(summary = "List the available downloadable clients")
    public ResponseEntity<?> list() {
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map.Entry<String, String> e : FILES.entrySet()) {
            File f = downloadsDir.resolve(e.getValue()).toFile();
            if (!f.exists() || !f.isFile()) continue;
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", e.getKey());
            m.put("title", TITLES.get(e.getKey()));
            m.put("fileName", e.getValue());
            m.put("size", f.length());
            m.put("downloadUrl", "/api/clients/" + e.getKey() + "/download");
            out.add(m);
        }
        return ResponseEntity.ok(Map.of("clients", out));
    }

    @GetMapping("/{id}/download")
    @Operation(summary = "Download a client artifact")
    public ResponseEntity<Resource> download(@PathVariable String id) {
        String name = FILES.get(id);
        if (name == null) return ResponseEntity.notFound().build();
        Path p = downloadsDir.resolve(name);
        File f = p.toFile();
        if (!f.exists() || !f.isFile()) return ResponseEntity.notFound().build();
        Resource r = new FileSystemResource(f);
        return ResponseEntity.ok()
                .header("Content-Disposition", "attachment; filename=\"" + name + "\"")
                .contentLength(f.length())
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .body(r);
    }
}
