/**
 * TypeScript surface for the React Native bridge to PayabliSDKTapToPay.
 *
 * Wraps the iOS Native Module declared in `PayabliSDKModule.swift`. Method
 * names, argument shapes, and event names are 1:1 with that file.
 *
 * ## Authentication
 *
 * Your JS app obtains the access token from your **own backend** (which
 * holds the Payabli `clientSecret` server-side) and passes it to
 * {@link configure}. When the SDK needs to refresh it emits
 * `TTPTokenRefreshRequested`; supply a {@link tokenProvider} callback to
 * {@link configure} and the bridge will call it for you.
 *
 * ## Tap to Pay requirements
 *
 *   - Apple's `proximity-reader.payment.acceptance` entitlement on the
 *     iOS host app target (request to Apple).
 *   - `App Attest` entitlement (`devicecheck.appattest-environment`).
 *   - A physical iPhone XS or newer running iOS 16.7+.
 */

import { NativeModules, NativeEventEmitter, EmitterSubscription } from 'react-native';

const { PayabliSDKModule } = NativeModules as { PayabliSDKModule: NativePayabliSDKModule };

// Singleton emitter — reused across all event subscribers.
const emitter = new NativeEventEmitter(NativeModules.PayabliSDKModule);

// MARK: - Public enums (raw indices match the @objc Int enums on iOS)

export enum PayabliEnvironment {
    Local = 0,
    QA = 1,
    Sandbox = 2,
    Production = 3,
}

export enum PayabliTTPPaymentType {
    Sale = 0,
}

export enum PayabliTTPSessionState {
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

export enum PayabliTTPEventCode {
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
}

// MARK: - Data shapes

export interface PayabliTTPCustomerData {
    firstName?: string;
    lastName?: string;
    customerNumber?: string;
    email?: string;
    phone?: string;
    customerId?: number;
    company?: string;
    billingAddress1?: string;
    billingAddress2?: string;
    billingCity?: string;
    billingState?: string;
    billingZip?: string;
    billingCountry?: string;
    billingPhone?: string;
    billingEmail?: string;
    shippingAddress1?: string;
    shippingAddress2?: string;
    shippingCity?: string;
    shippingState?: string;
    shippingZip?: string;
    shippingCountry?: string;
}

export interface PayabliTTPPaymentDetails {
    amount: number;
    serviceFee?: number;
    currency?: string;
    paymentDescription?: string;
}

export interface PayabliTTPInvoiceData {
    invoiceNumber?: string;
}

export interface PayabliTTPTransactionResult {
    paymentTransId: string;
}

export interface PayabliTTPEvent {
    code: PayabliTTPEventCode;
    payload: { paymentTransId?: string; error?: string };
}

export interface PayabliTTPConfig {
    accessToken: string;
    entryPoint: string;
    appId: string;
    environment?: PayabliEnvironment;
    /** Async callback invoked when the SDK needs a fresh access token. */
    tokenProvider: () => Promise<string>;
}

export interface PayabliTTPChargeRequest {
    paymentDetails: PayabliTTPPaymentDetails;
    type?: PayabliTTPPaymentType;
    customer?: PayabliTTPCustomerData;
    invoice?: PayabliTTPInvoiceData;
    orderDescription?: string;
}

// MARK: - Native module typing

interface NativePayabliSDKModule {
    configure(config: {
        accessToken: string;
        entryPoint: string;
        appId: string;
        environment: number;
    }): Promise<void>;

    initialize(): Promise<void>;

    charge(params: {
        type: number;
        paymentDetails: {
            amount: number;
            serviceFee: number;
            currency?: string;
            paymentDescription?: string;
        };
        customer?: PayabliTTPCustomerData;
        invoice?: PayabliTTPInvoiceData;
        orderDescription?: string;
    }): Promise<PayabliTTPTransactionResult>;

    activateDevice(activationCode: string): Promise<void>;

    getSessionState(): Promise<number>;

    resolveTokenRefresh(token: string): void;

    rejectTokenRefresh(reason: string): void;
}

// MARK: - Public API

let refreshSubscription: EmitterSubscription | null = null;

/**
 * Configures the underlying `PayabliTTP` instance. Call once per app
 * launch, before {@link initialize}. Wires the JS-side token refresh
 * handler to the native `TTPTokenRefreshRequested` event so the SDK can
 * silently refresh the access token without surfacing `tokenExpired` to
 * the host.
 */
export async function configure(config: PayabliTTPConfig): Promise<void> {
    refreshSubscription?.remove();
    refreshSubscription = emitter.addListener(
        'TTPTokenRefreshRequested',
        async () => {
            try {
                const token = await config.tokenProvider();
                PayabliSDKModule.resolveTokenRefresh(token);
            } catch (e) {
                const message = e instanceof Error ? e.message : String(e);
                PayabliSDKModule.rejectTokenRefresh(message);
            }
        }
    );

    await PayabliSDKModule.configure({
        accessToken: config.accessToken,
        entryPoint: config.entryPoint,
        appId: config.appId,
        environment: config.environment ?? PayabliEnvironment.Sandbox,
    });
}

/** Runs the cold/warm attestation + config + reader-prepare pipeline. */
export function initialize(): Promise<void> {
    return PayabliSDKModule.initialize();
}

/** Runs a full sale charge: backend `/initiate` → NFC tap → backend `/update`. */
export function charge(req: PayabliTTPChargeRequest): Promise<PayabliTTPTransactionResult> {
    return PayabliSDKModule.charge({
        type: req.type ?? PayabliTTPPaymentType.Sale,
        paymentDetails: {
            amount: req.paymentDetails.amount,
            serviceFee: req.paymentDetails.serviceFee ?? 0,
            // Pass `currency` through verbatim — when undefined the SDK omits
            // it from `/initiate` and the backend authorizes in the
            // merchant's configured processor currency.
            currency: req.paymentDetails.currency,
            paymentDescription: req.paymentDetails.paymentDescription,
        },
        customer: req.customer,
        invoice: req.invoice,
        orderDescription: req.orderDescription,
    });
}

/** Activates a pending device using an out-of-band activation code. */
export function activateDevice(activationCode: string): Promise<void> {
    return PayabliSDKModule.activateDevice(activationCode);
}

/** Polls the current session state. */
export async function getSessionState(): Promise<PayabliTTPSessionState> {
    const raw = await PayabliSDKModule.getSessionState();
    return raw as PayabliTTPSessionState;
}

/**
 * Subscribes to lifecycle events. Returns an `EmitterSubscription` —
 * call `.remove()` to stop receiving events.
 */
export function addEventListener(
    handler: (event: PayabliTTPEvent) => void
): EmitterSubscription {
    return emitter.addListener('TTPEvent', (raw) => {
        handler({
            code: raw.code as PayabliTTPEventCode,
            payload: raw.payload || {},
        });
    });
}

export const PayabliTTP = {
    configure,
    initialize,
    charge,
    activateDevice,
    getSessionState,
    addEventListener,
};

export default PayabliTTP;
