// WalkingPadSDK — Swift SDK for KingSmith WalkingPad treadmills over BLE.
//
// Public API:
//   WalkingPadController  — high-level scanning, connection, and control
//   WalkingPadDevice      — discovered BLE peripheral
//   ConnectionState       — scanning / connecting / connected / ready
//   DeviceProtocol        — .ftms or .legacy
//   TreadmillStatus       — live speed, distance, time, calories, steps, avgSpeed
//   TreadmillLastRecord   — last session summary
//   BeltState             — idle / running / paused / starting
//   CalorieCalculator     — ACSM metabolic equation-based calorie calculation
//   UserProfile           — user profile for calorie calculation
//   TreadmillMode, SensitivityLevel, PreferenceKey, TargetType
//   FTMSCommand, FTMSParser, FTMSMachineEvent, FTMSConstants
//   KSCommand, KingSmithParser, KingSmithConstants
//   WalkingPadCommand, WalkingPadParser, WalkingPadConstants, ByteUtils
