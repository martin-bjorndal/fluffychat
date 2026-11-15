// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Unlocking chat backup on a new device with the recovery key, and making
// sure the device ends up signed by the account. Only a signed device asks
// the backup for the keys of earlier messages (the SDK's
// KeyManager.maybeAutoRequest skips unknown sessions).
//
// The SDK signs the device while unlocking, but only when it already knows
// the account's master key. Right after logging in it often doesn't, and
// then it skips signing without a word and never tries again: the device
// stays unsigned, new messages work, and every earlier message stays locked.

import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// Unlocks chat backup with [keyOrPassphrase], as the backup page does after
/// logging in, and signs this device. Throws InvalidPassphraseException for
/// a wrong key.
Future<void> unlockChatBackup(Client client, String keyOrPassphrase) async {
  await client.restoreCryptoIdentity(keyOrPassphrase, selfSign: false);
  await signThisDevice(client);
}

/// Signs this device with the account's cross-signing keys, when chat backup
/// is unlocked here but the device isn't signed yet, and returns whether it
/// did. Safe to call at every start: it does nothing for a signed device or
/// one without the keys.
Future<bool> signThisDevice(Client client) async {
  final encryption = client.encryption;
  final userId = client.userID;
  final deviceId = client.deviceID;
  if (encryption == null || userId == null || deviceId == null) return false;
  if (!encryption.crossSigning.enabled) return false;
  if (!await encryption.crossSigning.isCached()) return false;

  await client.userDeviceKeysLoading;
  var own = client.userDeviceKeys[userId];
  if (own?.masterKey == null || own?.deviceKeys[deviceId] == null) {
    // Not fetched yet, as right after logging in
    await client.updateUserDeviceKeys(additionalUsers: {userId});
    own = client.userDeviceKeys[userId];
  }
  final masterKey = own?.masterKey;
  final deviceKeys = own?.deviceKeys[deviceId];
  if (masterKey == null || deviceKeys == null) return false;
  if (!client.isUnknownSession && masterKey.directVerified) return false;

  // As CrossSigning.selfSign does, with the keys already unlocked: trust the
  // account's master key, then sign it with this device and this device
  // with the self-signing key
  await masterKey.setVerified(true, false);
  await encryption.crossSigning.sign([masterKey, deviceKeys]);
  return true;
}
