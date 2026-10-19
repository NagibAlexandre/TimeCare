#pragma once
#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include "Telemetry.h"
extern QueueHandle_t publishQueue;
extern char bootId[17];
void networkTask(void *);
int64_t epochMs();
