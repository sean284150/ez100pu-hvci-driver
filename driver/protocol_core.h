#pragma once

#define EZPROTO_HEADER_SIZE 10u

typedef enum _EZPROTO_RESULT {
    EzProtoOk = 0,
    EzProtoInvalidArgument,
    EzProtoShortResponse,
    EzProtoWrongResponseType,
    EzProtoWrongSlot,
    EzProtoWrongSequence,
    EzProtoTimeExtension,
    EzProtoCommandFailed,
    EzProtoInvalidLength,
    EzProtoBufferTooSmall
} EZPROTO_RESULT;

typedef struct _EZPROTO_RESPONSE {
    unsigned long PayloadLength;
    unsigned char SlotStatus;
    unsigned char Error;
} EZPROTO_RESPONSE;

void EzProtoPutBe32(unsigned char* Buffer, unsigned long Value);
EZPROTO_RESULT EzProtoParseResponse(
    const unsigned char* Buffer,
    unsigned long WireLength,
    unsigned char ExpectedResponse,
    unsigned char ExpectedSequence,
    unsigned long ResponseCapacity,
    EZPROTO_RESPONSE* Result);
