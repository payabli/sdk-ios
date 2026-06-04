import { StatusBar } from "expo-status-bar";
import { useEffect, useState, type ReactNode } from "react";
import {
  Alert,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
  type EmitterSubscription,
} from "react-native";
import {
  PayabliEnvironment,
  PayabliPayInPaymentFlow,
  PayabliTTP,
  PayabliTTPEventCode,
  PayabliTTPSessionState,
  type PayabliTTPEvent,
} from "payabli-sdk-react-native";

const Secrets = {
  entryPoint: "<YOUR_ENTRY_POINT>",
  appId: "<TEAM_ID>.<BUNDLE_ID>",
  fetchAccessToken: async () => "placeholder-token",
  fetchPayInPaymentFlowAccessToken: async () => "placeholder-payin-payment-flow-access-token",
};

export default function App() {
  const [configured, setConfigured] = useState(false);
  const [sessionState, setSessionState] = useState(PayabliTTPSessionState.Idle);
  const [amount, setAmount] = useState("1.00");
  const [activationCode, setActivationCode] = useState("");
  const [cardNumber, setCardNumber] = useState("4111111111111111");
  const [expiration, setExpiration] = useState("02/28");
  const [cardholderName, setCardholderName] = useState("Jane Doe");
  const [cvv, setCvv] = useState("123");
  const [postalCode, setPostalCode] = useState("33139");
  const [achAccount, setAchAccount] = useState("1111111111111");
  const [achRouting, setAchRouting] = useState("123456780");
  const [achHolder, setAchHolder] = useState("Jane Doe");
  const [isWorking, setIsWorking] = useState(false);
  const [result, setResult] = useState("Not configured");
  const [payInResult, setPayInResult] = useState("No PayIn result yet");
  const [events, setEvents] = useState<string[]>([]);

  useEffect(() => {
    let subscription: EmitterSubscription | undefined;
    try {
      subscription = PayabliTTP.addEventListener((event) => {
        setEvents((current) => [eventLabel(event), ...current].slice(0, 20));
      });
    } catch (error) {
      setResult(errorMessage(error));
    }

    return () => {
      subscription?.remove();
    };
  }, []);

  const configure = async () => {
    await run("Configure", async () => {
      await PayabliTTP.configure({
        accessToken: await Secrets.fetchAccessToken(),
        tokenProvider: Secrets.fetchAccessToken,
        entryPoint: Secrets.entryPoint,
        appId: Secrets.appId,
        environment: PayabliEnvironment.Sandbox,
      });
      await PayabliPayInPaymentFlow.configure({
        accessTokenProvider: Secrets.fetchPayInPaymentFlowAccessToken,
        entryPoint: Secrets.entryPoint,
        environment: PayabliEnvironment.Sandbox,
      });
      setConfigured(true);
      await refreshState();
      setResult("Configured");
    });
  };

  const initialize = async () => {
    await run("Initialize", async () => {
      await PayabliTTP.initialize();
      await refreshState();
      setResult("Initialized");
    });
  };

  const charge = async () => {
    await run("Charge", async () => {
      const value = Number.parseFloat(amount);
      if (!Number.isFinite(value) || value <= 0) {
        throw new Error("Enter a valid amount.");
      }
      const response = await PayabliTTP.charge({
        paymentDetails: {
          amount: value,
          currency: "USD",
          paymentDescription: "React Native demo sale",
        },
      });
      setResult(`Charged transaction ${response.paymentTransId}`);
      await refreshState();
    });
  };

  const activateDevice = async () => {
    await run("Activate device", async () => {
      const code = activationCode.trim();
      if (!code) {
        throw new Error("Enter an activation code.");
      }
      await PayabliTTP.activateDevice(code);
      setActivationCode("");
      setResult("Device activated");
      await refreshState();
    });
  };

  const refreshState = async () => {
    const state = await PayabliTTP.getSessionState();
    setSessionState(state);
  };

  const addCard = async () => {
    await run("Add card", async () => {
      const stored = await PayabliPayInPaymentFlow.addCard({
        cardNumber,
        expiration,
        cardholderName,
        cvv,
        billingZip: postalCode,
        createAnonymous: false,
        forceCustomerCreation: true,
        temporary: false,
        source: "react-native-demo",
      });
      setPayInResult(storedResultText(stored));
    });
  };

  const addACH = async () => {
    await run("Add ACH", async () => {
      const stored = await PayabliPayInPaymentFlow.addACH({
        accountNumber: achAccount,
        accountType: "Checking",
        holderName: achHolder,
        routingNumber: achRouting,
        secCode: "WEB",
        holderType: "personal",
        achValidation: true,
        createAnonymous: false,
        forceCustomerCreation: true,
        temporary: false,
        source: "react-native-demo",
      });
      setPayInResult(storedResultText(stored));
    });
  };

  const run = async (label: string, work: () => Promise<void>) => {
    try {
      setIsWorking(true);
      await work();
    } catch (error) {
      const message = errorMessage(error);
      setResult(`${label} failed: ${message}`);
      Alert.alert(label, message);
    } finally {
      setIsWorking(false);
    }
  };

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
        <View style={styles.header}>
          <Text style={styles.title}>Payabli React Native QA</Text>
          <View style={styles.badge}>
            <Text style={styles.badgeText}>{sessionStateLabel(sessionState)}</Text>
          </View>
        </View>

        <Section title="Setup">
          <ActionButton title={configured ? "Configured" : "Configure"} disabled={isWorking} onPress={configure} />
          <Text style={styles.resultText}>{result}</Text>
        </Section>

        <Section title="Tap to Pay">
          <Row>
            <ActionButton title="Initialize" disabled={isWorking || !configured} onPress={initialize} />
            <ActionButton title="Refresh" disabled={isWorking || !configured} onPress={() => run("Refresh", refreshState)} />
          </Row>
          <TextInput
            value={amount}
            onChangeText={setAmount}
            keyboardType="decimal-pad"
            placeholder="Amount"
            style={styles.input}
          />
          <ActionButton title="Charge" disabled={isWorking || !configured} onPress={charge} />
          <TextInput
            value={activationCode}
            onChangeText={setActivationCode}
            placeholder="Activation code"
            autoCapitalize="characters"
            style={styles.input}
          />
          <ActionButton title="Activate Device" disabled={isWorking || !configured} onPress={activateDevice} />
        </Section>

        <Section title="Card PayIn Flow">
          <TextInput value={cardNumber} onChangeText={setCardNumber} keyboardType="number-pad" placeholder="Card number" style={styles.input} />
          <Row>
            <TextInput value={expiration} onChangeText={setExpiration} keyboardType="number-pad" placeholder="Expiration" style={[styles.input, styles.rowInput]} />
            <TextInput value={cvv} onChangeText={setCvv} keyboardType="number-pad" placeholder="CVV" secureTextEntry style={[styles.input, styles.rowInput]} />
          </Row>
          <TextInput value={cardholderName} onChangeText={setCardholderName} placeholder="Name on card" style={styles.input} />
          <TextInput value={postalCode} onChangeText={setPostalCode} keyboardType="default" placeholder="Postal Code" style={styles.input} />
          <ActionButton title="Add Card" disabled={isWorking || !configured} onPress={addCard} />
        </Section>

        <Section title="ACH PayIn Flow">
          <TextInput value={achAccount} onChangeText={setAchAccount} keyboardType="number-pad" placeholder="Account number" secureTextEntry style={styles.input} />
          <TextInput value={achRouting} onChangeText={setAchRouting} keyboardType="number-pad" placeholder="Routing number" style={styles.input} />
          <TextInput value={achHolder} onChangeText={setAchHolder} placeholder="Account holder" style={styles.input} />
          <ActionButton title="Add ACH" disabled={isWorking || !configured} onPress={addACH} />
          <Text style={styles.resultText}>{payInResult}</Text>
        </Section>

        <Section title="Events">
          {events.length === 0 ? (
            <Text style={styles.mutedText}>No events yet</Text>
          ) : (
            events.map((event, index) => (
              <Text key={`${event}-${index}`} style={styles.eventText}>
                {event}
              </Text>
            ))
          )}
        </Section>
      </ScrollView>
    </SafeAreaView>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{title}</Text>
      {children}
    </View>
  );
}

function Row({ children }: { children: ReactNode }) {
  return <View style={styles.row}>{children}</View>;
}

function ActionButton({
  title,
  disabled,
  onPress,
}: {
  title: string;
  disabled?: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [
        styles.button,
        disabled && styles.buttonDisabled,
        pressed && !disabled && styles.buttonPressed,
      ]}
    >
      <Text style={[styles.buttonText, disabled && styles.buttonTextDisabled]}>{title}</Text>
    </Pressable>
  );
}

function sessionStateLabel(state: PayabliTTPSessionState): string {
  switch (state) {
    case PayabliTTPSessionState.AttestingDevice:
      return "attesting";
    case PayabliTTPSessionState.FetchingConfig:
      return "config";
    case PayabliTTPSessionState.InitializingReader:
      return "reader";
    case PayabliTTPSessionState.Ready:
      return "ready";
    case PayabliTTPSessionState.SessionExpired:
      return "expired";
    case PayabliTTPSessionState.Reinitializing:
      return "reinit";
    case PayabliTTPSessionState.PendingActivation:
      return "pending";
    case PayabliTTPSessionState.Error:
      return "error";
    case PayabliTTPSessionState.Idle:
    default:
      return "idle";
  }
}

function eventLabel(event: PayabliTTPEvent): string {
  const name = PayabliTTPEventCode[event.code] ?? `event-${event.code}`;
  const payload = Object.keys(event.payload).length > 0 ? ` ${JSON.stringify(event.payload)}` : "";
  return `${name}${payload}`;
}

function storedResultText(result: { storedMethodId?: string; responseText: string; resultText?: string }): string {
  return [
    `Stored method: ${result.storedMethodId ?? "-"}`,
    `Response: ${result.responseText}`,
    `Result: ${result.resultText ?? "-"}`,
  ].join("\n");
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: "#F7F8FA",
  },
  content: {
    padding: 18,
    gap: 14,
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
  },
  title: {
    flex: 1,
    color: "#14171A",
    fontSize: 28,
    fontWeight: "700",
  },
  badge: {
    minWidth: 78,
    borderRadius: 8,
    backgroundColor: "#1D4ED8",
    paddingHorizontal: 10,
    paddingVertical: 7,
  },
  badgeText: {
    color: "#FFFFFF",
    fontSize: 12,
    fontWeight: "700",
    textAlign: "center",
  },
  section: {
    borderRadius: 8,
    backgroundColor: "#FFFFFF",
    borderColor: "#DCE1E7",
    borderWidth: StyleSheet.hairlineWidth,
    padding: 14,
    gap: 10,
  },
  sectionTitle: {
    color: "#24292F",
    fontSize: 16,
    fontWeight: "700",
  },
  row: {
    flexDirection: "row",
    gap: 10,
  },
  input: {
    minHeight: 48,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "#CBD5E1",
    backgroundColor: "#FFFFFF",
    color: "#111827",
    paddingHorizontal: 12,
    fontSize: 16,
  },
  rowInput: {
    flex: 1,
  },
  button: {
    minHeight: 48,
    borderRadius: 8,
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "#0877F2",
    paddingHorizontal: 14,
  },
  buttonPressed: {
    backgroundColor: "#075CB8",
  },
  buttonDisabled: {
    backgroundColor: "#D7DEE8",
  },
  buttonText: {
    color: "#FFFFFF",
    fontSize: 16,
    fontWeight: "700",
  },
  buttonTextDisabled: {
    color: "#697586",
  },
  resultText: {
    color: "#384252",
    fontSize: 14,
    lineHeight: 20,
  },
  mutedText: {
    color: "#697586",
    fontSize: 14,
  },
  eventText: {
    color: "#384252",
    fontSize: 13,
    lineHeight: 18,
  },
});
