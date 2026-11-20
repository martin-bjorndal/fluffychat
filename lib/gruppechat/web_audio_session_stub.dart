// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Outside the browser there is no page audio session.
String? webAudioSessionType() => null;

void setWebAudioSessionType(String type) {}
