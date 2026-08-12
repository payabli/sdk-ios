// The Tap to Pay device list and the activation challenge.

import { LocalTokenServerError } from "./errors.mjs";
import { defaultEntry, envFilePath, stringValue } from "./settings.mjs";
import { payabliApi } from "./payabli-api.mjs";

// Observed values. Anything else is passed through as its raw number rather
// than guessed at.
const DEVICE_STATUS_ACTIVE = 1;
const DEVICE_STATUS_PENDING = 2;

// These endpoints report failure as HTTP 200 with `isSuccess: false`, so the
// real outcome is in the envelope rather than the transport status.
function envelopeDecline(payload) {
  if (!payload || payload.isSuccess !== false) {
    return null;
  }

  const data = payload.responseData || {};
  return {
    code: Number(data.resultCode) || 0,
    text: stringValue(data.resultText) || stringValue(payload.responseText) || "Declined"
  };
}

function deviceStatusLabel(status) {
  if (status === DEVICE_STATUS_ACTIVE) return "active";
  if (status === DEVICE_STATUS_PENDING) return "pending";
  return `status-${status}`;
}

async function describeDevice(entry, deviceId, options = {}) {
  const payload = await payabliApi(
    `/Device/get/${encodeURIComponent(entry)}/${encodeURIComponent(deviceId)}`,
    { options }
  );
  // Reported rather than dropped. Returning null removed the device from the list with nothing
  // said, so a lookup declined for provisioning or authorisation looked the same as a device that
  // is not there. Which decline codes mean a stale row is documented nowhere this server can read,
  // so it names what it skipped instead of deciding.
  const decline = envelopeDecline(payload);
  return decline ? { deviceId, decline } : { deviceId, device: payload.responseData || null };
}

// `/Device/list` omits pending devices, which are the only ones that can be
// activated, so the fuller `/Cloud/list` is the source and each row is then
// described individually to get its status.
export async function listTapToPayDevices(entry, options = {}) {
  if (!entry) {
    throw new LocalTokenServerError(
      400,
      `Set PAYABLI_ENTRY in ${envFilePath}, or pass entry in the request.`
    );
  }

  const payload = await payabliApi(`/Cloud/list/${encodeURIComponent(entry)}`, { options });
  const decline = envelopeDecline(payload);
  if (decline) {
    throw new LocalTokenServerError(400, `Device list declined (${decline.code}): ${decline.text}`);
  }

  const rows = Array.isArray(payload.responseList) ? payload.responseList : [];
  const described = [];
  for (let index = 0; index < rows.length; index += 6) {
    const batch = await Promise.all(
      rows.slice(index, index + 6).map((row) => describeDevice(entry, row.deviceId, options))
    );
    described.push(...batch);
  }

  const unavailable = described
    .filter((row) => row.decline)
    .map((row) => ({ deviceId: row.deviceId, code: row.decline.code, text: row.decline.text }));

  const devices = described
    .map((row) => row.device)
    .filter((device) => device && stringValue(device.deviceType).toLowerCase() === "softpos")
    .map((device) => ({
      deviceId: device.deviceId,
      status: deviceStatusLabel(device.deviceStatus),
      deviceStatus: device.deviceStatus,
      model: device.model,
      serialNumber: device.serialNumber,
      friendlyName: device.friendlyName,
      createdAt: device.createdAt,
      updatedAt: device.updatedAt
    }))
    .sort((a, b) => String(b.createdAt || "").localeCompare(String(a.createdAt || "")));

  return { devices, unavailable };
}

// Requests the activation code for a pending device. Idempotent upstream: an
// unexpired code is returned again rather than reissued.
export async function requestActivationCode(options = {}) {
  const entry = stringValue(options.entry) || defaultEntry;
  if (!entry) {
    throw new LocalTokenServerError(
      400,
      `Set PAYABLI_ENTRY in ${envFilePath}, or pass entry in the request.`
    );
  }

  let deviceId = stringValue(options.deviceId);
  let resolvedFrom = "request";

  // A serial number is the app's identifierForVendor and is shared by every
  // record a reinstall leaves behind, so it cannot pick one device out. Only a
  // deviceId does. Falling back to the newest pending device is a convenience
  // for a single-device QA setup, and reports itself as such.
  if (!deviceId) {
    const { devices } = await listTapToPayDevices(entry, options);
    const pending = devices.filter((device) => device.deviceStatus === DEVICE_STATUS_PENDING);

    if (pending.length === 0) {
      throw new LocalTokenServerError(
        404,
        `No pending Tap to Pay devices on ${entry}. Pass deviceId to target a specific device.`
      );
    }

    deviceId = stringValue(pending[0].deviceId);
    resolvedFrom = pending.length === 1 ? "onlyPendingDevice" : `newestOf${pending.length}Pending`;
  }

  const payload = await payabliApi("/v2/device/taptopay/activate/challenge", {
    method: "POST",
    body: { entry, deviceId },
    options
  });

  const decline = envelopeDecline(payload);
  if (decline) {
    throw new LocalTokenServerError(
      decline.code === 404 ? 404 : 400,
      `Activation challenge declined (${decline.code}): ${decline.text}`
    );
  }

  const data = payload.responseData || {};
  // An envelope that reports success and carries no code is an upstream fault, not an activation.
  // Returned as 200 with an empty code it reads as issuance, and the device is never activated.
  const code = stringValue(data.code);
  if (!code) {
    throw new LocalTokenServerError(
      502,
      `Activation challenge for ${deviceId} on ${entry} reported success and returned no code.`
    );
  }

  return {
    entry,
    deviceId,
    resolvedFrom,
    code,
    expiresAt: stringValue(data.expiresAt),
    alreadyIssued: Boolean(data.alreadyIssued)
  };
}
