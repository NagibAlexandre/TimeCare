#pragma once
#include <stdint.h>
#include <math.h>
#include <string.h>
#include <algorithm>

constexpr unsigned MAX_BEATS = 125; // no maximo um candidato por amostra, 25 Hz x 5s
constexpr unsigned MAX_AUX = 6;
struct Beat {
  uint32_t offsetMs, ibiMs;
  float bpm;
  bool settling;
};
struct Aux {
  uint32_t offsetMs;
  float temp, ax, ay, az, gx, gy, gz, mpuTemp;
  bool tempOK, mpuOK;
};
struct Window {
  bool heartRateAttempted, heartRateValid;
  int32_t algorithmBpm;
  bool spo2Attempted, spo2Valid;
  int32_t spo2;
  uint32_t spo2StartOffsetMs, spo2EndOffsetMs;
  int64_t startMono, endMono, epochEnd;
  uint32_t sequence, droppedBefore, totalSamples, contactSamples;
  uint32_t acquisitionErrors, overflows, beatOverflow;
  uint32_t irClippedSamples, redClippedSamples;
  uint32_t lastBeatAgeMs;
  uint32_t recoveryAttempts, recoveryFailures, registerReadFailures, burstMismatches;
  uint32_t irMin, irMax, redMin, redMax, lastIR, lastRed, maxContinuousPairs;
  uint8_t fifoWr, fifoRd, fifoOvf, modeReg, fifoConfig, spo2Config;
  bool registersOK, recoveryPending;
  bool hasLastBeat, maxAvailable, tempAvailable, contactEnd;
  uint16_t beatCount, auxCount;
  Beat beats[MAX_BEATS];
  Aux aux[MAX_AUX];
};
// Resumo da janela, sem filtro por proximidade do historico.
// Candidatos durante estabilizacao continuam no pacote, fora do resumo.
inline unsigned summarize(const Window &w, float &median, float &minimum, float &maximum) {
  float v[MAX_BEATS];
  unsigned n = 0;
  for (unsigned i=0; i<w.beatCount; ++i)
    if (!w.beats[i].settling && w.beats[i].ibiMs &&
        isfinite(w.beats[i].bpm) && w.beats[i].bpm>0) v[n++] = w.beats[i].bpm;
  if (!n) return 0;
  std::sort(v, v+n);
  median = n%2 ? v[n/2] : (v[n/2-1]+v[n/2])/2;
  minimum = v[0]; maximum = v[n-1];
  return n;
}

// Estados tecnicos por parametro; nao sao faixas clinicas nem um SQI validado.
inline const char *opticalStatus(const Window &w, bool oxygen) {
  if (!w.maxAvailable) return "sensor_unavailable";
  if (w.acquisitionErrors || w.overflows || w.recoveryPending ||
      w.registerReadFailures || !w.registersOK || (!oxygen && w.beatOverflow))
    return "acquisition_gap";
  if (!w.totalSamples) return "no_samples";
  if (w.irClippedSamples || (oxygen && w.redClippedSamples)) return "signal_clipped";
  if (!w.contactSamples) return "no_contact";
  if (!w.contactEnd || w.contactSamples!=w.totalSamples) return "unstable_contact";
  return "unvalidated_estimate";
}
inline const char *bpmStatus(const Window &w, unsigned count) {
  const char *status=opticalStatus(w,false);
  if (strcmp(status,"unvalidated_estimate")!=0) return status;
  return count?"unvalidated_estimate":"insufficient_data";
}
inline const char *oxygenStatus(const Window &w) {
  const char *status=opticalStatus(w,true);
  if (strcmp(status,"unvalidated_estimate")!=0) return status;
  if (!w.spo2Attempted) return "insufficient_data";
  return w.spo2Valid && w.spo2>0 && w.spo2<=100?
    "unvalidated_estimate":"algorithm_invalid";
}
inline const char *temperatureStatus(const Window &w, unsigned count) {
  if (!w.tempAvailable) return "sensor_unavailable";
  if (count) return "unvalidated_estimate";
  return w.auxCount?"read_error":"no_samples";
}

// Publication requires technically eligible measurements in one acquisition window.
// No clinical magnitude cutoff: extreme values alone do not prove an artifact.
inline const char *completeWindowStatus(const Window &w) {
  if (w.endMono <= w.startMono || w.beatCount > MAX_BEATS || w.auxCount > MAX_AUX)
    return "invalid_window";
  float median=0, minimum=0, maximum=0;
  const unsigned beats=summarize(w,median,minimum,maximum);
  const char *status=bpmStatus(w,beats);
  if (strcmp(status,"unvalidated_estimate")!=0) return status;
  status=oxygenStatus(w);
  if (strcmp(status,"unvalidated_estimate")!=0) return status;
  const uint64_t duration=uint64_t(w.endMono-w.startMono);
  if (w.spo2EndOffsetMs <= w.spo2StartOffsetMs || w.spo2EndOffsetMs > duration)
    return "invalid_oxygen_window";
  unsigned freshTemperatures=0;
  for (unsigned i=0;i<w.auxCount;++i) {
    const Aux &a=w.aux[i];
    if (!a.tempOK) continue;
    if (!isfinite(a.temp) || a.temp<-55 || a.temp>150) return "invalid_temperature";
    if (a.offsetMs>duration) return "stale_temperature";
    ++freshTemperatures;
  }
  status=temperatureStatus(w,freshTemperatures);
  if (strcmp(status,"unvalidated_estimate")!=0) return status;
  return "complete";
}
