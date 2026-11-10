#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int kr;
    uint32_t dataSize;
    char dataType[5];
    uint8_t bytes[32];
} SMCBridgeValue;

bool SMCBridgeOpen(void);
void SMCBridgeClose(void);
bool SMCBridgeIsOpen(void);

/// Read one four-character SMC key. Returns false if the call failed or the key is absent.
bool SMCBridgeReadKey(const char *key4, SMCBridgeValue *outValue);

/// Number of published keys, or 0 on failure.
uint32_t SMCBridgeKeyCount(void);

/// Write a 4-character key name (plus NUL) at the given index.
bool SMCBridgeKeyAtIndex(uint32_t index, char outKey[5]);

/// sizeof(SMCKeyData_t), for diagnostics.
uint32_t SMCBridgeStructSize(void);

#ifdef __cplusplus
}
#endif
