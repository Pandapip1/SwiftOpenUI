#ifndef CHELPERPROCESSSANDBOX_H
#define CHELPERPROCESSSANDBOX_H

/// Confines the calling process (Linux): no new privileges, and a seccomp filter that refuses with
/// EPERM every syscall that would open a network connection, start a program, trace another
/// process, or create, write, rename or remove a file. Reading files (shared libraries, locale
/// data) stays possible. Returns 0 when installed, -1 where unsupported (other systems or
/// architectures) or refused by the kernel.
int sou_helper_process_confine(void);

#endif
