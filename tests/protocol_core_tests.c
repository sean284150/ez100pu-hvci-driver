#include <stdio.h>
#include <string.h>
#include "../driver/protocol_core.h"

static int failures;
#define CHECK(expression) do { if (!(expression)) { \
    printf("FAIL line %d: %s\n", __LINE__, #expression); failures++; } } while (0)

int main(void)
{
    unsigned char response[64];
    EZPROTO_RESPONSE parsed;
    unsigned long length;

    memset(response, 0, sizeof(response));
    response[0] = 0x80;
    response[6] = 7;
    EzProtoPutBe32(response + 1, 2);
    response[10] = 0x90;
    response[11] = 0x00;
    CHECK(EzProtoParseResponse(response, 12, 0x80, 7, 54, &parsed) == EzProtoOk);
    CHECK(parsed.PayloadLength == 2);

    for (length = 0; length < EZPROTO_HEADER_SIZE; length++) {
        CHECK(EzProtoParseResponse(response, length, 0x80, 7, 54, &parsed) == EzProtoShortResponse);
    }
    response[0] = 0x81;
    CHECK(EzProtoParseResponse(response, 12, 0x80, 7, 54, &parsed) == EzProtoWrongResponseType);
    response[0] = 0x80;
    response[6] = 8;
    CHECK(EzProtoParseResponse(response, 12, 0x80, 7, 54, &parsed) == EzProtoWrongSequence);
    response[6] = 7;
    response[7] = 0x80;
    CHECK(EzProtoParseResponse(response, 10, 0x80, 7, 54, &parsed) == EzProtoTimeExtension);
    response[7] = 0x40;
    CHECK(EzProtoParseResponse(response, 10, 0x80, 7, 54, &parsed) == EzProtoCommandFailed);
    response[7] = 0;
    EzProtoPutBe32(response + 1, 55);
    CHECK(EzProtoParseResponse(response, 64, 0x80, 7, 54, &parsed) == EzProtoInvalidLength);
    EzProtoPutBe32(response + 1, 4);
    CHECK(EzProtoParseResponse(response, 14, 0x80, 7, 3, &parsed) == EzProtoBufferTooSmall);
    CHECK(EzProtoParseResponse(0, 0, 0, 0, 0, &parsed) == EzProtoInvalidArgument);

    if (failures) return 1;
    puts("protocol_core tests passed");
    return 0;
}
