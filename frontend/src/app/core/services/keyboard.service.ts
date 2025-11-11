import { Injectable, PLATFORM_ID, inject } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { Router } from '@angular/router';
import { Subject } from 'rxjs';

export interface KeyboardShortcut {
  key: string;
  ctrlKey?: boolean;
  altKey?: boolean;
  shiftKey?: boolean;
  description: string;
  action: () => void;
}

@Injectable({
  providedIn: 'root'
})
export class KeyboardService {
  private shortcuts: KeyboardShortcut[] = [];
  private platformId = inject(PLATFORM_ID);
  private router = inject(Router);

  shortcutTriggered$ = new Subject<KeyboardShortcut>();

  constructor() {
    if (isPlatformBrowser(this.platformId)) {
      this.initKeyboardListener();
      this.registerDefaultShortcuts();
    }
  }

  /**
   * Register a keyboard shortcut
   */
  registerShortcut(shortcut: KeyboardShortcut): void {
    this.shortcuts.push(shortcut);
  }

  /**
   * Unregister a shortcut by key combination
   */
  unregisterShortcut(key: string, ctrlKey = false, altKey = false, shiftKey = false): void {
    this.shortcuts = this.shortcuts.filter(s =>
      !(s.key === key && s.ctrlKey === ctrlKey && s.altKey === altKey && s.shiftKey === shiftKey)
    );
  }

  /**
   * Get all registered shortcuts
   */
  getShortcuts(): KeyboardShortcut[] {
    return [...this.shortcuts];
  }

  /**
   * Initialize global keyboard listener
   */
  private initKeyboardListener(): void {
    document.addEventListener('keydown', (event) => {
      // Skip if typing in input/textarea
      if (this.isTypingInInput(event.target as HTMLElement)) {
        return;
      }

      const shortcut = this.shortcuts.find(s =>
        s.key.toLowerCase() === event.key.toLowerCase() &&
        !!s.ctrlKey === event.ctrlKey &&
        !!s.altKey === event.altKey &&
        !!s.shiftKey === event.shiftKey
      );

      if (shortcut) {
        event.preventDefault();
        shortcut.action();
        this.shortcutTriggered$.next(shortcut);
      }
    });
  }

  /**
   * Register default shortcuts
   */
  private registerDefaultShortcuts(): void {
    // Ctrl+K: Focus search (if exists)
    this.registerShortcut({
      key: 'k',
      ctrlKey: true,
      description: 'Focus search',
      action: () => {
        const searchInput = document.querySelector('input[placeholder*="search" i], input[placeholder*="Search" i]') as HTMLInputElement;
        if (searchInput) {
          searchInput.focus();
        }
      }
    });

    // Ctrl+/ : Show shortcuts help
    this.registerShortcut({
      key: '/',
      ctrlKey: true,
      description: 'Show keyboard shortcuts',
      action: () => {
        this.showShortcutsModal();
      }
    });

    // Escape: Close modals/drawers
    this.registerShortcut({
      key: 'Escape',
      description: 'Close modals and drawers',
      action: () => {
        const modal = document.querySelector('.ant-modal-mask');
        const drawer = document.querySelector('.ant-drawer-mask');
        if (modal) {
          (modal.parentElement?.querySelector('.ant-modal-close') as HTMLElement)?.click();
        } else if (drawer) {
          (drawer.parentElement?.querySelector('.ant-drawer-close') as HTMLElement)?.click();
        }
      }
    });

    // Ctrl+H: Go to dashboard/home
    this.registerShortcut({
      key: 'h',
      ctrlKey: true,
      description: 'Go to dashboard',
      action: () => {
        this.router.navigate(['/']);
      }
    });

    // Ctrl+U: Go to users
    this.registerShortcut({
      key: 'u',
      ctrlKey: true,
      description: 'Go to users',
      action: () => {
        this.router.navigate(['/users']);
      }
    });

    // Ctrl+D: Go to dynamic CRUD
    this.registerShortcut({
      key: 'd',
      ctrlKey: true,
      description: 'Go to dynamic CRUD',
      action: () => {
        this.router.navigate(['/dynamic-crud']);
      }
    });
  }

  /**
   * Check if user is typing in an input element
   */
  private isTypingInInput(target: HTMLElement): boolean {
    const tagName = target.tagName.toLowerCase();
    const contentEditable = target.contentEditable === 'true';
    const isInput = tagName === 'input' || tagName === 'textarea' || tagName === 'select';
    return isInput || contentEditable;
  }

  /**
   * Show shortcuts modal (placeholder)
   */
  private showShortcutsModal(): void {
    // TODO: Implement shortcuts modal
    console.log('Keyboard shortcuts:', this.getShortcuts());
  }
}