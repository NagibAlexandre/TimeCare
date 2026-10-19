#include <Arduino.h>
#include <Wire.h>
#include <SparkFun_TMP117.h>
#include <MAX30105.h>
#include <heartRate.h>
#include <spo2_algorithm.h>
#include <esp_timer.h>
#include <esp_system.h>
#include "Config.h"
#include "TimeCareNetwork.h"
#include "MedicationAlarm.h"
#include "FifoAccess.h"

#define SDA_PIN 21
#define SCL_PIN 22
#define TMP_ADDR 0x48
#define MAX_ADDR 0x57
#define MPU_ADDR 0x68
#include "Sensors.h"

TMP117 tmp117;
MAX30105 max30102;
bool tmpOK=false, maxOK=false, mpuOK=false;
QueueHandle_t publishQueue=nullptr;
char bootId[17];
static Window current{};
static uint32_t sequence=0, dropped=0;
static uint64_t sampleNumber=0, previousPeakSample=0;
static int64_t previousPeakMono=0, contactStart=0, lastPoll=0, lastAux=0;
static bool hasPeak=false, contact=false;
static bool recoveryPending=false;
static int64_t lastRecovery=-1000, lastRegisterCheck=-1000;
static uint32_t continuousPairs=0;
static_assert(FreqS == 25 && BUFFER_SIZE == 100 && FIFO_SAMPLE_MS == 40,
              "SpO2 requer 100 pares a 25 Hz");
static uint32_t oxygenRed[BUFFER_SIZE], oxygenIR[BUFFER_SIZE];
static unsigned oxygenCount=0;
static int64_t oxygenStart=0;

static int64_t monoMs() { return esp_timer_get_time()/1000; }
static void breakContinuity() { hasPeak=false; contact=false; contactStart=0; continuousPairs=0; oxygenCount=0; }
static bool readMax(uint8_t reg,uint8_t &value) { return lerRegistro(MAX_ADDR,reg,value); }
static bool writeMax(uint8_t reg,uint8_t value) { return escreverRegistro(MAX_ADDR,reg,value); }
static void recoverIfDue(int64_t now) {
  if (now-lastRecovery<1000) return;
  lastRecovery=now;
  ++current.recoveryAttempts;
  recoveryPending=!recoverFifo(readMax,writeMax);
  if (recoveryPending) ++current.recoveryFailures;
  current.registersOK=readMax(0x09,current.modeReg) && readMax(0x08,current.fifoConfig)
    && readMax(0x0A,current.spo2Config);
  FifoPointers ptr;
  if (readFifoPointers(readMax,ptr)) {
    current.fifoWr=ptr.wr;current.fifoRd=ptr.rd;current.fifoOvf=ptr.ovf;
  } else ++current.registerReadFailures;
}

static void beginWindow(int64_t now) {
  oxygenCount=0; // cada resultado usa somente amostras desta janela
  current = Window{};
  current.startMono=now;
  current.sequence=++sequence;
  current.maxAvailable=maxOK;
  current.tempAvailable=tmpOK;
  current.irMin=current.redMin=UINT32_MAX;
}

static void processIR(uint32_t red, uint32_t ir, int64_t sampleTime) {
  ++sampleNumber;
  ++current.totalSamples;
  if (ir>=0x3FFFF) ++current.irClippedSamples;
  if (red>=0x3FFFF) ++current.redClippedSamples;
  current.lastIR=ir;current.lastRed=red;
  current.irMin=std::min(current.irMin,ir);current.irMax=std::max(current.irMax,ir);
  current.redMin=std::min(current.redMin,red);current.redMax=std::max(current.redMax,red);
  const bool peak=checkForBeat(ir);
  if (ir<IR_CONTACT_MIN || ir>=0x3FFFF) {
    breakContinuity(); // nenhum bloco optico atravessa perda de contato/saturacao
    return;
  }
  ++current.contactSamples;
  if (red>0 && red<0x3FFFF) ++continuousPairs; else continuousPairs=0;
  current.maxContinuousPairs=std::max(current.maxContinuousPairs,continuousPairs);
  if (!contact) { contact=true; contactStart=sampleTime; hasPeak=false; }
  // Sem interpolacao ou rejeicao por proximidade ao valor anterior.
  if (!red || red>=0x3FFFF || sampleTime-contactStart<CONTACT_SETTLE_MS) {
    oxygenCount=0;
  } else if (!current.spo2Attempted) {
    if (!oxygenCount) oxygenStart=sampleTime;
    oxygenRed[oxygenCount]=red; oxygenIR[oxygenCount]=ir;
    if (++oxygenCount==BUFFER_SIZE) {
      int32_t oxygen=-999, algorithmHR=0;
      int8_t valid=0, hrValid=0;
      maxim_heart_rate_and_oxygen_saturation(oxygenIR,BUFFER_SIZE,oxygenRed,
                                            &oxygen,&valid,&algorithmHR,&hrValid);
      current.spo2Attempted=true;
      current.spo2Valid=valid==1 && oxygen>0 && oxygen<=100;
      current.spo2=oxygen;
      current.spo2StartOffsetMs=(uint32_t)std::max<int64_t>(0,oxygenStart-current.startMono);
      current.spo2EndOffsetMs=(uint32_t)std::max<int64_t>(0,sampleTime-current.startMono);
      oxygenCount=0;
    }
  }
  if (!peak) return;
  if (hasPeak) {
    const uint64_t interval=(sampleNumber-previousPeakSample)*FIFO_SAMPLE_MS;
    if (interval && interval<=UINT32_MAX) {
      if (current.beatCount<MAX_BEATS) {
        Beat &b=current.beats[current.beatCount++];
        b.offsetMs=(uint32_t)std::max<int64_t>(0,sampleTime-current.startMono);
        b.ibiMs=(uint32_t)interval;
        b.bpm=60000.0f/b.ibiMs;
        b.settling=sampleTime-contactStart<CONTACT_SETTLE_MS;
      } else ++current.beatOverflow;
    }
  }
  previousPeakSample=sampleNumber;
  previousPeakMono=sampleTime;
  hasPeak=true;

}

static void readPulse() {
  if (!maxOK) return;
  int64_t now=monoMs();
  if (now-lastPoll<5) return;
  // A biblioteca SparkFun possui buffer pequeno em RAM. Ler o FIFO direto
  // evita perder amostras ao drenar lotes maiores, mantendo configuracao e detector.
  if (lastPoll && now-lastPoll>=1000) {
    ++current.acquisitionErrors;
    breakContinuity();
    recoveryPending=true;
  }
  lastPoll=now;
  if (recoveryPending) { recoverIfDue(now); return; }
  FifoPointers ptr;
  if (!readFifoPointers(readMax,ptr)) {
    ++current.acquisitionErrors; ++current.registerReadFailures;
    breakContinuity(); recoveryPending=true; return;
  }
  current.fifoWr=ptr.wr;current.fifoRd=ptr.rd;current.fifoOvf=ptr.ovf;
  // Comparar burst apenas para OVF/RD (estaveis sem leitura de dados entre eles).
  if (now-lastRegisterCheck>=1000) {
    lastRegisterCheck=now;
    uint8_t burst[3];
    if (lerBytes(MAX_ADDR,0x04,burst,3)) {
      if (burst[1]!=ptr.ovf || burst[2]!=ptr.rd) ++current.burstMismatches;
    } else ++current.registerReadFailures;
    current.registersOK=readMax(0x09,current.modeReg) && readMax(0x08,current.fifoConfig)
      && readMax(0x0A,current.spo2Config);
    if (!current.registersOK || !acquisitionConfigMatches(current.modeReg,current.fifoConfig,current.spo2Config)) {
      ++current.acquisitionErrors;breakContinuity();recoveryPending=true;return;
    }
  }
  if (ptr.ovf) {
    ++current.overflows; breakContinuity(); recoveryPending=true; recoverIfDue(now); return;
  }
  unsigned count=(ptr.wr-ptr.rd)&31;
  for (unsigned i=0;i<count;++i) {
    uint8_t bytes[6]; // modo Red+IR, 18 bits por canal
    if (!lerBytes(MAX_ADDR,0x07,bytes,6)) {
      ++current.acquisitionErrors; breakContinuity(); recoveryPending=true; return;
    }
    uint32_t ir=((uint32_t(bytes[3])<<16)|(uint32_t(bytes[4])<<8)|bytes[5])&0x3FFFF;
    uint32_t red=((uint32_t(bytes[0])<<16)|(uint32_t(bytes[1])<<8)|bytes[2])&0x3FFFF;
    processIR(red,ir, now-int64_t(count-1-i)*FIFO_SAMPLE_MS);
  }
}

static void readAux() {
  int64_t now=monoMs();
  if (now-lastAux<1000) return;
  lastAux=now;
  if (current.auxCount>=MAX_AUX) return;
  Aux &a=current.aux[current.auxCount++];
  a.offsetMs=(uint32_t)(now-current.startMono);
  a.tempOK=false; a.mpuOK=false;
  // TMP117: registro de temperatura com sinal, resolucao 0.0078125 C.
  // Leitura direta permite detectar falha I2C em vez de reutilizar temperatura.
  uint8_t bytes[2];
  if (tmpOK && lerBytes(TMP_ADDR,0x00,bytes,2)) {
    a.temp=(int16_t)((uint16_t(bytes[0])<<8)|bytes[1])*0.0078125f;
    a.tempOK=isfinite(a.temp) && a.temp>=-55 && a.temp<=150;
  }
  if (mpuOK) a.mpuOK=lerMPU(a.ax,a.ay,a.az,a.gx,a.gy,a.gz,a.mpuTemp);
}

static void finishWindow(int64_t now) {
  current.endMono=now;
  current.epochEnd=epochMs();
  current.droppedBefore=dropped;
  current.contactEnd=contact;
  current.recoveryPending=recoveryPending;
  current.hasLastBeat=hasPeak;
  if (hasPeak) current.lastBeatAgeMs=(uint32_t)(now-previousPeakMono);
  Serial.printf("SpO2: tentativa=%d valida_algoritmo=%d valor=%ld%%\n",
    current.spo2Attempted,current.spo2Valid,(long)(current.spo2Valid?current.spo2:-1));
  float med=0,lo=0,hi=0;
  unsigned n=summarize(current,med,lo,hi);
  // Nao imprimir dados pessoais, tokens, URLs autenticadas ou senha.
  Serial.printf("Janela %lu: BPM basico; intervalos novos=%u; aproveitados=%u; mediana=%.1f; erros %lu; perdas fila %lu\n",
    (unsigned long)current.sequence,current.beatCount,n,n?med:-1.0f,
    (unsigned long)current.acquisitionErrors,(unsigned long)dropped);
  Serial.printf("MAX: amostras=%lu RED=%lu IR=%lu OVF=%u recuperacoes=%lu falhas=%lu burst_diff=%lu\n",
    (unsigned long)current.totalSamples,(unsigned long)current.lastRed,(unsigned long)current.lastIR,
    current.fifoOvf,(unsigned long)current.recoveryAttempts,(unsigned long)current.recoveryFailures,
    (unsigned long)current.burstMismatches);
  const char *publicationStatus=completeWindowStatus(current);
  if (strcmp(publicationStatus,"complete")!=0) {
    Serial.printf("Janela nao publicada: %s; aguardando tres medidas elegiveis.\n",publicationStatus);
  } else if (!publishQueue || xQueueSend(publishQueue,&current,0)!=pdTRUE) ++dropped;
  beginWindow(now);
}

void setup() {
  Serial.begin(115200);
  if (!beginMedicationAlarm()) Serial.println("FALHA: alarme de medicamento indisponivel.");
  delay(300);
  snprintf(bootId,sizeof(bootId),"%08lx%08lx",(unsigned long)esp_random(),(unsigned long)esp_random());
  Wire.begin(SDA_PIN,SCL_PIN);
  Wire.setClock(100000);
  Wire.setTimeOut(50);
  tmpOK=dispositivoPresente(TMP_ADDR) && tmp117.begin(TMP_ADDR,Wire);
  maxOK=dispositivoPresente(MAX_ADDR) && max30102.begin(Wire,I2C_SPEED_STANDARD);
  if (maxOK) {
    max30102.setup(0x1F,4,2,100,411,4096);
    max30102.setPulseAmplitudeRed(0x1F);
    max30102.setPulseAmplitudeIR(0x1F);
    max30102.setPulseAmplitudeGreen(0);
    max30102.disableFIFORollover();
    recoveryPending=true;
  }
  mpuOK=iniciarMPU();
  Serial.printf("TMP117=%d MAX30102=%d MPU=%d\n",tmpOK,maxOK,mpuOK);
  publishQueue=xQueueCreate(QUEUE_WINDOWS,sizeof(Window));
  beginWindow(monoMs());
  if (maxOK) recoverIfDue(monoMs());
  lastAux=monoMs();
  if (!publishQueue || xTaskCreate(networkTask,"firebase",16384,nullptr,1,nullptr)!=pdPASS)
    Serial.println("FALHA: fila/tarefa de rede indisponivel; apenas aquisicao local.");
}

void loop() {
  readPulse();
  // Fechar antes da leitura auxiliar para manter offsets dentro da janela.
  int64_t now=monoMs();
  if (now-current.startMono>=WINDOW_MS) finishWindow(now);
  readAux();
  delay(1);
}
