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
    void createUser_WhenValidUser_EncodesPasswordAndPersists() {
        when(userRepository.findByUsername("testuser")).thenReturn(Optional.empty());
        when(userRepository.findByEmail("test@example.com")).thenReturn(Optional.empty());
        when(userRepository.save(testUser)).thenReturn(testUser);

        User result = userService.createUser(testUser);

        assertNotNull(result);
        assertEquals("encodedPassword", result.getPassword());
        verify(passwordEncoder).encode("password123");
        verify(userRepository).save(testUser);
    }

    @Test
    void createUser_WhenPasswordLooksEncoded_ThrowsException() {
        testUser.setPassword("$2a$10$abcdefghijklmnopqrstuv");

        assertThrows(IllegalArgumentException.class, () -> userService.createUser(testUser));

        verify(userRepository, never()).save(any());
    }

    @Test
    void createUser_WhenUsernameAlreadyExists_ThrowsException() {
        when(userRepository.findByUsername("testuser")).thenReturn(Optional.of(new User()));

        assertThrows(IllegalArgumentException.class, () -> userService.createUser(testUser));

        verify(userRepository, never()).save(any());
    }

    @Test
    void createUser_WhenEmailAlreadyExists_ThrowsException() {
        when(userRepository.findByUsername("testuser")).thenReturn(Optional.empty());
        when(userRepository.findByEmail("test@example.com")).thenReturn(Optional.of(new User()));

        assertThrows(IllegalArgumentException.class, () -> userService.createUser(testUser));

        verify(userRepository, never()).save(any());
    }

    @Test
    void createUser_WhenEmailInvalid_ThrowsException() {
        testUser.setEmail("invalid");

        assertThrows(IllegalArgumentException.class, () -> userService.createUser(testUser));

        verify(userRepository, never()).save(any());
    }

    @Test
    void createUser_WhenPasswordTooShort_ThrowsException() {
        testUser.setPassword("short");

        assertThrows(IllegalArgumentException.class, () -> userService.createUser(testUser));

        verify(userRepository, never()).save(any());
    }

    @Test
    void updateUser_WhenPasswordChanged_EncodesNewPassword() {
        UUID userId = testUser.getId();
        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(passwordEncoder.encode("newPassword")).thenReturn("newEncodedPassword");
        when(userRepository.save(testUser)).thenReturn(testUser);

        User result = userService.updateUser(userId, null, null, true, "newPassword");

        assertEquals("newEncodedPassword", result.getPassword());
        verify(passwordEncoder).encode("newPassword");
        verify(userRepository).save(testUser);
    }

    @Test
    void updateUser_WhenUsernameConflicts_ThrowsException() {
        UUID userId = testUser.getId();
        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        User conflicting = new User();
        conflicting.setId(UUID.randomUUID());
        when(userRepository.findByUsername("otherUser")).thenReturn(Optional.of(conflicting));

        assertThrows(IllegalArgumentException.class, () -> userService.updateUser(userId, "otherUser", null, false, null));

        verify(userRepository, never()).save(any());
    }

    @Test
    void updateUser_WhenEmailInvalid_ThrowsException() {
        UUID userId = testUser.getId();
        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));

        assertThrows(IllegalArgumentException.class, () -> userService.updateUser(userId, null, "invalid-email", false, null));

        verify(userRepository, never()).save(any());
    }

    @Test
    void updateUser_WhenEmailConflicts_ThrowsException() {
        UUID userId = testUser.getId();
        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        User conflicting = new User();
        conflicting.setId(UUID.randomUUID());
        when(userRepository.findByEmail("new@example.com")).thenReturn(Optional.of(conflicting));

        assertThrows(IllegalArgumentException.class, () -> userService.updateUser(userId, null, "new@example.com", false, null));

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
