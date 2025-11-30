#include "pixman/ios_compat.h"
int main() {
    uint32_t arr[1];
    getisax(arr, 1);
    feenableexcept(0);
    return 0;
}
