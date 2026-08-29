#include <jni.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/system_properties.h>
#include <sys/utsname.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <android/log.h>

#define TAG "PixelNativeProbe"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)

#define KSU_MAGIC_1 0xDEADBEEF
#define KSU_MAGIC_2 0xCAFEBABE

static int check_kernelsu_active(void) {
    pid_t pid = fork();
    if (pid < 0) {
        return 0;
    }
    if (pid == 0) {
        // Child process: isolated from parent.
        // If KernelSU is not present, SECCOMP will trigger SIGSYS and only this child process will terminate.
        int fd = -1;
        if (syscall(SYS_reboot, KSU_MAGIC_1, KSU_MAGIC_2, 0, &fd) == 0 && fd >= 0) {
            close(fd);
            _exit(0);
        }
        _exit(1);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) == pid) {
        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
            return 1;
        }
    }
    return 0;
}

static int read_file(const char *path, char *buf, size_t size) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    ssize_t n = read(fd, buf, size - 1);
    close(fd);
    if (n < 0) return -1;
    buf[n] = '\0';
    return 0;
}

static void get_prop(const char *key, char *buf, size_t size) {
    buf[0] = '\0';
    int len = __system_property_get(key, buf);
    if (len <= 0 || buf[0] == '\0') {
        snprintf(buf, size, "unknown");
    }
}

JNIEXPORT jboolean JNICALL
Java_com_alex193a_rootmypixel_utils_NativeProbe_isKernelSuActiveNative(
        JNIEnv *env __attribute__((unused)), jobject thiz __attribute__((unused))) {
    return check_kernelsu_active() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_alex193a_rootmypixel_utils_NativeProbe_run(
    JNIEnv *env, jobject thiz __attribute__((unused))) {

    char output[4096];
    int off = 0;

    struct utsname uts;
    if (uname(&uts) == 0) {
        off += snprintf(output + off, sizeof(output) - off,
                        "sysname: %s\n", uts.sysname);
        off += snprintf(output + off, sizeof(output) - off,
                        "nodename: %s\n", uts.nodename);
        off += snprintf(output + off, sizeof(output) - off,
                        "release: %s\n", uts.release);
        off += snprintf(output + off, sizeof(output) - off,
                        "version: %s\n", uts.version);
        off += snprintf(output + off, sizeof(output) - off,
                        "machine: %s\n", uts.machine);
    }

    char version[512] = {0};
    if (read_file("/proc/version", version, sizeof(version)) == 0) {
        off += snprintf(output + off, sizeof(output) - off,
                        "proc_version: %s", version);
    }

    char model[PROP_VALUE_MAX];
    char device[PROP_VALUE_MAX];
    char build[PROP_VALUE_MAX];
    char sdk[PROP_VALUE_MAX];
    char abi[PROP_VALUE_MAX];
    char fingerprint[PROP_VALUE_MAX];

    get_prop("ro.product.model", model, sizeof(model));
    get_prop("ro.product.device", device, sizeof(device));
    get_prop("ro.build.display.id", build, sizeof(build));
    get_prop("ro.build.version.sdk", sdk, sizeof(sdk));
    get_prop("ro.product.cpu.abi", abi, sizeof(abi));
    get_prop("ro.build.fingerprint", fingerprint, sizeof(fingerprint));

    off += snprintf(output + off, sizeof(output) - off,
                    "\nmodel: %s\ndevice: %s\nbuild: %s\n"
                    "sdk: %s\nabi: %s\nfingerprint: %s\n"
                    "pid: %d uid: %d\n",
                    model, device, build, sdk, abi, fingerprint,
                    getpid(), getuid());

    // Check for KernelSU
    if (check_kernelsu_active()) {
        off += snprintf(output + off, sizeof(output) - off,
                "kernelsu: active\n");
    }

    return (*env)->NewStringUTF(env, output);
}
