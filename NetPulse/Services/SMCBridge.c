#include "SMCBridge.h"

#include <IOKit/IOKitLib.h>
#include <string.h>

#define KERNEL_INDEX_SMC        2
#define SMC_CMD_READ_BYTES      5
#define SMC_CMD_READ_INDEX      8
#define SMC_CMD_READ_KEYINFO    9

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    UInt16 release;
} SMCKeyData_vers_t;

typedef struct {
    UInt16 version;
    UInt16 length;
    UInt32 cpuPLimit;
    UInt32 gpuPLimit;
    UInt32 memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    UInt32 dataSize;
    UInt32 dataType;
    char dataAttributes;
} SMCKeyData_keyInfo_t;

typedef char SMCBytes_t[32];

typedef struct {
    UInt32 key;
    SMCKeyData_vers_t vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t keyInfo;
    char result;
    char status;
    char data8;
    UInt32 data32;
    SMCBytes_t bytes;
} SMCKeyData_t;

static io_connect_t gConn = IO_OBJECT_NULL;

static UInt32 pack_key(const char *str) {
    UInt32 total = 0;
    for (int i = 0; i < 4; i++) {
        unsigned char ch = (unsigned char)(str[i] ? str[i] : ' ');
        total += (UInt32)ch << (8 * (3 - i));
    }
    return total;
}

static void unpack_type(char out[5], UInt32 val) {
    out[0] = (char)((val >> 24) & 0xFF);
    out[1] = (char)((val >> 16) & 0xFF);
    out[2] = (char)((val >> 8) & 0xFF);
    out[3] = (char)(val & 0xFF);
    out[4] = '\0';
}

static mach_port_t main_port(void) {
    return kIOMainPortDefault;
}

static kern_return_t smc_call(SMCKeyData_t *input, SMCKeyData_t *output) {
    size_t inSize = sizeof(SMCKeyData_t);
    size_t outSize = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(gConn, KERNEL_INDEX_SMC, input, inSize, output, &outSize);
}

bool SMCBridgeOpen(void) {
    if (gConn != IO_OBJECT_NULL) {
        return true;
    }

    CFMutableDictionaryRef matching = IOServiceMatching("AppleSMC");
    if (matching == NULL) {
        return false;
    }

    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(main_port(), matching, &iterator);
    if (kr != KERN_SUCCESS) {
        return false;
    }

    io_object_t device = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (device == 0) {
        return false;
    }

    kr = IOServiceOpen(device, mach_task_self(), 0, &gConn);
    IOObjectRelease(device);
    if (kr != KERN_SUCCESS) {
        gConn = IO_OBJECT_NULL;
        return false;
    }
    return true;
}

void SMCBridgeClose(void) {
    if (gConn != IO_OBJECT_NULL) {
        IOServiceClose(gConn);
        gConn = IO_OBJECT_NULL;
    }
}

bool SMCBridgeIsOpen(void) {
    return gConn != IO_OBJECT_NULL;
}

uint32_t SMCBridgeStructSize(void) {
    return (uint32_t)sizeof(SMCKeyData_t);
}

bool SMCBridgeReadKey(const char *key4, SMCBridgeValue *outValue) {
    if (outValue == NULL || key4 == NULL) {
        return false;
    }
    memset(outValue, 0, sizeof(*outValue));
    if (!SMCBridgeOpen()) {
        outValue->kr = KERN_FAILURE;
        return false;
    }

    SMCKeyData_t input;
    SMCKeyData_t output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));

    input.key = pack_key(key4);
    input.data8 = SMC_CMD_READ_KEYINFO;
    kern_return_t kr = smc_call(&input, &output);
    outValue->kr = (int)kr;
    if (kr != KERN_SUCCESS || output.keyInfo.dataSize == 0 || output.keyInfo.dataSize > 32) {
        return false;
    }

    outValue->dataSize = output.keyInfo.dataSize;
    unpack_type(outValue->dataType, output.keyInfo.dataType);

    input.keyInfo.dataSize = output.keyInfo.dataSize;
    input.data8 = SMC_CMD_READ_BYTES;
    memset(&output, 0, sizeof(output));
    kr = smc_call(&input, &output);
    outValue->kr = (int)kr;
    if (kr != KERN_SUCCESS) {
        return false;
    }
    memcpy(outValue->bytes, output.bytes, sizeof(output.bytes));
    return true;
}

uint32_t SMCBridgeKeyCount(void) {
    SMCBridgeValue value;
    if (!SMCBridgeReadKey("#KEY", &value)) {
        return 0;
    }
    if (value.dataSize >= 4) {
        return ((uint32_t)value.bytes[0] << 24) | ((uint32_t)value.bytes[1] << 16) |
               ((uint32_t)value.bytes[2] << 8) | (uint32_t)value.bytes[3];
    }
    if (value.dataSize == 1) {
        return value.bytes[0];
    }
    return 0;
}

bool SMCBridgeKeyAtIndex(uint32_t index, char outKey[5]) {
    if (outKey == NULL) {
        return false;
    }
    memset(outKey, 0, 5);
    if (!SMCBridgeOpen()) {
        return false;
    }

    SMCKeyData_t input;
    SMCKeyData_t output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.data8 = SMC_CMD_READ_INDEX;
    input.data32 = index;
    if (smc_call(&input, &output) != KERN_SUCCESS || output.key == 0) {
        return false;
    }
    unpack_type(outKey, output.key);
    return outKey[0] != '\0';
}
