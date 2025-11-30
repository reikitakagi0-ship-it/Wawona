#include "util/ios_sys_headers.h"
#include <sys/prctl.h>
int main() {
    prctl(0);
    return 0;
}
