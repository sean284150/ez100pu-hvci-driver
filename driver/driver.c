#include "ez100pu_km.h"

VOID
EzKmLogFailure(_In_ ULONG Stage, _In_ NTSTATUS Status)
{
    PIO_ERROR_LOG_PACKET packet;

    KdPrintEx((DPFLTR_IHVDRIVER_ID, DPFLTR_ERROR_LEVEL,
        "EZ100PU: initialization stage %lu failed: 0x%08X\n", Stage, Status));
    packet = IoAllocateErrorLogEntry(
        WdfDriverWdmGetDriverObject(WdfGetDriver()), sizeof(IO_ERROR_LOG_PACKET));
    if (packet != NULL) {
        RtlZeroMemory(packet, sizeof(IO_ERROR_LOG_PACKET));
        packet->ErrorCode = 0xE1000000u | Stage;
        packet->FinalStatus = Status;
        packet->UniqueErrorValue = Stage;
        packet->MajorFunctionCode = IRP_MJ_PNP;
        IoWriteErrorLogEntry(packet);
    }
}

VOID
EzKmLogTransportFailure(
    _In_ UCHAR Command,
    _In_ UCHAR Sequence,
    _In_ ULONG PayloadLength,
    _In_ UCHAR SlotStatus,
    _In_ UCHAR Error)
{
    const UCHAR packetSize = (UCHAR)(FIELD_OFFSET(IO_ERROR_LOG_PACKET, DumpData) +
        (4u * sizeof(ULONG)));
    PIO_ERROR_LOG_PACKET packet = IoAllocateErrorLogEntry(
        WdfDriverWdmGetDriverObject(WdfGetDriver()), packetSize);

    if (packet != NULL) {
        RtlZeroMemory(packet, packetSize);
        packet->ErrorCode = 0xE1000028u;
        packet->FinalStatus = STATUS_DEVICE_PROTOCOL_ERROR;
        packet->UniqueErrorValue = 40u;
        packet->MajorFunctionCode = IRP_MJ_DEVICE_CONTROL;
        packet->DumpDataSize = 4u * sizeof(ULONG);
        packet->DumpData[0] = Command;
        packet->DumpData[1] = Sequence;
        packet->DumpData[2] = PayloadLength;
        packet->DumpData[3] = ((ULONG)Error << 8) | SlotStatus;
        IoWriteErrorLogEntry(packet);
    }
}

VOID
EzKmLogProtocolData(
    _In_ ULONG Stage,
    _In_ ULONG Value0,
    _In_ ULONG Value1,
    _In_ ULONG Value2,
    _In_ ULONG Value3)
{
    const UCHAR packetSize = (UCHAR)(FIELD_OFFSET(IO_ERROR_LOG_PACKET, DumpData) +
        (4u * sizeof(ULONG)));
    PIO_ERROR_LOG_PACKET packet = IoAllocateErrorLogEntry(
        WdfDriverWdmGetDriverObject(WdfGetDriver()), packetSize);

    if (packet != NULL) {
        RtlZeroMemory(packet, packetSize);
        packet->ErrorCode = 0xE1000000u | Stage;
        packet->FinalStatus = STATUS_SUCCESS;
        packet->UniqueErrorValue = Stage;
        packet->MajorFunctionCode = IRP_MJ_DEVICE_CONTROL;
        packet->DumpDataSize = 4u * sizeof(ULONG);
        packet->DumpData[0] = Value0;
        packet->DumpData[1] = Value1;
        packet->DumpData[2] = Value2;
        packet->DumpData[3] = Value3;
        IoWriteErrorLogEntry(packet);
    }
}

NTSTATUS
DriverEntry(
    _In_ PDRIVER_OBJECT DriverObject,
    _In_ PUNICODE_STRING RegistryPath)
{
    WDF_DRIVER_CONFIG config;
    WDF_DRIVER_CONFIG_INIT(&config, EzKmEvtDeviceAdd);
    return WdfDriverCreate(DriverObject, RegistryPath, WDF_NO_OBJECT_ATTRIBUTES, &config, WDF_NO_HANDLE);
}
