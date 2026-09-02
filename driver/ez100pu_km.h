#pragma once

#include <ntddk.h>
#include <usb.h>
#include <usbdi.h>
#include <usbdlib.h>
#pragma warning(disable:4201 4324)
#include <wdf.h>
#include <wdfusb.h>
#pragma warning(push)
#pragma warning(disable:4201 4324)
#include <smclib.h>
#pragma warning(pop)
#include "protocol_core.h"

#define EZKM_TAG 'KZEC'
#define EZKM_MAX_MESSAGE 512u
#define EZKM_HEADER_SIZE 10u
#define EZKM_TIMEOUT_MS 5000u
#define EZKM_MAX_TIME_EXTENSIONS 16u

#define EZKM_STAGE_DEVICE_CREATE 1u
#define EZKM_STAGE_INTERFACE_CREATE 2u
#define EZKM_STAGE_IOCTL_QUEUE 3u
#define EZKM_STAGE_IOCTL_DISPATCH 4u
#define EZKM_STAGE_NOTIFY_QUEUE 5u
#define EZKM_STAGE_TIMER_CREATE 6u
#define EZKM_STAGE_SMCLIB_INIT 7u
#define EZKM_STAGE_USB_CREATE 20u
#define EZKM_STAGE_USB_SELECT_CONFIG 21u
#define EZKM_STAGE_USB_PIPE_LAYOUT 22u
#define EZKM_STAGE_USB_LOCK 23u
#define EZKM_STAGE_D0_REFRESH 24u
#define EZKM_STAGE_TIME_EXTENSION 25u

#define EZKM_CMD_POWER_ON 0x62u
#define EZKM_CMD_POWER_OFF 0x63u
#define EZKM_CMD_GET_SLOT_STATUS 0x65u
#define EZKM_CMD_XFR_BLOCK 0x6Fu
#define EZKM_CMD_SET_PARAMETERS 0x61u
#define EZKM_RSP_DATA_BLOCK 0x80u
#define EZKM_RSP_SLOT_STATUS 0x81u
#define EZKM_RSP_PARAMETERS 0x82u

typedef struct _READER_EXTENSION {
    WDFDEVICE Device;
    WDFUSBDEVICE UsbDevice;
    WDFUSBPIPE BulkIn;
    WDFUSBPIPE BulkOut;
    WDFUSBPIPE InterruptIn;
    WDFWAITLOCK TransportLock;
    UCHAR Sequence;
    BOOLEAN HardwarePrepared;
} READER_EXTENSION, *PEZKM_READER_EXTENSION;

typedef struct _EZKM_DEVICE_CONTEXT {
    SMARTCARD_EXTENSION SmartcardExtension;
    READER_EXTENSION Reader;
    WDFDEVICE Device;
    WDFQUEUE IoctlQueue;
    WDFQUEUE NotificationQueue;
    WDFTIMER PollTimer;
    volatile LONG PollEnabled;
    BOOLEAN SmcInitialized;
} EZKM_DEVICE_CONTEXT, *PEZKM_DEVICE_CONTEXT;

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(EZKM_DEVICE_CONTEXT, EzKmGetContext)

#define EZKM_GET_REQUEST_FROM_IRP(Irp) ((WDFREQUEST)(Irp)->Tail.Overlay.DriverContext[0])
#define EZKM_SET_REQUEST_IN_IRP(Irp, Request) ((Irp)->Tail.Overlay.DriverContext[0] = (PVOID)(Request))

DRIVER_INITIALIZE DriverEntry;
VOID EzKmLogFailure(_In_ ULONG Stage, _In_ NTSTATUS Status);
VOID EzKmLogTransportFailure(
    _In_ UCHAR Command,
    _In_ UCHAR Sequence,
    _In_ ULONG PayloadLength,
    _In_ UCHAR SlotStatus,
    _In_ UCHAR Error);
VOID EzKmLogProtocolData(
    _In_ ULONG Stage,
    _In_ ULONG Value0,
    _In_ ULONG Value1,
    _In_ ULONG Value2,
    _In_ ULONG Value3);
EVT_WDF_DRIVER_DEVICE_ADD EzKmEvtDeviceAdd;
EVT_WDF_OBJECT_CONTEXT_CLEANUP EzKmEvtCleanup;
EVT_WDF_DEVICE_PREPARE_HARDWARE EzKmEvtPrepareHardware;
EVT_WDF_DEVICE_RELEASE_HARDWARE EzKmEvtReleaseHardware;
EVT_WDF_DEVICE_D0_ENTRY EzKmEvtD0Entry;
EVT_WDF_DEVICE_D0_EXIT EzKmEvtD0Exit;
EVT_WDF_IO_QUEUE_IO_DEVICE_CONTROL EzKmEvtIoDeviceControl;
EVT_WDF_IO_QUEUE_IO_CANCELED_ON_QUEUE EzKmEvtCanceled;
EVT_WDF_FILE_CLEANUP EzKmEvtFileCleanup;
EVT_WDF_TIMER EzKmEvtPoll;

NTSTATUS EzKmRegisterSmclib(_In_ PEZKM_DEVICE_CONTEXT Context);
NTSTATUS EzKmUsbInitialize(_In_ PEZKM_DEVICE_CONTEXT Context);
NTSTATUS EzKmRefreshState(_In_ PEZKM_DEVICE_CONTEXT Context, _In_ BOOLEAN ForceWake);
NTSTATUS EzKmCcidCommand(
    _In_ PEZKM_READER_EXTENSION Reader,
    _In_ UCHAR Command,
    _In_reads_bytes_opt_(PayloadLength) const UCHAR* Payload,
    _In_ ULONG PayloadLength,
    _In_ UCHAR Parameter0,
    _In_ UCHAR ExpectedResponse,
    _Out_writes_bytes_to_(ResponseCapacity, *ResponseLength) UCHAR* Response,
    _In_ ULONG ResponseCapacity,
    _Out_ PULONG ResponseLength,
    _Out_opt_ PUCHAR SlotStatus);

NTSTATUS EzKmCardPower(_In_ PSMARTCARD_EXTENSION Extension);
NTSTATUS EzKmSetProtocol(_In_ PSMARTCARD_EXTENSION Extension);
NTSTATUS EzKmTransmit(_In_ PSMARTCARD_EXTENSION Extension);
NTSTATUS EzKmCardTracking(_In_ PSMARTCARD_EXTENSION Extension);
NTSTATUS EzKmVendorIoctl(_In_ PSMARTCARD_EXTENSION Extension);
