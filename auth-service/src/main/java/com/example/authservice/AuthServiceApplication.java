package com.example.authservice;

import org.springframework.boot.SpringApplication;
import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.servers.Server;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@OpenAPIDefinition(servers = @Server(url = "/"))
@SpringBootApplication
public class AuthServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(AuthServiceApplication.class, args);
    }
}
