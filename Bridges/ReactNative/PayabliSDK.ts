/**
 * TypeScript surface for the React Native bridge to Payabli iOS SDK.
 *
 * Wraps the iOS Native Module declared in `PayabliSDKModule.swift`. Expo Go
 * cannot load this custom native module; use an Expo development build or a
 * bare React Native app with the native iOS bridge installed.
 */

import {
    EmitterSubscription,
    NativeEventEmitter,
    NativeModules,
} from "react-native";

const nativeModule = NativeModules.PayabliSDKModule as NativePayabliSDKModule | undefined;
const emitter = nativeModule ? new NativeEventEmitter(nativeModule as any) : null;

function requireNativeModule(): NativePayabliSDKModule {
    if (!nativeModule) {
        throw new Error(
            "PayabliSDKModule is not available. Build a custom Expo development client or bare React Native app with the Payabli iOS bridge installed."
        );
    }
    return nativeModule;
}

function requireEmitter(): NativeEventEmitter {
    if (!emitter) {
        throw new Error(
            "PayabliSDKModule events are not available. Build a custom Expo development client or bare React Native app with the Payabli iOS bridge installed."
        );
    }
    return emitter;
}

// MARK: - Public enums

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
    AttestationFailed = 18,
    ConfigFailed = 19,
}

export type PayabliPayInPaymentFlowACHAccountType = "Checking" | "Savings";
export type PayabliPayInPaymentFlowACHHolderType = "personal" | "business";
export type PayabliPayInPaymentFlowACHSecCode = "PPD" | "WEB" | "TEL" | "CCD" | "BOC";

// MARK: - Tap to Pay data shapes

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
    tokenProvider: () => Promise<string>;
}

export interface PayabliTTPChargeRequest {
    paymentDetails: PayabliTTPPaymentDetails;
    type?: PayabliTTPPaymentType;
    customer?: PayabliTTPCustomerData;
    invoice?: PayabliTTPInvoiceData;
    orderDescription?: string;
}

// MARK: - PayIn payment flow data shapes

export interface PayabliPayInPaymentFlowConfig {
    entryPoint: string;
    environment?: PayabliEnvironment;
    accessTokenProvider: () => Promise<string>;
}

export interface PayabliPayInPaymentFlowOptions {
    achValidation?: boolean;
    createAnonymous?: boolean;
    forceCustomerCreation?: boolean;
    temporary?: boolean;
    source?: string;
}

export interface PayabliPayInPaymentFlowCardData extends PayabliPayInPaymentFlowOptions {
    cardNumber: string;
    expiration: string;
    cardholderName: string;
    cvv: string;
    billingZip: string;
}

export interface PayabliPayInPaymentFlowACHData extends PayabliPayInPaymentFlowOptions {
    accountNumber: string;
    accountType: PayabliPayInPaymentFlowACHAccountType;
    holderName: string;
    routingNumber: string;
    secCode?: PayabliPayInPaymentFlowACHSecCode;
    holderType?: PayabliPayInPaymentFlowACHHolderType;
}

export interface PayabliPayInPaymentFlowStoredPaymentMethod {
    storedMethodId?: string;
    methodReferenceId?: string;
    resultCode?: number;
    resultText?: string;
    customerId?: number;
    responseText: string;
    apiResponse: Record<string, unknown>;
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

    configurePayInPaymentFlow(config: {
        entryPoint: string;
        environment: number;
    }): Promise<void>;

    addCard(params: PayabliPayInPaymentFlowCardData): Promise<PayabliPayInPaymentFlowStoredPaymentMethod>;

    addACH(params: PayabliPayInPaymentFlowACHData): Promise<PayabliPayInPaymentFlowStoredPaymentMethod>;

    resolvePayInPaymentFlowAccessToken(token: string): void;

    rejectPayInPaymentFlowAccessToken(reason: string): void;
}

// MARK: - Tap to Pay public API

let refreshSubscription: EmitterSubscription | null = null;

export async function configure(config: PayabliTTPConfig): Promise<void> {
    const module = requireNativeModule();
    const eventEmitter = requireEmitter();

    refreshSubscription?.remove();
    refreshSubscription = eventEmitter.addListener(
        "TTPTokenRefreshRequested",
        async () => {
            try {
                const token = await config.tokenProvider();
                module.resolveTokenRefresh(token);
            } catch (e) {
                const message = e instanceof Error ? e.message : String(e);
                module.rejectTokenRefresh(message);
            }
        }
    );

    await module.configure({
        accessToken: config.accessToken,
        entryPoint: config.entryPoint,
        appId: config.appId,
        environment: config.environment ?? PayabliEnvironment.Sandbox,
    });
}

export function initialize(): Promise<void> {
    return requireNativeModule().initialize();
}

export function charge(req: PayabliTTPChargeRequest): Promise<PayabliTTPTransactionResult> {
    return requireNativeModule().charge({
        type: req.type ?? PayabliTTPPaymentType.Sale,
        paymentDetails: {
            amount: req.paymentDetails.amount,
            serviceFee: req.paymentDetails.serviceFee ?? 0,
            currency: req.paymentDetails.currency,
            paymentDescription: req.paymentDetails.paymentDescription,
        },
        customer: req.customer,
        invoice: req.invoice,
        orderDescription: req.orderDescription,
    });
}

export function activateDevice(activationCode: string): Promise<void> {
    return requireNativeModule().activateDevice(activationCode);
}

export async function getSessionState(): Promise<PayabliTTPSessionState> {
    const raw = await requireNativeModule().getSessionState();
    return raw as PayabliTTPSessionState;
}

export function addEventListener(
    handler: (event: PayabliTTPEvent) => void
): EmitterSubscription {
    return requireEmitter().addListener("TTPEvent", (raw: { code: number; payload?: PayabliTTPEvent["payload"] }) => {
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

// MARK: - PayIn payment flow public API

let payInAccessTokenSubscription: EmitterSubscription | null = null;

export async function configurePayInPaymentFlow(
    config: PayabliPayInPaymentFlowConfig
): Promise<void> {
    const module = requireNativeModule();
    const eventEmitter = requireEmitter();

    payInAccessTokenSubscription?.remove();
    payInAccessTokenSubscription = eventEmitter.addListener(
        "PayInPaymentFlowAccessTokenRequested",
        async () => {
            try {
                const token = await config.accessTokenProvider();
                module.resolvePayInPaymentFlowAccessToken(token);
            } catch (e) {
                const message = e instanceof Error ? e.message : String(e);
                module.rejectPayInPaymentFlowAccessToken(message);
            }
        }
    );

    await module.configurePayInPaymentFlow({
        entryPoint: config.entryPoint,
        environment: config.environment ?? PayabliEnvironment.Sandbox,
    });
}

export function addCard(
    params: PayabliPayInPaymentFlowCardData
): Promise<PayabliPayInPaymentFlowStoredPaymentMethod> {
    return requireNativeModule().addCard(params);
}

export function addACH(
    params: PayabliPayInPaymentFlowACHData
): Promise<PayabliPayInPaymentFlowStoredPaymentMethod> {
    return requireNativeModule().addACH(params);
}

export const PayabliPayInPaymentFlow = {
    configure: configurePayInPaymentFlow,
    addCard,
    addACH,
};

export default PayabliTTP;
