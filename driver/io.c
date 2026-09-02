#include "ez100pu_km.h"

_Function_class_(IO_COMPLETION_ROUTINE)
static NTSTATUS
EzKmSmcComplete(
    _In_ PDEVICE_OBJECT DeviceObject,
    _In_ PIRP Irp,
    _In_ PVOID CompletionContext)
{
    UNREFERENCED_PARAMETER(DeviceObject);
    WdfRequestCompleteWithInformation(
        (WDFREQUEST)CompletionContext, Irp->IoStatus.Status, Irp->IoStatus.Information);
    return STATUS_MORE_PROCESSING_REQUIRED;
}
VOID
EzKmEvtIoDeviceControl(
    _In_ WDFQUEUE Queue,
    _In_ WDFREQUEST Request,
    _In_ size_t OutputBufferLength,
    _In_ size_t InputBufferLength,
    _In_ ULONG IoControlCode)
{
    PEZKM_DEVICE_CONTEXT context = EzKmGetContext(WdfIoQueueGetDevice(Queue));
    PIRP irp = WdfRequestWdmGetIrp(Request);

    UNREFERENCED_PARAMETER(OutputBufferLength);
    UNREFERENCED_PARAMETER(InputBufferLength);
    UNREFERENCED_PARAMETER(IoControlCode);

    EZKM_SET_REQUEST_IN_IRP(irp, Request);
    IoCopyCurrentIrpStackLocationToNext(irp);
    IoSetCompletionRoutine(irp, EzKmSmcComplete, Request, TRUE, TRUE, TRUE);
    IoSetNextIrpStackLocation(irp);
    (void)SmartcardDeviceControl(&context->SmartcardExtension, irp);
}

VOID
EzKmEvtCanceled(_In_ WDFQUEUE Queue, _In_ WDFREQUEST Request)
{
    PEZKM_DEVICE_CONTEXT context = EzKmGetContext(WdfIoQueueGetDevice(Queue));
    InterlockedCompareExchangePointer(
        &context->SmartcardExtension.OsData->NotificationIrp,
        NULL,
        WdfRequestWdmGetIrp(Request));
    WdfRequestComplete(Request, STATUS_CANCELLED);
}

VOID
EzKmEvtFileCleanup(_In_ WDFFILEOBJECT FileObject)
{
    PEZKM_DEVICE_CONTEXT context = EzKmGetContext(WdfFileObjectGetDevice(FileObject));
    WDFREQUEST request;
    NTSTATUS status;

    do {
        status = WdfIoQueueRetrieveRequestByFileObject(
            context->NotificationQueue, FileObject, &request);
        if (NT_SUCCESS(status)) {
            InterlockedCompareExchangePointer(
                &context->SmartcardExtension.OsData->NotificationIrp,
                NULL,
                WdfRequestWdmGetIrp(request));
            WdfRequestComplete(request, STATUS_CANCELLED);
        }
    } while (NT_SUCCESS(status));
}
