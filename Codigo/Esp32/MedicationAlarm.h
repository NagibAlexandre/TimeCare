#pragma once
#include <Arduino.h>
#include "MedicationSchedule.h"

bool beginMedicationAlarm();
bool updateMedicationSchedule(const MedicationSchedule &schedule);
