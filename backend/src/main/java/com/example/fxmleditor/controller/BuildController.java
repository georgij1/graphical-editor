package com.example.fxmleditor.controller;

import com.example.fxmleditor.service.BuildService;
import com.example.fxmleditor.service.BuildService.BuildException;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;

@RestController
@RequestMapping("/build")
@Tag(name = "Build")
public class BuildController {

    private final BuildService buildService;

    public BuildController(BuildService buildService) {
        this.buildService = buildService;
    }

    @PostMapping
    @Operation(summary = "Compile an exported project into a runnable JAR")
    public ResponseEntity<byte[]> buildJar(@RequestBody byte[] archive) {
        try {
            byte[] artifact = buildService.build(archive, false);
            return ResponseEntity.ok()
                    .header("Content-Disposition", "attachment; filename=\"app.jar\"")
                    .header("X-Artifact", "app.jar")
                    .contentType(MediaType.APPLICATION_OCTET_STREAM)
                    .body(artifact);
        } catch (BuildException e) {
            return ResponseEntity.badRequest()
                    .contentType(MediaType.TEXT_PLAIN)
                    .body(e.getMessage().getBytes());
        } catch (Exception e) {
            return ResponseEntity.status(500)
                    .contentType(MediaType.TEXT_PLAIN)
                    .body(("Build failed: " + e).getBytes());
        }
    }

    @PostMapping("/bundle")
    @Operation(summary = "Compile an exported project into a self-contained bundle (JAR + JavaFX + run scripts)")
    public ResponseEntity<byte[]> buildBundle(@RequestBody byte[] archive) {
        try {
            byte[] artifact = buildService.build(archive, true);
            return ResponseEntity.ok()
                    .header("Content-Disposition", "attachment; filename=\"bundle.zip\"")
                    .header("X-Artifact", "bundle.zip")
                    .contentType(MediaType.APPLICATION_OCTET_STREAM)
                    .body(artifact);
        } catch (BuildException e) {
            return ResponseEntity.badRequest()
                    .contentType(MediaType.TEXT_PLAIN)
                    .body(e.getMessage().getBytes());
        } catch (Exception e) {
            return ResponseEntity.status(500)
                    .contentType(MediaType.TEXT_PLAIN)
                    .body(("Build failed: " + e).getBytes());
        }
    }

    @GetMapping("/health")
    @Operation(summary = "Health check for the build service")
    public ResponseEntity<?> health() {
        return ResponseEntity.ok(java.util.Map.of("status", "ok"));
    }
}
