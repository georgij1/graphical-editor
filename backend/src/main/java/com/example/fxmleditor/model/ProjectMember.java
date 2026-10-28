package com.example.fxmleditor.model;

public class ProjectMember {
    public String email;
    public String role = "editor";

    public ProjectMember() {}

    public ProjectMember(String email, String role) {
        this.email = email;
        this.role = role;
    }
}
