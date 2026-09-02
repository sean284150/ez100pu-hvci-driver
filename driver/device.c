#include "ez100pu_km.h"

NTSTATUS
EzKmEvtDeviceAdd(
    _In_ WDFDRIVER Driver,
    _Inout_ PWDFDEVICE_INIT DeviceInit)
{
    WDF_PNPPOWER_EVENT_CALLBACKS power;
    WDF_FILEOBJECT_CONFIG fileConfig;
    WDF_OBJECT_ATTRIBUTES attributes;
    WDF_IO_QUEUE_CONFIG queueConfig;
    WDF_TIMER_CONFIG timerConfig;
    WDFDEVICE device;
    PEZKM_DEVICE_CONTEXT context;
    NTSTATUS status;

    UNREFERENCED_PARAMETER(Driver);

    WdfDeviceInitSetDeviceType(DeviceInit, FILE_DEVICE_SMARTCARD);
    WdfDeviceInitSetExclusive(DeviceInit, TRUE);
    WdfDeviceInitSetIoType(DeviceInit, WdfDeviceIoBuffered);

    WDF_PNPPOWER_EVENT_CALLBACKS_INIT(&power);
    power.EvtDevicePrepareHardware = EzKmEvtPrepareHardware;
    power.EvtDeviceReleaseHardware = EzKmEvtReleaseHardware;
    power.EvtDeviceD0Entry = EzKmEvtD0Entry;
    power.EvtDeviceD0Exit = EzKmEvtD0Exit;
    WdfDeviceInitSetPnpPowerEventCallbacks(DeviceInit, &power);

    WDF_FILEOBJECT_CONFIG_INIT(
        &fileConfig, WDF_NO_EVENT_CALLBACK, WDF_NO_EVENT_CALLBACK, EzKmEvtFileCleanup);
    WdfDeviceInitSetFileObjectConfig(DeviceInit, &fileConfig, WDF_NO_OBJECT_ATTRIBUTES);

    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&attributes, EZKM_DEVICE_CONTEXT);
    attributes.EvtCleanupCallback = EzKmEvtCleanup;
    attributes.ExecutionLevel = WdfExecutionLevelPassive;
    status = WdfDeviceCreate(&DeviceInit, &attributes, &device);
    if (!NT_SUCCESS(status)) {
        EzKmLogFailure(EZKM_STAGE_DEVICE_CREATE, status);
        return status;
    }

    context = EzKmGetContext(device);
    RtlZeroMemory(context, sizeof(*context));
    context->Device = device;
    context->Reader.Device = device;

    WdfDeviceWdmGetDeviceObject(device)->StackSize++;
    status = WdfDeviceCreateDeviceInterface(device, &SmartCardReaderGuid, NULL);
    if (!NT_SUCCESS(status)) {
        EzKmLogFailure(EZKM_STAGE_INTERFACE_CREATE, status);
        return status;
    }

    /* smclib keeps one CurrentIrp and shared request/reply state per reader. */
    WDF_IO_QUEUE_CONFIG_INIT(&queueConfig, WdfIoQueueDispatchSequential);
    queueConfig.EvtIoDeviceControl = EzKmEvtIoDeviceControl;
    status = WdfIoQueueCreate(device, &queueConfig, WDF_NO_OBJECT_ATTRIBUTES, &context->IoctlQueue);
    if (!NT_SUCCESS(status)) {
        EzKmLogFailure(EZKM_STAGE_IOCTL_QUEUE, status);
        return status;
    }
    status = WdfDeviceConfigureRequestDispatching(device, context->IoctlQueue, WdfRequestTypeDeviceControl);
    if (!NT_SUCCESS(status)) {
        EzKmLogFailure(EZKM_STAGE_IOCTL_DISPATCH, status);
        return status;
    }

    WDF_IO_QUEUE_CONFIG_INIT(&queueConfig, WdfIoQueueDispatchManual);
    queueConfig.PowerManaged = WdfFalse;
    queueConfig.EvtIoCanceledOnQueue = EzKmEvtCanceled;
    status = WdfIoQueueCreate(device, &queueConfig, WDF_NO_OBJECT_ATTRIBUTES, &context->NotificationQueue);
    if (!NT_SUCCESS(status)) {
        EzKmLogFailure(EZKM_STAGE_NOTIFY_QUEUE, status);
        return status;
    }

    WDF_TIMER_CONFIG_INIT(&timerConfig, EzKmEvtPoll);
    timerConfig.AutomaticSerialization = FALSE;
    WDF_OBJECT_ATTRIBUTES_INIT(&attributes);
    attributes.ParentObject = device;
    attributes.ExecutionLevel = WdfExecutionLevelPassive;
    status = WdfTimerCreate(&timerConfig, &attributes, &context->PollTimer);
    if (!NT_SUCCESS(status)) {
        EzKmLogFailure(EZKM_STAGE_TIMER_CREATE, status);
        return status;
    }
    WDF_OBJECT_ATTRIBUTES_INIT(&attributes);
    attributes.ParentObject = device;
    status = WdfWaitLockCreate(&attributes, &context->Reader.TransportLock);
    if (!NT_SUCCESS(status)) {
        EzKmLogFailure(EZKM_STAGE_USB_LOCK, status);
        return status;
    }

    status = EzKmRegisterSmclib(context);
    if (!NT_SUCCESS(status)) {
        EzKmLogFailure(EZKM_STAGE_SMCLIB_INIT, status);
    }
    return status;
}

NTSTATUS
EzKmEvtReleaseHardware(
    _In_ WDFDEVICE Device,
    _In_ WDFCMRESLIST ResourcesTranslated)
{
    PEZKM_DEVICE_CONTEXT context = EzKmGetContext(Device);

    UNREFERENCED_PARAMETER(ResourcesTranslated);
    InterlockedExchange(&context->PollEnabled, 0);
    WdfTimerStop(context->PollTimer, TRUE);
    context->Reader.HardwarePrepared = FALSE;
    context->Reader.BulkIn = NULL;
    context->Reader.BulkOut = NULL;
    context->Reader.InterruptIn = NULL;
    context->Reader.Sequence = 0;
    if (context->Reader.UsbDevice != NULL) {
        WdfObjectDelete(context->Reader.UsbDevice);
        context->Reader.UsbDevice = NULL;
    }
    return STATUS_SUCCESS;
}

VOID
EzKmEvtCleanup(_In_ WDFOBJECT Object)
{
    PEZKM_DEVICE_CONTEXT context = EzKmGetContext((WDFDEVICE)Object);
    if (context->SmcInitialized) {
        SmartcardExit(&context->SmartcardExtension);
        context->SmcInitialized = FALSE;
    }
}

NTSTATUS
EzKmEvtPrepareHardware(
    _In_ WDFDEVICE Device,
    _In_ WDFCMRESLIST ResourcesRaw,
    _In_ WDFCMRESLIST ResourcesTranslated)
{
    UNREFERENCED_PARAMETER(ResourcesRaw);
    UNREFERENCED_PARAMETER(ResourcesTranslated);
    return EzKmUsbInitialize(EzKmGetContext(Device));
}

NTSTATUS
EzKmEvtD0Entry(_In_ WDFDEVICE Device, _In_ WDF_POWER_DEVICE_STATE PreviousState)
{
    PEZKM_DEVICE_CONTEXT context = EzKmGetContext(Device);
    NTSTATUS status;
    UNREFERENCED_PARAMETER(PreviousState);
    status = EzKmRefreshState(context, TRUE);
    if (!NT_SUCCESS(status)) {
        /* The synchronous USB helpers reset a failed pipe; retry once. */
        status = EzKmRefreshState(context, TRUE);
    }
    if (!NT_SUCCESS(status)) {
        EzKmLogFailure(EZKM_STAGE_D0_REFRESH, status);
        return status;
    }
    InterlockedExchange(&context->PollEnabled, 1);
    WdfTimerStart(context->PollTimer, WDF_REL_TIMEOUT_IN_MS(500));
    return STATUS_SUCCESS;
}

NTSTATUS
EzKmEvtD0Exit(_In_ WDFDEVICE Device, _In_ WDF_POWER_DEVICE_STATE TargetState)
{
    PEZKM_DEVICE_CONTEXT context = EzKmGetContext(Device);
    WDFREQUEST request;
    UNREFERENCED_PARAMETER(TargetState);
    InterlockedExchange(&context->PollEnabled, 0);
    WdfTimerStop(context->PollTimer, TRUE);
    while (NT_SUCCESS(WdfIoQueueRetrieveNextRequest(context->NotificationQueue, &request))) {
        InterlockedExchangePointer(&context->SmartcardExtension.OsData->NotificationIrp, NULL);
        WdfRequestComplete(request, STATUS_DEVICE_NOT_READY);
    }
    return STATUS_SUCCESS;
}

VOID
EzKmEvtPoll(_In_ WDFTIMER Timer)
{
    WDFDEVICE device = (WDFDEVICE)WdfTimerGetParentObject(Timer);
    PEZKM_DEVICE_CONTEXT context = EzKmGetContext(device);
    (void)EzKmRefreshState(context, FALSE);
    if (InterlockedCompareExchange(&context->PollEnabled, 0, 0) != 0) {
        WdfTimerStart(Timer, WDF_REL_TIMEOUT_IN_MS(500));
    }
}
