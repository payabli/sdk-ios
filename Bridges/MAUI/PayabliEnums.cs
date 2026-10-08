using ObjCRuntime;

namespace Payabli.TapToPay
{
    // ApiDefinition files drive binding generation but are not compiled into
    // the final assembly, so generated C# needs these enum declarations here.
    [Native]
    public enum PayabliTTPFailureReason : long
    {
        AttestationRequired = 0,
        ConfigurationRejected = 1,
        ServiceUnavailable = 2,
        DeviceIneligible = 3,
        SdkInternalError = 4,
        DeviceKeyUnavailable = 5,
    }

    [Native]
    public enum TapToPayChargeActivity : long
    {
        Opening = 0,
        WaitingForCard = 1,
        Closing = 2,
        CardDetected = 3,
        CardRemovalRequested = 4,
        CardReadRetryRequested = 5,
        PinEntryRequested = 6,
        PinEntryCompleted = 7,
        ReaderPromptDismissed = 8,
    }

    [Native]
    public enum PayabliEnvironment : long
    {
        Local = 0,
        QA = 1,
        Sandbox = 2,
        Production = 3,
    }

    [Native]
    public enum PayabliTTPPaymentType : long
    {
        Sale = 0,
    }

    [Native]
    public enum PayabliTTPSessionState : long
    {
        Idle = 0,
        AttestingDevice = 1,
        FetchingConfig = 2,
        InitializingReader = 3,
        Ready = 4,
        SessionExpired = 5,
        Reinitializing = 6,
        PendingActivation = 7,
        Failed = 8,
        PendingTerms = 9,
        Charging = 10,
    }
}
