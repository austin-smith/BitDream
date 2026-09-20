#ifndef BITDREAM_TAILSCALE_CORE_H
#define BITDREAM_TAILSCALE_CORE_H
// Returned UTF-8 JSON is owned by the caller and must be released exactly once.
char *BDTailscaleCommand(const char *input);
void BDTailscaleFree(char *value);
#endif
