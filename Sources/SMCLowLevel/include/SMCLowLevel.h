#ifndef SMC_LOW_LEVEL_H
#define SMC_LOW_LEVEL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t CLSMCConnectionRef;

int32_t CLSMCOpen(CLSMCConnectionRef *connection);
void CLSMCClose(CLSMCConnectionRef connection);
int32_t CLSMCReadKey(
    CLSMCConnectionRef connection,
    const char key[4],
    uint8_t output[32],
    size_t *outputLength
);
int32_t CLSMCWriteKey(
    CLSMCConnectionRef connection,
    const char key[4],
    const uint8_t *bytes,
    size_t length
);

#ifdef __cplusplus
}
#endif

#endif
