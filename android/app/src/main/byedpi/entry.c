#include <signal.h>
#include <android/multinetwork.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <unistd.h>

#define main byedpi_main
#include "upstream/main.c"
#undef main

int main(int argc, char **argv) {
    pid_t owner = getppid();
    if (owner == 1 || prctl(PR_SET_PDEATHSIG, SIGKILL) || getppid() != owner)
        return 1;
    const char *network = getenv("FLCLASH_NETWORK");
    if (network && android_setprocnetwork(strtoull(network, NULL, 10)))
        return 1;
    return byedpi_main(argc, argv);
}
