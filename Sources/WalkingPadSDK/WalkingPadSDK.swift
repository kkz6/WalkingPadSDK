// WalkingPadSDK — Swift SDK for KingSmith WalkingPad treadmills over BLE.
//
// Public API:
//   WalkingPadController  — high-level scanning, connection, and control
//   WalkingPadDevice      — discovered BLE peripheral
//   ConnectionState       — scanning / connecting / connected / ready
//   DeviceProtocol        — .ftms or .legacy
//   TreadmillStatus       — live speed, distance, time, calories
//   TreadmillLastRecord   — last session summary
//   BeltState, TreadmillMode, SensitivityLevel, PreferenceKey, TargetType
//   FTMSCommand, FTMSParser, FTMSMachineEvent, FTMSConstants
//   KSCommand, KingSmithParser, KingSmithConstants
//   WalkingPadCommand, WalkingPadParser, WalkingPadConstants, ByteUtils
