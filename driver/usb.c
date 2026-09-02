#include "ez100pu_km.h"

static VOID
EzKmRecoverTransport(_In_ PEZKM_READER_EXTENSION Reader)
{
    if (Reader->BulkOut != NULL) {
        (void)WdfUsbTargetPipeAbortSynchronously(Reader->BulkOut, WDF_NO_HANDLE, NULL);
        (void)WdfUsbTargetPipeResetSynchronously(Reader->BulkOut, WDF_NO_HANDLE, NULL);
    }
    if (Reader->BulkIn != NULL) {
        (void)WdfUsbTargetPipeAbortSynchronously(Reader->BulkIn, WDF_NO_HANDLE, NULL);
        (void)WdfUsbTargetPipeResetSynchronously(Reader->BulkIn, WDF_NO_HANDLE, NULL);
    }
}

static NTSTATUS
EzKmPipeWrite(
    _In_ WDFUSBPIPE Pipe,
    _In_reads_bytes_(Length) UCHAR* Buffer,
    _In_ ULONG Length)
{
    WDF_MEMORY_DESCRIPTOR descriptor;
    WDF_REQUEST_SEND_OPTIONS options;
    ULONG transferred = 0;
    NTSTATUS status;

    WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&descriptor, Buffer, Length);
    WDF_REQUEST_SEND_OPTIONS_INIT(&options, WDF_REQUEST_SEND_OPTION_TIMEOUT);
    WDF_REQUEST_SEND_OPTIONS_SET_TIMEOUT(&options, WDF_REL_TIMEOUT_IN_MS(EZKM_TIMEOUT_MS));
    status = WdfUsbTargetPipeWriteSynchronously(Pipe, WDF_NO_HANDLE, &options, &descriptor, &transferred);
    if (!NT_SUCCESS(status) || transferred != Length) {
        (void)WdfUsbTargetPipeResetSynchronously(Pipe, WDF_NO_HANDLE, NULL);
        return NT_SUCCESS(status) ? STATUS_DEVICE_DATA_ERROR : status;
    }
    return STATUS_SUCCESS;
}

static NTSTATUS
EzKmPipeRead(
    _In_ WDFUSBPIPE Pipe,
    _Out_writes_bytes_to_(Capacity, *Length) UCHAR* Buffer,
    _In_ ULONG Capacity,
    _Out_ PULONG Length)
{
    WDF_MEMORY_DESCRIPTOR descriptor;
    WDF_REQUEST_SEND_OPTIONS options;
    NTSTATUS status;

    WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&descriptor, Buffer, Capacity);
    WDF_REQUEST_SEND_OPTIONS_INIT(&options, WDF_REQUEST_SEND_OPTION_TIMEOUT);
    WDF_REQUEST_SEND_OPTIONS_SET_TIMEOUT(&options, WDF_REL_TIMEOUT_IN_MS(EZKM_TIMEOUT_MS));
    status = WdfUsbTargetPipeReadSynchronously(Pipe, WDF_NO_HANDLE, &options, &descriptor, Length);
    if (!NT_SUCCESS(status)) {
        (void)WdfUsbTargetPipeResetSynchronously(Pipe, WDF_NO_HANDLE, NULL);
    }
    return status;
}

NTSTATUS
EzKmUsbInitialize(_In_ PEZKM_DEVICE_CONTEXT Context)
{
    WDF_USB_DEVICE_SELECT_CONFIG_PARAMS selectConfig;
    WDFUSBINTERFACE usbInterface;
    UCHAR index;
    NTSTATUS status;

    status = WdfUsbTargetDeviceCreate(
        Context->Device, WDF_NO_OBJECT_ATTRIBUTES, &Context->Reader.UsbDevice);
    if (!NT_SUCCESS(status)) {
        EzKmLogFailure(EZKM_STAGE_USB_CREATE, status);
        return status;
    }
    WDF_USB_DEVICE_SELECT_CONFIG_PARAMS_INIT_SINGLE_INTERFACE(&selectConfig);
    status = WdfUsbTargetDeviceSelectConfig(
        Context->Reader.UsbDevice, WDF_NO_OBJECT_ATTRIBUTES, &selectConfig);
    if (!NT_SUCCESS(status)) {
        EzKmLogFailure(EZKM_STAGE_USB_SELECT_CONFIG, status);
        return status;
    }
    if (selectConfig.Types.SingleInterface.NumberConfiguredPipes != 3) {
        EzKmLogFailure(EZKM_STAGE_USB_PIPE_LAYOUT, STATUS_DEVICE_CONFIGURATION_ERROR);
        return STATUS_DEVICE_CONFIGURATION_ERROR;
    }

    usbInterface = selectConfig.Types.SingleInterface.ConfiguredUsbInterface;
    for (index = 0; index < 3; index++) {
        WDF_USB_PIPE_INFORMATION info;
        WDFUSBPIPE pipe;
        WDF_USB_PIPE_INFORMATION_INIT(&info);
        pipe = WdfUsbInterfaceGetConfiguredPipe(usbInterface, index, &info);
        if (info.EndpointAddress == 0x01u && info.PipeType == WdfUsbPipeTypeBulk) {
            Context->Reader.BulkOut = pipe;
        } else if (info.EndpointAddress == 0x82u && info.PipeType == WdfUsbPipeTypeBulk) {
            Context->Reader.BulkIn = pipe;
        } else if (info.EndpointAddress == 0x83u && info.PipeType == WdfUsbPipeTypeInterrupt) {
            Context->Reader.InterruptIn = pipe;
        }
    }
    if (Context->Reader.BulkOut == NULL || Context->Reader.BulkIn == NULL ||
        Context->Reader.InterruptIn == NULL) {
        EzKmLogFailure(EZKM_STAGE_USB_PIPE_LAYOUT, STATUS_DEVICE_CONFIGURATION_ERROR);
        return STATUS_DEVICE_CONFIGURATION_ERROR;
    }
    WdfUsbTargetPipeSetNoMaximumPacketSizeCheck(Context->Reader.BulkIn);
    WdfUsbTargetPipeSetNoMaximumPacketSizeCheck(Context->Reader.BulkOut);

    Context->Reader.Sequence = 0;
    Context->Reader.HardwarePrepared = TRUE;
    return STATUS_SUCCESS;
}

NTSTATUS
EzKmCcidCommand(
    _In_ PEZKM_READER_EXTENSION Reader,
    _In_ UCHAR Command,
    _In_reads_bytes_opt_(PayloadLength) const UCHAR* Payload,
    _In_ ULONG PayloadLength,
    _In_ UCHAR Parameter0,
    _In_ UCHAR ExpectedResponse,
    _Out_writes_bytes_to_(ResponseCapacity, *ResponseLength) UCHAR* Response,
    _In_ ULONG ResponseCapacity,
    _Out_ PULONG ResponseLength,
    _Out_opt_ PUCHAR SlotStatus)
{
    UCHAR commandBuffer[EZKM_MAX_MESSAGE];
    UCHAR responseBuffer[EZKM_MAX_MESSAGE];
    UCHAR sequence;
    ULONG wireLength;
    ULONG payloadOnWire;
    ULONG timeExtensions = 0;
    EZPROTO_RESPONSE parsed;
    EZPROTO_RESULT parseResult;
    NTSTATUS status;

    if (PayloadLength > EZKM_MAX_MESSAGE - EZKM_HEADER_SIZE) {
        return STATUS_INVALID_BUFFER_SIZE;
    }
    if (ResponseLength == NULL ||
        (PayloadLength != 0 && Payload == NULL) ||
        (ResponseCapacity != 0 && Response == NULL)) {
        return STATUS_INVALID_PARAMETER;
    }
    if (!Reader->HardwarePrepared || Reader->BulkIn == NULL || Reader->BulkOut == NULL) {
        return STATUS_DEVICE_NOT_READY;
    }
    *ResponseLength = 0;
    if (SlotStatus != NULL) {
        *SlotStatus = 0;
    }
    WdfWaitLockAcquire(Reader->TransportLock, NULL);
    sequence = Reader->Sequence++;
    RtlZeroMemory(commandBuffer, EZKM_HEADER_SIZE);
    commandBuffer[0] = Command;
    EzProtoPutBe32(&commandBuffer[1], PayloadLength);
    commandBuffer[6] = sequence;
    commandBuffer[7] = Parameter0;
    if (PayloadLength != 0 && Payload != NULL) {
        RtlCopyMemory(commandBuffer + EZKM_HEADER_SIZE, Payload, PayloadLength);
    }

    status = EzKmPipeWrite(Reader->BulkOut, commandBuffer, EZKM_HEADER_SIZE + PayloadLength);
    if (!NT_SUCCESS(status)) {
        WdfWaitLockRelease(Reader->TransportLock);
        return status;
    }

    for (;;) {
        RtlZeroMemory(responseBuffer, sizeof(responseBuffer));
        status = EzKmPipeRead(Reader->BulkIn, responseBuffer, sizeof(responseBuffer), &wireLength);
        if (!NT_SUCCESS(status)) {
            break;
        }
        parseResult = EzProtoParseResponse(
            responseBuffer, wireLength, ExpectedResponse, sequence, ResponseCapacity, &parsed);
        if (parseResult == EzProtoTimeExtension) {
            if (timeExtensions >= EZKM_MAX_TIME_EXTENSIONS) {
                EzKmLogProtocolData(
                    EZKM_STAGE_TIME_EXTENSION, Command, sequence, timeExtensions, 0);
                EzKmRecoverTransport(Reader);
                status = STATUS_IO_TIMEOUT;
                break;
            }
            timeExtensions++;
            continue;
        }
        if (parseResult == EzProtoCommandFailed) {
            if (Command == EZKM_CMD_XFR_BLOCK) {
                EzKmLogTransportFailure(
                    Command, sequence, PayloadLength, parsed.SlotStatus, parsed.Error);
            }
            status = parsed.Error == 0xFEu && (parsed.SlotStatus & 0x03u) == 2u ?
                STATUS_NO_MEDIA : STATUS_DEVICE_DATA_ERROR;
            break;
        }
        if (parseResult == EzProtoBufferTooSmall) {
            *ResponseLength = parsed.PayloadLength;
            status = STATUS_BUFFER_TOO_SMALL;
            break;
        }
        if (parseResult != EzProtoOk) {
            status = STATUS_DEVICE_PROTOCOL_ERROR;
            break;
        }

        payloadOnWire = parsed.PayloadLength;
        if (SlotStatus != NULL) {
            *SlotStatus = parsed.SlotStatus;
        }
        if (payloadOnWire != 0 && Response != NULL && payloadOnWire <= ResponseCapacity) {
            RtlCopyMemory(Response, responseBuffer + EZKM_HEADER_SIZE, payloadOnWire);
        }
        *ResponseLength = payloadOnWire;
        status = STATUS_SUCCESS;
        break;
    }
    WdfWaitLockRelease(Reader->TransportLock);
    return status;
}

NTSTATUS
EzKmRefreshState(_In_ PEZKM_DEVICE_CONTEXT Context, _In_ BOOLEAN ForceWake)
{
    UCHAR response[1];
    UCHAR slotStatus = 0;
    ULONG responseLength = 0;
    ULONG oldState;
    ULONG newState;
    KIRQL irql;
    NTSTATUS status;
    PIRP notificationIrp;
    WDFREQUEST request;

    if (Context->Reader.BulkIn == NULL) {
        return STATUS_DEVICE_NOT_READY;
    }
    status = EzKmCcidCommand(
        &Context->Reader, EZKM_CMD_GET_SLOT_STATUS, NULL, 0, 0, EZKM_RSP_SLOT_STATUS,
        response, sizeof(response), &responseLength, &slotStatus);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    KeAcquireSpinLock(&Context->SmartcardExtension.OsData->SpinLock, &irql);
    oldState = Context->SmartcardExtension.ReaderCapabilities.CurrentState > SCARD_ABSENT ?
        SCARD_PRESENT : SCARD_ABSENT;
    newState = (slotStatus & 0x03u) == 2u ? SCARD_ABSENT : SCARD_PRESENT;
    if (newState == SCARD_ABSENT) {
        Context->SmartcardExtension.ReaderCapabilities.CurrentState = SCARD_ABSENT;
    } else if (Context->SmartcardExtension.ReaderCapabilities.CurrentState <= SCARD_ABSENT) {
        Context->SmartcardExtension.ReaderCapabilities.CurrentState = SCARD_PRESENT;
    }
    notificationIrp = NULL;
    if (Context->SmartcardExtension.OsData->NotificationIrp != NULL &&
        (ForceWake || oldState != newState)) {
        notificationIrp = InterlockedExchangePointer(
            &Context->SmartcardExtension.OsData->NotificationIrp, NULL);
    }
    KeReleaseSpinLock(&Context->SmartcardExtension.OsData->SpinLock, irql);

    if (notificationIrp != NULL && NT_SUCCESS(
        WdfIoQueueRetrieveNextRequest(Context->NotificationQueue, &request))) {
        WdfRequestCompleteWithInformation(request, STATUS_SUCCESS, 0);
    }
    return STATUS_SUCCESS;
}
