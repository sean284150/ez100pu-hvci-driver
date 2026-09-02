#include "protocol_core.h"

void EzProtoPutBe32(unsigned char* Buffer, unsigned long Value)
{
    Buffer[0] = (unsigned char)(Value >> 24);
    Buffer[1] = (unsigned char)(Value >> 16);
    Buffer[2] = (unsigned char)(Value >> 8);
    Buffer[3] = (unsigned char)Value;
}

static unsigned long EzProtoGetBe32(const unsigned char* Buffer)
{
    return ((unsigned long)Buffer[0] << 24) | ((unsigned long)Buffer[1] << 16) |
        ((unsigned long)Buffer[2] << 8) | Buffer[3];
}

EZPROTO_RESULT EzProtoParseResponse(
    const unsigned char* Buffer,
    unsigned long WireLength,
    unsigned char ExpectedResponse,
    unsigned char ExpectedSequence,
    unsigned long ResponseCapacity,
    EZPROTO_RESPONSE* Result)
{
    unsigned long payloadLength;

    if (Buffer == 0 || Result == 0) return EzProtoInvalidArgument;
    Result->PayloadLength = 0;
    Result->SlotStatus = 0;
    Result->Error = 0;
    if (WireLength < EZPROTO_HEADER_SIZE) return EzProtoShortResponse;
    if (Buffer[0] != ExpectedResponse) return EzProtoWrongResponseType;
    if (Buffer[5] != 0) return EzProtoWrongSlot;
    if (Buffer[6] != ExpectedSequence) return EzProtoWrongSequence;
    Result->SlotStatus = Buffer[7];
    Result->Error = Buffer[8];
    if ((Buffer[7] & 0xC0u) == 0x80u) return EzProtoTimeExtension;
    if ((Buffer[7] & 0x40u) != 0) return EzProtoCommandFailed;
    payloadLength = EzProtoGetBe32(Buffer + 1);
    Result->PayloadLength = payloadLength;
    if (payloadLength > WireLength - EZPROTO_HEADER_SIZE) return EzProtoInvalidLength;
    if (payloadLength > ResponseCapacity) return EzProtoBufferTooSmall;
    return EzProtoOk;
}
