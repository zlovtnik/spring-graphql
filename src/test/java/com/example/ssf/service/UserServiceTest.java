package com.example.ssf.service;

import com.example.ssf.entity.User;
import com.example.ssf.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class UserServiceTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @InjectMocks
    private UserService userService;

    private User testUser;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        
        testUser = new User();
        testUser.setId(UUID.randomUUID());
        testUser.setUsername("testuser");
        testUser.setEmail("test@example.com");
        testUser.setPassword("password123");

        when(passwordEncoder.encode(any(String.class))).thenReturn("encodedPassword");
    }

    @Test
    void findByUsername_WhenUserExists_ReturnsUser() {
        when(userRepository.findByUsername("testuser")).thenReturn(Optional.of(testUser));

        Optional<User> result = userService.findByUsername("testuser");

        assertTrue(result.isPresent());
        assertEquals("testuser", result.get().getUsername());
        verify(userRepository).findByUsername("testuser");
    }

    @Test
    void findByUsername_WhenUserDoesNotExist_ReturnsEmpty() {
        when(userRepository.findByUsername("nonexistent")).thenReturn(Optional.empty());

        Optional<User> result = userService.findByUsername("nonexistent");

        assertFalse(result.isPresent());
        verify(userRepository).findByUsername("nonexistent");
    }

    @Test
    void findByEmail_WhenUserExists_ReturnsUser() {
        when(userRepository.findByEmail("test@example.com")).thenReturn(Optional.of(testUser));

        Optional<User> result = userService.findByEmail("test@example.com");

        assertTrue(result.isPresent());
        assertEquals("test@example.com", result.get().getEmail());
        verify(userRepository).findByEmail("test@example.com");
    }

    @Test
    void save_WhenValidUser_EncodesPasswordAndPersists() {
        when(userRepository.save(any(User.class))).thenReturn(testUser);

        User result = userService.save(testUser);

        assertNotNull(result);
        assertEquals(testUser.getUsername(), result.getUsername());
        assertEquals("encodedPassword", testUser.getPassword());
        verify(passwordEncoder).encode("password123");
        verify(userRepository).save(testUser);
    }

    @Test
    void save_WhenPasswordAlreadyEncoded_SkipsEncoding() {
        String encoded = "$2a$10$abcdefghijklmnopqrstuv";
        testUser.setPassword(encoded);
        when(userRepository.save(any(User.class))).thenReturn(testUser);

        userService.save(testUser);

        verify(passwordEncoder, never()).encode(anyString());
        verify(userRepository).save(testUser);
    }

    @Test
    void save_WhenPasswordBlank_ThrowsException() {
        testUser.setPassword(" ");

        assertThrows(IllegalArgumentException.class, () -> userService.save(testUser));

        verify(userRepository, never()).save(any());
    }

    @Test
    void save_WhenPasswordTooShort_ThrowsException() {
        testUser.setPassword("short");

        assertThrows(IllegalArgumentException.class, () -> userService.save(testUser));

        verify(userRepository, never()).save(any());
    }

    @Test
    void findById_WhenUserExists_ReturnsUser() {
        when(userRepository.findById(testUser.getId())).thenReturn(Optional.of(testUser));

        Optional<User> result = userService.findById(testUser.getId());

        assertTrue(result.isPresent());
        assertEquals(testUser.getId(), result.get().getId());
        verify(userRepository).findById(testUser.getId());
    }
}
