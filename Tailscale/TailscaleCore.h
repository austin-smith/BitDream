#ifndef BITDREAM_TAILSCALE_CORE_H
#define BITDREAM_TAILSCALE_CORE_H
// Returned UTF-8 JSON is owned by the caller and must be released exactly once.
unsigned long long BDTailscaleBeginOperation(long long milliseconds, int ownsProxy, unsigned long long parent);
void BDTailscaleCancelOperation(unsigned long long operation);
void BDTailscaleEndOperation(unsigned long long operation);
char *BDTailscaleCommand(const char *input, unsigned long long operation);
void BDTailscaleFree(char *value);
#endif
