#include "ez100pu_km.h"

static const UCHAR EzKmVendorName[] = "EZ100PU Compatibility Project";
static const UCHAR EzKmIfdType[] = "EZ100PU compatible KMDF driver";

_Success_(return != FALSE)
static BOOLEAN
EzKmGetDataRate(
    _In_ PSMARTCARD_EXTENSION Extension,
    _In_ UCHAR Fl,
    _In_ UCHAR Dl,
    _Out_ PULONGLONG DataRate)
{
    ULONG f;
    ULONG dNumerator;
    ULONG dDivisor;

    *DataRate = 0;
    if (Fl >= 16u || Dl >= 16u ||
        Extension->CardCapabilities.ClockRateConversion == NULL ||
        Extension->CardCapabilities.BitRateAdjustment == NULL) {
        return FALSE;
    }
    f = Extension->CardCapabilities.ClockRateConversion[Fl].F;
    dNumerator = Extension->CardCapabilities.BitRateAdjustment[Dl].DNumerator;
    dDivisor = Extension->CardCapabilities.BitRateAdjustment[Dl].DDivisor;
    if (f == 0 || dNumerator == 0 || dDivisor == 0) {
        return FALSE;
    }
    *DataRate = ((ULONGLONG)Extension->ReaderCapabilities.CLKFrequency.Default * 1000u *
        dNumerator) / ((ULONGLONG)f * dDivisor);
    return TRUE;
}

static NTSTATUS
EzKmSelectFiDi(
    _In_ PSMARTCARD_EXTENSION Extension,
    _Out_ PUCHAR SelectedFl,
    _Out_ PUCHAR SelectedDl)
{
    UCHAR candidate;
    UCHAR bestDl = 0;
    ULONGLONG requestedRate;
    ULONGLONG bestRate = 0;
    ULONGLONG rate;
    ULONGLONG ceiling;

    if (Extension->CardCapabilities.Fl >= 16u ||
        Extension->CardCapabilities.Dl >= 16u ||
        !EzKmGetDataRate(
            Extension,
            Extension->CardCapabilities.Fl,
            Extension->CardCapabilities.Dl,
            &requestedRate)) {
        return STATUS_DEVICE_PROTOCOL_ERROR;
    }

    ceiling = requestedRate;
    if (ceiling > Extension->ReaderCapabilities.DataRate.Max) {
        ceiling = Extension->ReaderCapabilities.DataRate.Max;
    }
    for (candidate = 1u; candidate < 16u; candidate++) {
        if (EzKmGetDataRate(Extension, Extension->CardCapabilities.Fl, candidate, &rate) &&
            rate <= ceiling && rate > bestRate) {
            bestRate = rate;
            bestDl = candidate;
        }
    }
    if (bestDl == 0) {
        return STATUS_NOT_SUPPORTED;
    }
    *SelectedFl = Extension->CardCapabilities.Fl;
    *SelectedDl = bestDl;
    return STATUS_SUCCESS;
}

static NTSTATUS
EzKmExchangePps(
    _In_ PEZKM_READER_EXTENSION Reader,
    _In_ UCHAR ProtocolNumber,
    _In_ UCHAR FiDi)
{
    UCHAR request[4];
    UCHAR response[4];
    ULONG responseLength = 0;
    NTSTATUS status;

    request[0] = 0xFFu;
    request[1] = (UCHAR)(0x10u | (ProtocolNumber & 0x0Fu));
    request[2] = FiDi;
    request[3] = (UCHAR)(request[0] ^ request[1] ^ request[2]);

    status = EzKmCcidCommand(
        Reader, EZKM_CMD_XFR_BLOCK, request, sizeof(request), 0,
        EZKM_RSP_DATA_BLOCK, response, sizeof(response), &responseLength, NULL);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    if (responseLength != sizeof(request) ||
        RtlCompareMemory(request, response, sizeof(request)) != sizeof(request)) {
        return STATUS_DEVICE_PROTOCOL_ERROR;
    }
    return STATUS_SUCCESS;
}

NTSTATUS
EzKmRegisterSmclib(_In_ PEZKM_DEVICE_CONTEXT Context)
{
    PSMARTCARD_EXTENSION extension = &Context->SmartcardExtension;
    NTSTATUS status;

    RtlZeroMemory(extension, sizeof(*extension));
    extension->Version = SMCLIB_VERSION;
    extension->ReaderExtension = (PREADER_EXTENSION)&Context->Reader;
    extension->ReaderFunction[RDF_CARD_POWER] = EzKmCardPower;
    extension->ReaderFunction[RDF_TRANSMIT] = EzKmTransmit;
    extension->ReaderFunction[RDF_CARD_TRACKING] = EzKmCardTracking;
    extension->ReaderFunction[RDF_SET_PROTOCOL] = EzKmSetProtocol;
    extension->ReaderFunction[RDF_IOCTL_VENDOR] = EzKmVendorIoctl;

    RtlCopyMemory(extension->VendorAttr.VendorName.Buffer, EzKmVendorName, sizeof(EzKmVendorName));
    extension->VendorAttr.VendorName.Length = sizeof(EzKmVendorName);
    RtlCopyMemory(extension->VendorAttr.IfdType.Buffer, EzKmIfdType, sizeof(EzKmIfdType));
    extension->VendorAttr.IfdType.Length = sizeof(EzKmIfdType);
    extension->VendorAttr.IfdVersion.VersionMajor = 0;
    extension->VendorAttr.IfdVersion.VersionMinor = 3;
    extension->VendorAttr.IfdVersion.BuildNumber = 1;

    extension->ReaderCapabilities.SupportedProtocols = SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1;
    extension->ReaderCapabilities.ReaderType = SCARD_READER_TYPE_USB;
    extension->ReaderCapabilities.CurrentState = SCARD_UNKNOWN;
    extension->ReaderCapabilities.CLKFrequency.Default = 3580;
    extension->ReaderCapabilities.CLKFrequency.Max = 3580;
    extension->ReaderCapabilities.DataRate.Default = 9600;
    extension->ReaderCapabilities.DataRate.Max = 115200;
    extension->ReaderCapabilities.MaxIFSD = 252;
    extension->SmartcardRequest.BufferSize = MIN_BUFFER_SIZE;
    extension->SmartcardReply.BufferSize = MIN_BUFFER_SIZE;

    status = SmartcardInitialize(extension);
    if (NT_SUCCESS(status)) {
        extension->OsData->DeviceObject = WdfDeviceWdmGetDeviceObject(Context->Device);
        Context->SmcInitialized = TRUE;
    }
    return status;
}

NTSTATUS
EzKmCardPower(_In_ PSMARTCARD_EXTENSION Extension)
{
    PEZKM_READER_EXTENSION reader = (PEZKM_READER_EXTENSION)Extension->ReaderExtension;
    UCHAR atr[MAXIMUM_ATR_LENGTH + 1];
    UCHAR slotStatus = 0;
    ULONG atrLength = 0;
    NTSTATUS status;

    if (Extension->MinorIoControlCode == SCARD_POWER_DOWN) {
        status = EzKmCcidCommand(
            reader, EZKM_CMD_POWER_OFF, NULL, 0, 0, EZKM_RSP_SLOT_STATUS,
            atr, sizeof(atr), &atrLength, &slotStatus);
        if (NT_SUCCESS(status)) {
            KIRQL irql;
            KeAcquireSpinLock(&Extension->OsData->SpinLock, &irql);
            Extension->ReaderCapabilities.CurrentState = SCARD_SWALLOWED;
            KeReleaseSpinLock(&Extension->OsData->SpinLock, irql);
        }
        return status;
    }

    if (Extension->MinorIoControlCode != SCARD_COLD_RESET &&
        Extension->MinorIoControlCode != SCARD_WARM_RESET) {
        return STATUS_INVALID_PARAMETER;
    }
    if (Extension->MinorIoControlCode == SCARD_COLD_RESET) {
        (void)EzKmCcidCommand(
            reader, EZKM_CMD_POWER_OFF, NULL, 0, 0, EZKM_RSP_SLOT_STATUS,
            atr, sizeof(atr), &atrLength, &slotStatus);
    }

    atrLength = 0;
    status = EzKmCcidCommand(
        reader, EZKM_CMD_POWER_ON, NULL, 0, 0, EZKM_RSP_DATA_BLOCK,
        atr, sizeof(atr), &atrLength, &slotStatus);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    if (atrLength > 1 && atr[0] == 0 && (atr[1] == 0x3Bu || atr[1] == 0x3Fu)) {
        RtlMoveMemory(atr, atr + 1, atrLength - 1);
        atrLength--;
    }
    if (atrLength == 0 || atrLength > MAXIMUM_ATR_LENGTH) {
        return STATUS_UNRECOGNIZED_MEDIA;
    }
    if (atrLength > Extension->IoRequest.ReplyBufferLength) {
        return STATUS_BUFFER_TOO_SMALL;
    }

    RtlCopyMemory(Extension->IoRequest.ReplyBuffer, atr, atrLength);
    *Extension->IoRequest.Information = atrLength;
    RtlCopyMemory(Extension->CardCapabilities.ATR.Buffer, atr, atrLength);
    Extension->CardCapabilities.ATR.Length = (UCHAR)atrLength;
    return SmartcardUpdateCardCapabilities(Extension);
}

NTSTATUS
EzKmSetProtocol(_In_ PSMARTCARD_EXTENSION Extension)
{
    PEZKM_READER_EXTENSION reader = (PEZKM_READER_EXTENSION)Extension->ReaderExtension;
    ULONG requested = Extension->MinorIoControlCode;
    ULONG available = requested & Extension->CardCapabilities.Protocol.Supported &
        (SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1);
    ULONG selected;
    UCHAR parameters[7];
    UCHAR response[7];
    ULONG parameterLength;
    ULONG responseLength = 0;
    UCHAR protocolNumber;
    UCHAR negotiatedFl;
    UCHAR negotiatedDl;
    KIRQL irql;
    NTSTATUS status;

    if (Extension->IoRequest.ReplyBufferLength < sizeof(ULONG)) {
        return STATUS_BUFFER_TOO_SMALL;
    }

    if ((available & SCARD_PROTOCOL_T1) != 0) {
        selected = SCARD_PROTOCOL_T1;
    } else if ((available & SCARD_PROTOCOL_T0) != 0) {
        selected = SCARD_PROTOCOL_T0;
    } else {
        return STATUS_NOT_SUPPORTED;
    }


    if (Extension->ReaderCapabilities.CurrentState == SCARD_SPECIFIC &&
        Extension->CardCapabilities.Protocol.Selected == selected) {
        *(PULONG)Extension->IoRequest.ReplyBuffer = selected;
        *Extension->IoRequest.Information = sizeof(ULONG);
        return STATUS_SUCCESS;
    }

    protocolNumber = selected == SCARD_PROTOCOL_T1 ? 1u : 0u;
    status = EzKmSelectFiDi(Extension, &negotiatedFl, &negotiatedDl);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    if (negotiatedFl != 1u || negotiatedDl != 1u || protocolNumber != 0u) {
        const UCHAR fiDi = (UCHAR)((negotiatedFl << 4) | (negotiatedDl & 0x0Fu));
        status = EzKmExchangePps(reader, protocolNumber, fiDi);
        if (!NT_SUCCESS(status)) {
            EzKmLogProtocolData(41u, fiDi, protocolNumber, status,
                ((ULONG)Extension->CardCapabilities.Fl << 24) |
                ((ULONG)Extension->CardCapabilities.Dl << 16) |
                ((ULONG)negotiatedFl << 8) | negotiatedDl);
            if (status != STATUS_DEVICE_PROTOCOL_ERROR && status != STATUS_DEVICE_DATA_ERROR) {
                return status;
            }
            negotiatedFl = 1u;
            negotiatedDl = 1u;
            if (protocolNumber != 0u) {
                status = EzKmExchangePps(reader, protocolNumber, 0x11u);
                if (!NT_SUCCESS(status)) {
                    return status;
                }
            }
        }
    }

    RtlZeroMemory(parameters, sizeof(parameters));
    parameters[0] = (UCHAR)((negotiatedFl << 4) | (negotiatedDl & 0x0Fu));
    if (selected == SCARD_PROTOCOL_T1) {
        parameterLength = 7;
        parameters[1] = (UCHAR)(0x10u |
            (Extension->CardCapabilities.InversConvention ? 0x02u : 0u) |
            (Extension->CardCapabilities.T1.EDC & 0x01u));
        parameters[2] = Extension->CardCapabilities.N;
        parameters[3] = (UCHAR)((Extension->CardCapabilities.T1.BWI << 4) |
            (Extension->CardCapabilities.T1.CWI & 0x0Fu));
        parameters[4] = 0;
        parameters[5] = Extension->CardCapabilities.T1.IFSC;
        parameters[6] = 0;
    } else {
        parameterLength = 5;
        parameters[1] = Extension->CardCapabilities.InversConvention ? 0x02u : 0u;
        parameters[2] = Extension->CardCapabilities.N;
        parameters[3] = Extension->CardCapabilities.T0.WI;
        parameters[4] = 0;
    }
    status = EzKmCcidCommand(
        reader, EZKM_CMD_SET_PARAMETERS, parameters, parameterLength, protocolNumber,
        EZKM_RSP_PARAMETERS, response, sizeof(response), &responseLength, NULL);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    if (responseLength != parameterLength ||
        RtlCompareMemory(parameters, response, parameterLength) != parameterLength) {
        return STATUS_DEVICE_PROTOCOL_ERROR;
    }

    Extension->CardCapabilities.Protocol.Selected = selected;
    *(PULONG)Extension->IoRequest.ReplyBuffer = selected;
    *Extension->IoRequest.Information = sizeof(ULONG);
    KeAcquireSpinLock(&Extension->OsData->SpinLock, &irql);
    Extension->ReaderCapabilities.CurrentState = SCARD_SPECIFIC;
    KeReleaseSpinLock(&Extension->OsData->SpinLock, irql);
    return STATUS_SUCCESS;
}

static NTSTATUS
EzKmTransmitProtocol(_In_ PSMARTCARD_EXTENSION Extension, _In_ BOOLEAN T1)
{
    PEZKM_READER_EXTENSION reader = (PEZKM_READER_EXTENSION)Extension->ReaderExtension;
    NTSTATUS status;
    NTSTATUS transportStatus;

    do {
        Extension->SmartcardRequest.BufferLength = 0;
        if (T1) {
            Extension->T1.NAD = 0;
            status = SmartcardT1Request(Extension);
        } else {
            status = SmartcardT0Request(Extension);
        }
        if (!NT_SUCCESS(status)) {
            break;
        }

        Extension->SmartcardReply.BufferLength = 0;
        transportStatus = EzKmCcidCommand(
            reader,
            EZKM_CMD_XFR_BLOCK,
            Extension->SmartcardRequest.Buffer,
            Extension->SmartcardRequest.BufferLength,
            0,
            EZKM_RSP_DATA_BLOCK,
            Extension->SmartcardReply.Buffer,
            Extension->SmartcardReply.BufferSize,
            &Extension->SmartcardReply.BufferLength,
            NULL);
        if (T1 && !NT_SUCCESS(transportStatus) &&
            Extension->SmartcardRequest.BufferLength >= 3u) {
            EzKmLogProtocolData(
                42u,
                1u,
                Extension->SmartcardRequest.BufferLength,
                Extension->CardCapabilities.T1.EDC,
                transportStatus);
        }
        if (T1) {
            status = SmartcardT1Reply(Extension);
            if (NT_SUCCESS(status) && !NT_SUCCESS(transportStatus)) {
                status = transportStatus;
            }
        } else {
            if (!NT_SUCCESS(transportStatus)) {
                status = transportStatus;
                break;
            }
            status = SmartcardT0Reply(Extension);
        }
    } while (status == STATUS_MORE_PROCESSING_REQUIRED);

    return status;
}

NTSTATUS
EzKmTransmit(_In_ PSMARTCARD_EXTENSION Extension)
{
    if (Extension->CardCapabilities.Protocol.Selected == SCARD_PROTOCOL_T1) {
        return EzKmTransmitProtocol(Extension, TRUE);
    }
    if (Extension->CardCapabilities.Protocol.Selected == SCARD_PROTOCOL_T0) {
        return EzKmTransmitProtocol(Extension, FALSE);
    }
    return STATUS_INVALID_DEVICE_STATE;
}

NTSTATUS
EzKmCardTracking(_In_ PSMARTCARD_EXTENSION Extension)
{
    WDFREQUEST request = EZKM_GET_REQUEST_FROM_IRP(Extension->OsData->NotificationIrp);
    PEZKM_DEVICE_CONTEXT context = EzKmGetContext(
        WdfIoQueueGetDevice(WdfRequestGetIoQueue(request)));
    NTSTATUS status;

    IoMarkIrpPending(Extension->OsData->NotificationIrp);
    IoSkipCurrentIrpStackLocation(Extension->OsData->NotificationIrp);
    status = WdfRequestForwardToIoQueue(request, context->NotificationQueue);
    if (!NT_SUCCESS(status)) {
        InterlockedExchangePointer(&Extension->OsData->NotificationIrp, NULL);
        WdfRequestComplete(request, status);
    }
    return STATUS_PENDING;
}

NTSTATUS
EzKmVendorIoctl(_In_ PSMARTCARD_EXTENSION Extension)
{
    Extension->OsData->CurrentIrp->IoStatus.Information = 0;
    return STATUS_INVALID_DEVICE_REQUEST;
}
