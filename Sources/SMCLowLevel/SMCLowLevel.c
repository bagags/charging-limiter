#include "SMCLowLevel.h"

#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <string.h>

enum {
    kCLKernelIndexSMC = 2,
    kCLSMCReadBytes = 5,
    kCLSMCWriteBytes = 6,
    kCLSMCReadKeyInfo = 9,
};

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} CLSMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} CLSMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} CLSMCKeyInfoData;

typedef struct {
    uint32_t key;
    CLSMCVersion version;
    CLSMCPLimitData pLimitData;
    CLSMCKeyInfoData keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} CLSMCKeyData;

static uint32_t CLKeyCode(const char key[4]) {
    return ((uint32_t)(uint8_t)key[0] << 24) |
           ((uint32_t)(uint8_t)key[1] << 16) |
           ((uint32_t)(uint8_t)key[2] << 8) |
           (uint32_t)(uint8_t)key[3];
}

static kern_return_t CLCall(
    io_connect_t connection,
    const CLSMCKeyData *input,
    CLSMCKeyData *output
) {
    size_t outputSize = sizeof(*output);
    memset(output, 0, sizeof(*output));
    return IOConnectCallStructMethod(
        connection,
        kCLKernelIndexSMC,
        input,
        sizeof(*input),
        output,
        &outputSize
    );
}

static kern_return_t CLReadKeyInfo(
    io_connect_t connection,
    uint32_t key,
    CLSMCKeyInfoData *keyInfo
) {
    CLSMCKeyData input = {0};
    CLSMCKeyData output = {0};
    input.key = key;
    input.data8 = kCLSMCReadKeyInfo;

    kern_return_t result = CLCall(connection, &input, &output);
    if (result != KERN_SUCCESS) {
        return result;
    }
    if (output.result != 0 || output.keyInfo.dataSize == 0 || output.keyInfo.dataSize > 32) {
        return kIOReturnNotFound;
    }
    *keyInfo = output.keyInfo;
    return KERN_SUCCESS;
}

int32_t CLSMCOpen(CLSMCConnectionRef *connection) {
    if (connection == NULL) {
        return kIOReturnBadArgument;
    }

    io_service_t service = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("AppleSMC")
    );
    if (service == IO_OBJECT_NULL) {
        return kIOReturnNotFound;
    }

    io_connect_t ioConnection = IO_OBJECT_NULL;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &ioConnection);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS) {
        return result;
    }

    *connection = (CLSMCConnectionRef)ioConnection;
    return KERN_SUCCESS;
}

void CLSMCClose(CLSMCConnectionRef connection) {
    if (connection != IO_OBJECT_NULL) {
        IOServiceClose((io_connect_t)connection);
    }
}

int32_t CLSMCReadKey(
    CLSMCConnectionRef connection,
    const char key[4],
    uint8_t outputBytes[32],
    size_t *outputLength
) {
    if (connection == IO_OBJECT_NULL || key == NULL || outputBytes == NULL || outputLength == NULL) {
        return kIOReturnBadArgument;
    }

    uint32_t keyCode = CLKeyCode(key);
    CLSMCKeyInfoData keyInfo = {0};
    kern_return_t result = CLReadKeyInfo((io_connect_t)connection, keyCode, &keyInfo);
    if (result != KERN_SUCCESS) {
        return result;
    }

    CLSMCKeyData input = {0};
    CLSMCKeyData output = {0};
    input.key = keyCode;
    input.keyInfo.dataSize = keyInfo.dataSize;
    input.data8 = kCLSMCReadBytes;
    result = CLCall((io_connect_t)connection, &input, &output);
    if (result != KERN_SUCCESS) {
        return result;
    }
    if (output.result != 0) {
        return kIOReturnError;
    }

    memcpy(outputBytes, output.bytes, keyInfo.dataSize);
    *outputLength = keyInfo.dataSize;
    return KERN_SUCCESS;
}

int32_t CLSMCWriteKey(
    CLSMCConnectionRef connection,
    const char key[4],
    const uint8_t *bytes,
    size_t length
) {
    if (connection == IO_OBJECT_NULL || key == NULL || bytes == NULL || length == 0 || length > 32) {
        return kIOReturnBadArgument;
    }

    uint32_t keyCode = CLKeyCode(key);
    CLSMCKeyInfoData keyInfo = {0};
    kern_return_t result = CLReadKeyInfo((io_connect_t)connection, keyCode, &keyInfo);
    if (result != KERN_SUCCESS) {
        return result;
    }
    if (keyInfo.dataSize != length) {
        return kIOReturnBadArgument;
    }

    CLSMCKeyData input = {0};
    CLSMCKeyData output = {0};
    input.key = keyCode;
    input.keyInfo.dataSize = keyInfo.dataSize;
    input.data8 = kCLSMCWriteBytes;
    memcpy(input.bytes, bytes, length);
    result = CLCall((io_connect_t)connection, &input, &output);
    if (result != KERN_SUCCESS) {
        return result;
    }
    return output.result == 0 ? KERN_SUCCESS : kIOReturnError;
}
