package com.example.ssf;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
import org.springframework.validation.annotation.Validated;

@Validated
@ConfigurationProperties(prefix = "jwt")
@Component
public class JwtProperties {
    @NotBlank
    @Size(min = 32)
    private String secret;

    @JsonIgnore
    public String getSecret() {
        return secret;
    }

    public void setSecret(String secret) {
        this.secret = secret;
    }

    @Override
    public String toString() {
        return "JwtProperties{secret='[PROTECTED]'}";
    }
}
