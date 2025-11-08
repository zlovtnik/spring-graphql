package com.example.ssf.service;

import com.example.ssf.entity.User;
import com.example.ssf.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.util.StringUtils;
import java.util.Optional;
import java.util.UUID;

@Service
public class UserService {
    private static final String BCRYPT_PREFIX = "$2";

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    public UserService(UserRepository userRepository, PasswordEncoder passwordEncoder) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
    }

    public Optional<User> findByUsername(String username) {
        return userRepository.findByUsername(username);
    }

    public Optional<User> findByEmail(String email) {
        return userRepository.findByEmail(email);
    }

    public User save(User user) {
        validateUser(user);
        user.setPassword(encodePasswordIfNecessary(user.getPassword()));
        return userRepository.save(user);
    }

    public Optional<User> findById(UUID id) {
        return userRepository.findById(id);
    }

    private void validateUser(User user) {
        if (!StringUtils.hasText(user.getUsername())) {
            throw new IllegalArgumentException("Username must not be blank");
        }
        if (!StringUtils.hasText(user.getEmail())) {
            throw new IllegalArgumentException("Email must not be blank");
        }
        if (!StringUtils.hasText(user.getPassword())) {
            throw new IllegalArgumentException("Password must not be blank");
        }
        if (user.getPassword().length() < 8) {
            throw new IllegalArgumentException("Password must be at least 8 characters long");
        }
    }

    private String encodePasswordIfNecessary(String password) {
        if (password.startsWith(BCRYPT_PREFIX)) {
            return password;
        }
        return passwordEncoder.encode(password);
    }
}
