/*
 * Copyright 2016-2018, CZ.NIC z.s.p.o. (http://www.nic.cz/)
 *
 * This file is part of the turris updater.
 *
 * Updater is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 * Updater is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Updater.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef UPDATER_UTIL_H
#define UPDATER_UTIL_H

#include "events.h"

#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <alloca.h>

// Writes given text to file. Be aware that no information about failure is given.
bool dump2file (const char *file, const char *text) __attribute__((nonnull,nonnull));

// Executes all executable files in given directory
void exec_hook(const char *dir, const char *message) __attribute__((nonnull));

// Using these functions you can register/unregister cleanup function. Note that
// they are called in reverse order of insertion. This is implemented using atexit
// function.
typedef void (*cleanup_t)(void *data);
void cleanup_register(cleanup_t func, void *data) __attribute__((nonnull(1)));
bool cleanup_unregister(cleanup_t func) __attribute__((nonnull)); // Note: removes only first occurrence
bool cleanup_unregister_data(cleanup_t func, void *data) __attribute__((nonnull(1))); // Also matches data, not only function
void cleanup_run(cleanup_t func); // Run function and unregister it
void cleanup_run_all(void); // Run all cleanup functions explicitly

// Disable system reboot. If this function is called before system_reboot is than
// system reboot just prints warning about skipped reboot and returns.
void system_reboot_disable();
// Reboot system. Argument stick signals if updater should stick or continue.
void system_reboot(bool stick);

// Compute the size needed (including \0) to format given message
size_t printf_len(const char *msg, ...) __attribute__((format(printf, 1, 2)));
// Like sprintf, but returs the string. Expects there's enough space.
char *printf_into(char *dst, const char *msg, ...) __attribute__((format(printf, 2, 3)));
// Like printf, but allocates the data on the stack with alloca and returns. It uses the arguments multiple times, so beware of side effects.
#define aprintf(...) printf_into(alloca(printf_len(__VA_ARGS__)), __VA_ARGS__)

// GCC 7+ reports fall troughs but previous versions doesn't understand attribute
// for it so we have this macro to not put it in place if it's not needed.
#if  __GNUC__ >= 7
#define FALLTROUGH  __attribute__((fallthrough))
#else
#define FALLTROUGH
#endif

#endif
