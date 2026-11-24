#include "CHelperProcessSandbox.h"

#if defined(__linux__) && (defined(__x86_64__) || defined(__aarch64__))
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <sys/prctl.h>
#include <sys/syscall.h>

#if defined(__x86_64__)
#define SOU_ARCH AUDIT_ARCH_X86_64
#else
#define SOU_ARCH AUDIT_ARCH_AARCH64
#endif

#define SOU_DENY BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA))
#define SOU_LOAD_NR BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr))
/* Refuse syscall `nr` outright. */
#define SOU_REFUSE(nr) BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, (nr), 0, 1), SOU_DENY
/* Refuse syscall `nr` when its flags argument asks to write or create. */
#define SOU_WRITE_FLAGS (O_WRONLY | O_RDWR | O_CREAT | O_TRUNC | O_APPEND)
#define SOU_REFUSE_WRITING(nr, arg) \
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, (nr), 0, 4), \
    BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, args[arg])), \
    BPF_JUMP(BPF_JMP | BPF_JSET | BPF_K, SOU_WRITE_FLAGS, 0, 1), \
    SOU_DENY, \
    SOU_LOAD_NR

int sou_helper_process_confine(void) {
    struct sock_filter filter[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SOU_ARCH, 1, 0),
        SOU_DENY, /* another ABI (x32, i386 compat): nothing */
        SOU_LOAD_NR,
        SOU_REFUSE(__NR_socket), SOU_REFUSE(__NR_socketpair), SOU_REFUSE(__NR_connect), SOU_REFUSE(__NR_bind),
        SOU_REFUSE(__NR_listen), SOU_REFUSE(__NR_accept), SOU_REFUSE(__NR_accept4), SOU_REFUSE(__NR_sendto),
        SOU_REFUSE(__NR_sendmsg), SOU_REFUSE(__NR_execve), SOU_REFUSE(__NR_execveat), SOU_REFUSE(__NR_ptrace),
        SOU_REFUSE(__NR_process_vm_writev), SOU_REFUSE(__NR_process_vm_readv),
        SOU_REFUSE(__NR_unlinkat), SOU_REFUSE(__NR_renameat2), SOU_REFUSE(__NR_mkdirat), SOU_REFUSE(__NR_truncate),
        SOU_REFUSE(__NR_linkat), SOU_REFUSE(__NR_symlinkat),
#if defined(__x86_64__)
        SOU_REFUSE(__NR_creat), SOU_REFUSE(__NR_unlink), SOU_REFUSE(__NR_rename), SOU_REFUSE(__NR_renameat),
        SOU_REFUSE(__NR_mkdir), SOU_REFUSE(__NR_rmdir), SOU_REFUSE(__NR_link), SOU_REFUSE(__NR_symlink),
        SOU_REFUSE(__NR_fork), SOU_REFUSE(__NR_vfork),
        SOU_REFUSE_WRITING(__NR_open, 1),
#else
        SOU_REFUSE(__NR_renameat),
#endif
        SOU_REFUSE_WRITING(__NR_openat, 2),
#ifdef __NR_openat2
        SOU_REFUSE(__NR_openat2), /* its flags live behind a pointer the filter cannot read */
#endif
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    struct sock_fprog program = { .len = (unsigned short)(sizeof(filter) / sizeof(filter[0])), .filter = filter };
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) return -1;
    if (prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program) != 0) return -1;
    return 0;
}

#else
int sou_helper_process_confine(void) { return -1; }
#endif
