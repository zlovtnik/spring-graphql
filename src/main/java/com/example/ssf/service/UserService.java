package com.example.ssf.service;

import com.example.ssf.entity.User;
import com.example.ssf.repository.UserRepository;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.Optional;
import java.util.UUID;
import java.util.regex.Pattern;

@Service
public class UserService {
    private static final Pattern EMAIL_PATTERN = Pattern.compile("^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$", Pattern.CASE_INSENSITIVE);

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

    public User createUser(User user) {
        validateNewUser(user);
        ensureUsernameAvailable(user.getUsername(), null);
        ensureEmailAvailable(user.getEmail(), null);
        user.setPassword(passwordEncoder.encode(user.getPassword()));
        return userRepository.save(user);
    }

    public User updateUser(UUID userId, String newUsername, String newEmail, boolean passwordChanged, String newPassword) {
        User existing = userRepository.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("User not found"));

        if (StringUtils.hasText(newUsername) && !newUsername.equals(existing.getUsername())) {
            ensureUsernameAvailable(newUsername, existing.getId());
            existing.setUsername(newUsername);
        }

        if (StringUtils.hasText(newEmail) && !newEmail.equals(existing.getEmail())) {
            validateEmailFormat(newEmail);
            ensureEmailAvailable(newEmail, existing.getId());
            existing.setEmail(newEmail);
        }

        if (passwordChanged) {
            validateRawPassword(newPassword);
            existing.setPassword(passwordEncoder.encode(newPassword));
        }

        return userRepository.save(existing);
    }

    public Optional<User> findById(UUID id) {
        return userRepository.findById(id);
    }

    private void validateNewUser(User user) {
        if (!StringUtils.hasText(user.getUsername())) {
            throw new IllegalArgumentException("Username must not be blank");
        }
        validateEmailFormat(user.getEmail());
        validateRawPassword(user.getPassword());
    }

    private void validateRawPassword(String password) {
        if (!StringUtils.hasText(password)) {
            throw new IllegalArgumentException("Password must not be blank");
        }
        if (looksEncoded(password)) {
            throw new IllegalArgumentException("Password must be provided in raw form");
        }
        if (password.length() < 8) {
            throw new IllegalArgumentException("Password must be at least 8 characters long");
        }
    }

    private void validateEmailFormat(String email) {
        if (!StringUtils.hasText(email)) {
            throw new IllegalArgumentException("Email must not be blank");
        }
        if (!EMAIL_PATTERN.matcher(email).matches()) {
            throw new IllegalArgumentException("Email format is invalid");
        }
    }

    private void ensureUsernameAvailable(String username, UUID currentUserId) {
        userRepository.findByUsername(username)
                .filter(existing -> currentUserId == null || !existing.getId().equals(currentUserId))
                .ifPresent(existing -> {
                    throw new IllegalArgumentException("Username is already in use");
                });
    }

    private void ensureEmailAvailable(String email, UUID currentUserId) {
        userRepository.findByEmail(email)
                .filter(existing -> currentUserId == null || !existing.getId().equals(currentUserId))
                .ifPresent(existing -> {
                    throw new IllegalArgumentException("Email is already in use");
                });
    }

    private boolean looksEncoded(String password) {
        return password.startsWith("$2a$") || password.startsWith("$2b$") || password.startsWith("$2y$");
    }
}
