package com.example.aiservice;

import org.springframework.boot.SpringApplication;
import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.servers.Server;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@OpenAPIDefinition(servers = @Server(url = "/"))
@SpringBootApplication
public class AiServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(AiServiceApplication.class, args);
    }
}
