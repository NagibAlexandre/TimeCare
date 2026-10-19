#include "MedicationAlarm.h"
#include "TimeCareNetwork.h"
#include <Preferences.h>

static constexpr uint8_t ledPins[] = {19, 18};
static constexpr uint8_t buzzerPin = 5;
static constexpr uint32_t buzzerHz = 2000;
// LEDs: GPIO -> individual series resistor -> LED -> GND (active HIGH).
// Passive piezo buzzer: signal on GPIO5, return on GND.
static QueueHandle_t scheduleQueue = nullptr;

static void alarmTask(void *) {
  Preferences state;
  const bool storageOK = state.begin("med_alarm", false);
  MedicationSchedule schedule;
  MedicationAlarmClock clock;
  if (storageOK) {
    if (state.getBytesLength("schedule") == sizeof(schedule))
      state.getBytes("schedule", &schedule, sizeof(schedule));
    clock.lastAlertMinute = state.getLong64("last_minute", -1);
  } else Serial.println("Alarme: armazenamento indisponivel; cache apenas em RAM.");
  bool previous = false;
  for (;;) {
    MedicationSchedule incoming;
    if (xQueueReceive(scheduleQueue, &incoming, 0) == pdTRUE &&
        memcmp(&incoming, &schedule, sizeof(schedule)) != 0) {
      schedule = incoming;
      if (storageOK && state.putBytes("schedule", &schedule, sizeof(schedule)) != sizeof(schedule))
        Serial.println("Alarme: falha ao salvar horarios locais.");
    }
    const uint32_t now = millis();
    if (clock.check(schedule, epochMs(), now)) {
      if (storageOK && state.putLong64("last_minute", clock.lastAlertMinute) != sizeof(int64_t))
        Serial.println("Alarme: falha ao salvar trava de repeticao.");
      Serial.println("Lembrete de medicamento: sinal de 10 segundos.");
    }
    const bool on = clock.outputOn(now);
    if (on != previous) {
      for (uint8_t pin : ledPins) digitalWrite(pin, on ? HIGH : LOW);
      ledcWriteTone(buzzerPin, on ? buzzerHz : 0);
      previous = on;
    }
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

bool beginMedicationAlarm() {
  for (uint8_t pin : ledPins) {
    digitalWrite(pin, LOW);
    pinMode(pin, OUTPUT);
  }
  pinMode(buzzerPin, OUTPUT);
  digitalWrite(buzzerPin, LOW);
  if (!ledcAttach(buzzerPin, buzzerHz, 8)) return false;
  ledcWriteTone(buzzerPin, 0);
  scheduleQueue = xQueueCreate(1, sizeof(MedicationSchedule));
  if (!scheduleQueue) return false;
  if (xTaskCreate(alarmTask, "med_alarm", 4096, nullptr, 1, nullptr) != pdPASS) {
    vQueueDelete(scheduleQueue);
    scheduleQueue = nullptr;
    return false;
  }
  return true;
}

bool updateMedicationSchedule(const MedicationSchedule &schedule) {
  return scheduleQueue && xQueueOverwrite(scheduleQueue, &schedule) == pdTRUE;
}
