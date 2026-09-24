# Pulling CSV files from the watch

## 1. Connect watch via ADB
Enable ADB debugging on the watch:
  Settings → Developer Options → ADB Debugging → ON

Pair over Wi-Fi (easier than USB for a watch):
  Settings → Developer Options → Debug over Wi-Fi
  Note the IP shown (e.g. 192.168.1.42:5555)

Then on your laptop:
  adb connect 192.168.1.42:5555

## 2. List recorded sessions
  adb shell ls /sdcard/Android/data/com.spudbyte.imu_collector/files/

Output example:
  imu_20260924_183012.csv
  imu_20260924_190445.csv

## 3. Pull a file
  adb pull /sdcard/Android/data/com.spudbyte.imu_collector/files/imu_20260924_183012.csv

## 4. Pull all files at once
  adb pull /sdcard/Android/data/com.spudbyte.imu_collector/files/ ./sessions/

## CSV format
  timestamp_ms,ax,ay,az,gx,gy,gz
  1726510847000,0.12345,-9.81234,0.04412,0.00123,-0.00341,0.00891
  ...

- timestamp_ms : Unix time in milliseconds
- ax/ay/az     : Accelerometer in m/s²  (ay ≈ -9.8 at rest)
- gx/gy/gz     : Gyroscope in rad/s     (all ≈ 0.0 at rest)
- Sample rate  : ~50 Hz (one row every ~20ms)
