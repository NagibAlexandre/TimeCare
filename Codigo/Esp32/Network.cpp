#include "TimeCareNetwork.h"
#include "MedicationAlarm.h"
#include "Config.h"
#include "TrustRoots.h"
#include <ArduinoJson.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <esp_timer.h>
#include <sys/time.h>

int64_t epochMs() {
  timeval tv; gettimeofday(&tv,nullptr);
  if (tv.tv_sec<1767225600) return 0; // nao publicar millis() como Unix time
  return int64_t(tv.tv_sec)*1000+tv.tv_usec/1000;
}
static String token, refreshToken;
static uint32_t tokenSince=0, tokenLifetimeMs=0;
static Window pending;

static String urlEncode(const String &value) {
  String result; result.reserve(value.length()*3);
  const char hex[]="0123456789ABCDEF";
  for (unsigned i=0;i<value.length();++i) {
    uint8_t c=value[i];
    if ((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='-'||c=='_'||c=='.'||c=='~') result+=(char)c;
    else {result+='%';result+=hex[c>>4];result+=hex[c&15];}
  }
  return result;
}

static int request(const String &url, const char *method, const String &body,
                   String &response, bool form=false, bool createOnly=false) {
  WiFiClientSecure client;
  client.setCACert(GOOGLE_ROOTS);
  client.setHandshakeTimeout(12);
  HTTPClient http;
  http.setConnectTimeout(10000);
  http.setTimeout(10000);
  if (!http.begin(client,url)) return -1;
  http.addHeader("Content-Type",form?"application/x-www-form-urlencoded":"application/json");
  if (createOnly) http.addHeader("if-match","null_etag");
  int status=http.sendRequest(method,body);
  if (status<0) Serial.printf("HTTPS: transporte %d (%s), WiFi=%d RSSI=%d dBm\n",
    status,HTTPClient::errorToString(status).c_str(),int(WiFi.status()),WiFi.RSSI());
  response=http.getString();
  http.end();
  return status;
}

static bool authenticate() {
  if (token.length() && uint32_t(millis()-tokenSince)<tokenLifetimeMs) return true;
  bool refreshing=refreshToken.length()>0;
  String url,body,response;
  if (refreshing) {
    url=String("https://securetoken.googleapis.com/v1/token?key=")+urlEncode(FIREBASE_API_KEY);
    body="grant_type=refresh_token&refresh_token="+urlEncode(refreshToken);
  } else {
    url=String("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=")+urlEncode(FIREBASE_API_KEY);
    JsonDocument login;
    login["email"]=DEVICE_EMAIL; login["password"]=DEVICE_PASSWORD;
    login["returnSecureToken"]=true;
    serializeJson(login,body);
  }
  int status=request(url,"POST",body,response,refreshing);
  if (status!=200) {
    Serial.printf("Firebase Auth: HTTP %d (sem imprimir resposta/segredos)\n",status);
    if (status==400 || status==401) {refreshToken="";token="";}
    return false;
  }
  JsonDocument doc;
  if (deserializeJson(doc,response)) return false;
  String uid=doc[refreshing?"user_id":"localId"].as<String>();
  if (uid!=DEVICE_AUTH_UID) {
    Serial.println("Firebase: UID diferente do configurado; envio bloqueado.");
    token=""; refreshToken=""; return false;
  }
  token=doc[refreshing?"id_token":"idToken"].as<String>();
  refreshToken=doc[refreshing?"refresh_token":"refreshToken"].as<String>();
  long seconds=doc[refreshing?"expires_in":"expiresIn"].as<String>().toInt();
  if (!token.length() || seconds<=60) {token="";return false;}
  tokenLifetimeMs=(uint32_t)std::min<long>(seconds-60,3500)*1000;
  tokenSince=millis();
  return true;
}

static String makePayload(const Window &w, int64_t endEpoch, bool reconstructed) {
  JsonDocument doc;
  int64_t startEpoch=endEpoch-(w.endMono-w.startMono);
  doc["schema_version"]=1;
  doc["firmware_version"]="1.6.1-basic-bpm";
  doc["publication_policy"]="complete_window_basic_bpm_v1";
  doc["quality_contract_version"]=1;
  doc["timestamp"]=endEpoch;
  doc["received_at"][".sv"]="timestamp";
  doc["window_start"]=startEpoch;
  doc["window_ms"]=w.endMono-w.startMono;
  doc["clock_reconstructed"]=reconstructed;
  doc["source"]="esp32_timecare"; doc["simulated"]=false;
  doc["device_id"]=DEVICE_ID; doc["boot_id"]=bootId;
  doc["sequence"]=w.sequence;
  const char *spo2Status=oxygenStatus(w);
  const bool oxygenUsable=strcmp(spo2Status,"unvalidated_estimate")==0;
  doc["spo2_status"]=spo2Status;
  if (oxygenUsable) doc["spo2"]=w.spo2;
  doc["spo2_method"]="maxim_sparkfun_100_pairs_25hz";
  JsonObject oxygen=doc["spo2_diagnostics"].to<JsonObject>();
  oxygen["attempted"]=w.spo2Attempted;
  oxygen["algorithm_valid"]=w.spo2Valid;
  oxygen["clinically_validated"]=false;
  if (w.spo2Attempted) {
    oxygen["sample_count"]=100;
    oxygen["start_offset_ms"]=w.spo2StartOffsetMs;
    oxygen["end_offset_ms"]=w.spo2EndOffsetMs;
    if (w.spo2Valid) oxygen["candidate_percent"]=w.spo2;
  }
  float med=0,lo=0,hi=0;
  unsigned n=summarize(w,med,lo,hi);
  const char *pulseStatus=bpmStatus(w,n);
  doc["bpm_status"]=pulseStatus;
  if (strcmp(pulseStatus,"unvalidated_estimate")==0) {
    doc["bpm"]=med;
  }
  doc["bpm_summary_count"]=n;
  doc["bpm_method"]="median_new_intervals_after_settling";
  doc["bpm_summary_count_semantics"]="new_beat_intervals";
  JsonArray beats=doc["beats"].to<JsonArray>();
  for (unsigned i=0;i<w.beatCount;++i) {
    const Beat &b=w.beats[i];
    JsonObject o=beats.add<JsonObject>();
    o["offset_ms"]=b.offsetMs; o["ibi_ms"]=b.ibiMs; o["bpm"]=b.bpm;
    o["settling"]=b.settling;
    o["outside_legacy_range"]=b.bpm<45 || b.bpm>180;
  }
  JsonObject q=doc["quality"].to<JsonObject>();
  q["max_available"]=w.maxAvailable;
  q["tmp117_available"]=w.tempAvailable;
  q["ir_clipped_samples"]=w.irClippedSamples;
  q["red_clipped_samples"]=w.redClippedSamples;
  q["samples"]=w.totalSamples; q["contact_samples"]=w.contactSamples;
  q["contact_at_end"]=w.contactEnd;
  if (w.totalSamples) q["contact_fraction"]=float(w.contactSamples)/w.totalSamples;
  q["acquisition_errors"]=w.acquisitionErrors;
  q["fifo_overflows"]=w.overflows; q["beat_buffer_overflows"]=w.beatOverflow;
  q["overflow_counter_semantics"]="nonzero_register_observations_not_lost_samples";
  q["recovery_attempts"]=w.recoveryAttempts;q["recovery_failures"]=w.recoveryFailures;
  q["recovery_pending"]=w.recoveryPending;
  q["register_read_failures"]=w.registerReadFailures;q["burst_mismatches"]=w.burstMismatches;
  q["registers_ok"]=w.registersOK;
  q["fifo_wr"]=w.fifoWr;q["fifo_rd"]=w.fifoRd;q["fifo_ovf_register"]=w.fifoOvf;
  q["mode_register"]=w.modeReg;q["fifo_config_register"]=w.fifoConfig;
  q["spo2_config_register"]=w.spo2Config;
  q["observed_samples_per_second"]=1000.0*w.totalSamples/(w.endMono-w.startMono);
  JsonObject optical=doc["optical_diagnostics"].to<JsonObject>();
  optical["max_continuous_red_ir_pairs"]=w.maxContinuousPairs;
  optical["spo2_algorithm_implemented"]=true;
  if (w.totalSamples) {
    optical["red_min"]=w.redMin;optical["red_max"]=w.redMax;
    optical["ir_min"]=w.irMin;optical["ir_max"]=w.irMax;
    optical["last_red"]=w.lastRed;optical["last_ir"]=w.lastIR;
  }
  q["dropped_windows_total"]=w.droppedBefore;
  if (w.hasLastBeat) q["last_peak_age_ms"]=w.lastBeatAgeMs;
  q["status"]=pulseStatus; // compatibilidade: este status legado descreve BPM
  q["validated_sqi"]=false;
  JsonArray aux=doc["aux"].to<JsonArray>();
  float tempSum=0;unsigned tempN=0;
  for (unsigned i=0;i<w.auxCount;++i) {
    const Aux &a=w.aux[i];
    JsonObject o=aux.add<JsonObject>();
    o["offset_ms"]=a.offsetMs; o["tmp117_ok"]=a.tempOK; o["mpu_ok"]=a.mpuOK;
    if (a.tempOK) {o["temperatura"]=a.temp;tempSum+=a.temp;++tempN;}
    if (a.mpuOK) {
      o["ax_m_s2"]=a.ax;o["ay_m_s2"]=a.ay;o["az_m_s2"]=a.az;
      o["gx_deg_s"]=a.gx;o["gy_deg_s"]=a.gy;o["gz_deg_s"]=a.gz;
      o["mpu_die_temp_c"]=a.mpuTemp;
    }
  }
  const char *tempStatus=temperatureStatus(w,tempN);
  if (strcmp(tempStatus,"unvalidated_estimate")==0) doc["temperatura"]=tempSum/tempN;
  doc["temperature_samples"]=tempN;
  doc["temperature_status"]=tempStatus;
  doc["temperature_type"]="tmp117_contact_unvalidated";
  if (doc.overflowed()) return String();
  String body; serializeJson(doc,body);return body;
}

static bool configured() {
  return strcmp(WIFI_SSID,"PREENCHER") && strcmp(FIREBASE_API_KEY,"PREENCHER") &&
    strcmp(DEVICE_EMAIL,"PREENCHER") && strcmp(DEVICE_PASSWORD,"PREENCHER") &&
    strcmp(DEVICE_AUTH_UID,"PREENCHER");
}

static void refreshMedicationSchedule() {
  String response;
  const String url = String(DATABASE_URL) + "/" + urlEncode(USER_NODE) +
    "/remedios.json?auth=" + urlEncode(token);
  int status = request(url, "GET", "", response);
  if (status != 200) {
    Serial.printf("Horarios: HTTP %d; mantendo ultimo cache local.\n", status);
    if (status == 401) token = "";
    return;
  }
  if (response.length() > 65536) {
    Serial.println("Horarios: resposta muito grande; mantendo cache.");
    return;
  }
  JsonDocument doc;
  if (deserializeJson(doc, response) || (!doc.isNull() && !doc.is<JsonObject>())) {
    Serial.println("Horarios: resposta invalida; mantendo cache.");
    return;
  }
  MedicationSchedule schedule;
  unsigned invalid = 0;
  for (JsonPair item : doc.as<JsonObject>()) {
    const char *iso = item.value()["scheduled_time"].as<const char *>();
    unsigned minute;
    if (medicationMinute(iso, minute)) schedule.add(minute);
    else ++invalid;
  }
  if (invalid) Serial.printf("Horarios: %u entradas invalidas ignoradas.\n", invalid);
  updateMedicationSchedule(schedule);
}

void networkTask(void *) {
  if (!configured()) {
    Serial.println("Preencha Config.h: aquisicao local ativa, Firebase desativado.");
    for (;;) {xQueueReceive(publishQueue,&pending,portMAX_DELAY);}
  }
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID,WIFI_PASSWORD);
  configTime(0,0,"time.google.com","pool.ntp.org");
  bool havePending=false;
  String payload,key;
  uint32_t backoff=1000,lastReconnect=millis();
  uint32_t lastSchedulePoll = 0;
  bool schedulePolled = false;
  for (;;) {
    if (WiFi.status()!=WL_CONNECTED || !epochMs()) {
      if (WiFi.status()!=WL_CONNECTED && uint32_t(millis()-lastReconnect)>=15000) {
        WiFi.reconnect();lastReconnect=millis();
      }
      vTaskDelay(pdMS_TO_TICKS(1000));continue;
    }
    if (!authenticate()) {vTaskDelay(pdMS_TO_TICKS(15000));continue;}
    if (!schedulePolled || uint32_t(millis()-lastSchedulePoll) >= 15000) {
      lastSchedulePoll = millis();
      schedulePolled = true;
      refreshMedicationSchedule();
      if (!token.length()) continue;
    }
    if (!havePending) {
      if (xQueueReceive(publishQueue,&pending,pdMS_TO_TICKS(1000))!=pdTRUE) continue;
      if (strcmp(completeWindowStatus(pending),"complete")!=0) {
        Serial.println("Rede: janela incompleta bloqueada antes do envio.");
        continue;
      }
      int64_t end=pending.epochEnd;
      bool reconstructed=!end;
      if (!end) end=epochMs()-(esp_timer_get_time()/1000-pending.endMono);
      char buf[24];snprintf(buf,sizeof(buf),"%lld",(long long)end);key=buf;
      payload=makePayload(pending,end,reconstructed);
      while (!payload.length()) {
        Serial.println("Memoria insuficiente para JSON; janela retida.");
        vTaskDelay(pdMS_TO_TICKS(1000));
        payload=makePayload(pending,end,reconstructed);
      }
      havePending=true;
    }
    String url=String(DATABASE_URL)+"/"+urlEncode(USER_NODE)+"/sinais_vitais/"+key+".json?auth="+urlEncode(token);
    String response;
    int status=request(url,"PUT",payload,response,false,true);
    bool saved=status==200 || status==204;
    if (status==412 || status==401 || status==403) { // conferir tentativa anterior mesmo com regra create-only
      int readStatus=request(url,"GET","",response);
      JsonDocument existing;
      if (readStatus==200 && !deserializeJson(existing,response) && !existing.isNull()) {
        saved=existing["boot_id"].as<String>()==bootId &&
          existing["device_id"].as<String>()==DEVICE_ID &&
          existing["sequence"].as<uint32_t>()==pending.sequence;
        if (!saved) {
          Serial.println("COLISAO de timestamp: envio bloqueado; registro existente preservado.");
          vTaskDelay(pdMS_TO_TICKS(30000));continue;
        }
      }
    }
    if (saved) {
      Serial.printf("Firebase: janela %lu salva\n",(unsigned long)pending.sequence);
      havePending=false;payload="";backoff=1000;
    } else {
      if (status==401) token="";
      Serial.printf("Firebase: HTTP %d; janela retida para nova tentativa\n",status);
      vTaskDelay(pdMS_TO_TICKS(backoff));backoff=std::min<uint32_t>(backoff*2,30000);
    }
  }
}
