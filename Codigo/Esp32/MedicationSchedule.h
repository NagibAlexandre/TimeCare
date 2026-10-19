#pragma once
#include <stdint.h>
#include <string.h>
#include <stdio.h>

// Daily wall-clock schedule in Brasilia (UTC-3), matching the app's time picker.
struct MedicationSchedule {
  uint8_t minutes[180]{};
  void add(unsigned minute) {
    if (minute < 1440) minutes[minute / 8] |= uint8_t(1U << (minute % 8));
  }
  bool contains(unsigned minute) const {
    return minute < 1440 && (minutes[minute / 8] & (1U << (minute % 8)));
  }
};

inline bool medicationMinute(const char *iso, unsigned &minute) {
  if (!iso) return false;
  int y, month, day, hour, min, second, used = 0;
  if (sscanf(iso, "%4d-%2d-%2dT%2d:%2d:%2d%n",
             &y, &month, &day, &hour, &min, &second, &used) != 6 ||
      used != 19 || y < 1970 || month < 1 || month > 12 ||
      day < 1 || hour < 0 || hour > 23 || min < 0 || min > 59 ||
      second < 0 || second > 59) return false;
  const int days[] = {31,28,31,30,31,30,31,31,30,31,30,31};
  int maxDay = days[month - 1] + (month == 2 && y % 4 == 0 && (y % 100 != 0 || y % 400 == 0));
  if (day > maxDay) return false;
  const char *suffix = iso + used;
  if (*suffix == '.') {
    ++suffix;
    if (*suffix < '0' || *suffix > '9') return false;
    while (*suffix >= '0' && *suffix <= '9') ++suffix;
  }
  int offset = -180; // Older local ISO strings are interpreted as Brasilia.
  if (*suffix == 'Z' && suffix[1] == '\0') offset = 0;
  else if (*suffix == '+' || *suffix == '-') {
    int oh, om, count = 0;
    if (sscanf(suffix + 1, "%2d:%2d%n", &oh, &om, &count) != 2 ||
        count != 5 || suffix[6] != '\0' || oh < 0 || oh > 23 || om < 0 || om > 59) return false;
    offset = (oh * 60 + om) * (*suffix == '+' ? 1 : -1);
  } else if (*suffix != '\0') return false;
  minute = unsigned((hour * 60 + min - offset - 180 + 2880) % 1440);
  return true;
}

class MedicationAlarmClock {
 public:
  static constexpr uint32_t durationMs = 10000;
  static constexpr uint32_t pulseMs = 500;
  int64_t lastAlertMinute = -1;

  bool check(const MedicationSchedule &schedule, int64_t epochMilliseconds,
             uint32_t monotonicMs) {
    if (epochMilliseconds < 1767225600000LL) return false;
    const int64_t utcMinute = epochMilliseconds / 60000;
    const unsigned localMinute = unsigned((utcMinute - 180) % 1440);
    if (utcMinute <= lastAlertMinute || !schedule.contains(localMinute)) return false;
    lastAlertMinute = utcMinute;
    started = monotonicMs;
    active = true;
    return true;
  }
  bool outputOn(uint32_t now) {
    if (!active) return false;
    const uint32_t elapsed = now - started; // safe across millis() rollover
    if (elapsed >= durationMs) { active = false; return false; }
    return (elapsed / pulseMs) % 2 == 0;
  }
 private:
  bool active = false;
  uint32_t started = 0;
};
