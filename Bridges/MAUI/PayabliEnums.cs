using ObjCRuntime;

namespace Payabli.TapToPay
{
    // ApiDefinition files drive binding generation but are not compiled into
    // the final assembly, so generated C# needs these enum declarations here.
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
        Error = 8,
    }

    [Native]
    public enum PayabliTTPEventCode : long
    {
        AttestationStarted = 0,
        AttestationCompleted = 1,
        ConfigReceived = 2,
        ReaderInitializing = 3,
        ReaderReady = 4,
        ChargeInitiated = 5,
        NfcStarted = 6,
        NfcCompleted = 7,
        NfcFailed = 8,
        UpdateCompleted = 9,
        UpdateFailed = 10,
        SessionExpired = 11,
        ReinitializeStarted = 12,
        ReinitializeCompleted = 13,
        DevicePendingActivation = 14,
        ActivationStarted = 15,
        ActivationCompleted = 16,
        ActivationFailed = 17,
        AttestationFailed = 18,
        ConfigFailed = 19,
    }
}
