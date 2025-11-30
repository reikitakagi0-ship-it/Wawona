void* vkGetInstanceProcAddr(void*, const char*);
int main() { return vkGetInstanceProcAddr(0, 0) != 0; }
