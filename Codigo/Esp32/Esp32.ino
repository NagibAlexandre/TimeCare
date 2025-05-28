#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <LiquidCrystal_I2C.h>
#include "time.h"

#define WIFI_SSID "xxxxxxxxxx"
#define WIFI_PASSWORD "xxxxxxxxxx"
#define API_KEY "AIzaSyAy4FRG12XFK5ggNbZvTFyUKXTtAemLTvY"
#define DATABASE_URL "https://time-care-642b1-default-rtdb.firebaseio.com/"

// Altere "xxxxxxxxxx" pelos dados da sua rede próxima da plaquinha ^^^^^

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

LiquidCrystal_I2C lcd(0x27, 16, 2);

const char *ntpServer = "pool.ntp.org";
const long gmtOffset_sec = -3 * 3600; // Fuso horário de Brasília
const int daylightOffset_sec = 0;

// portas dos omponentes 
const int ledPins[] = {16, 4, 2, 15};
const int buzzerPin = 17;
const int reedPin = 13;

bool alertaFinalizado = false;

int timeToMinutes(String horario)
{
    int hora = horario.substring(0, 2).toInt();
    int minuto = horario.substring(3, 5).toInt();
    return hora * 60 + minuto;
}

bool reedAbriu()
{
    if (digitalRead(reedPin) == HIGH)
    {
        delay(30); 
        if (digitalRead(reedPin) == HIGH)
        { 
            return true;
        }
    }
    return false;
}

void alerta(unsigned long duracao_ms)
{
    unsigned long start = millis();
    bool estadoOn = false;
    unsigned long ultimoToggle = 0;
    const unsigned long intervaloPisca = 500; 

    int reedState = digitalRead(reedPin);

    if (reedState == HIGH)
    { 
        return;
    }

    // low = fechada
    // high = aberta

    Serial.println("Iniciando alerta!");

    while (millis() - start < duracao_ms)
    {
        reedState = digitalRead(reedPin);

        if (reedAbriu())
        {
            Serial.println("Caixa aberta, parando alerta");
            break;
        }

        if (millis() - ultimoToggle >= intervaloPisca)
        {
            estadoOn = !estadoOn;
            ultimoToggle = millis();

            for (int i = 0; i < 4; i++)
            {
                digitalWrite(ledPins[i], estadoOn ? HIGH : LOW);
            }
            digitalWrite(buzzerPin, estadoOn ? HIGH : LOW);
        }

        delay(10);
    }

    for (int i = 0; i < 4; i++)
    {
        digitalWrite(ledPins[i], LOW);
    }
    digitalWrite(buzzerPin, LOW);
    Serial.println("Alerta finalizado");
    return;
}

void setup()
{
    Serial.begin(115200);
    lcd.init();
    lcd.backlight();

    for (int i = 0; i < 4; i++)
    {
        pinMode(ledPins[i], OUTPUT);
        digitalWrite(ledPins[i], LOW);
    }
    pinMode(buzzerPin, OUTPUT);
    digitalWrite(buzzerPin, LOW);
    pinMode(reedPin, INPUT_PULLUP);

    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    Serial.print("Conectando WiFi");
    while (WiFi.status() != WL_CONNECTED)
    {
        delay(500);
        Serial.print(".");
    }
    Serial.println("\nWiFi conectado");

    config.api_key = API_KEY;
    config.database_url = DATABASE_URL;

    auth.user.email = "nagib@verly.com";
    auth.user.password = "najaini";

    Firebase.begin(&config, &auth);
    Firebase.reconnectWiFi(true);

    configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
}

void loop()
{
    struct tm timeinfo;
    if (!getLocalTime(&timeinfo))
    {
        Serial.println("Erro ao obter hora");
        delay(1000);
        return;
    }

    int nowMinutes = timeinfo.tm_hour * 60 + timeinfo.tm_min;
    Serial.printf("Agora: %02d:%02d (%d minutos)\n", timeinfo.tm_hour, timeinfo.tm_min, nowMinutes);

    if (Firebase.RTDB.getJSON(&fbdo, "/user_test/remedios"))
    {
        FirebaseJson json = fbdo.to<FirebaseJson>();
        FirebaseJsonData result;

        struct Remedio
        {
            String nome;
            String horario;
            int minutos;
            int diff;
        };

        std::vector<Remedio> remedios;

        size_t len = json.iteratorBegin();
        String key, value;
        int type;

        for (size_t i = 0; i < len; i++)
        {
            json.iteratorGet(i, type, key, value);
            FirebaseJson remedioJson;

            json.get(result, key);

            if (!result.stringValue.startsWith("{"))
                continue;

            remedioJson.setJsonData(result.stringValue);

            remedioJson.get(result, "name");
            String nome = result.stringValue;

            remedioJson.get(result, "scheduled_time");
            String horarioCompleto = result.stringValue;

            if (nome == "" || horarioCompleto == "")
                continue;

            int horaUTC = horarioCompleto.substring(11, 13).toInt();
            int minuto = horarioCompleto.substring(14, 16).toInt();

            int horaLocal = horaUTC - 3;
            if (horaLocal < 0)
                horaLocal += 24;

            char horarioLocal[6];
            sprintf(horarioLocal, "%02d:%02d", horaLocal, minuto);

            int minutos = timeToMinutes(String(horarioLocal));
            int diff = minutos - nowMinutes;
            if (diff < 0)
                diff += 1440;

            remedios.push_back({nome, String(horarioLocal), minutos, diff});
        }

        json.iteratorEnd();

        std::sort(remedios.begin(), remedios.end(), [](Remedio a, Remedio b)
                  { return a.diff < b.diff; });

        if (remedios.size() > 0)
        {
            lcd.clear();
            lcd.setCursor(0, 0);
            lcd.print(remedios[0].nome.substring(0, 16));
            lcd.setCursor(0, 1);
            lcd.print(remedios[0].horario);
            Serial.println("Mostrando:");
            Serial.println(remedios[0].nome + " - " + remedios[0].horario);

            if (remedios[0].diff == 0)
            {
                if (!alertaFinalizado)
                {
                    alerta(61000);
                    alertaFinalizado = true;
                }
            }
            else
            {
                alertaFinalizado = false; // flag pra controle de fechamento no alarme
            }
        }
        else
        {
            lcd.clear();
            lcd.setCursor(0, 0);
            lcd.print("Nenhum remedio");
            alertaFinalizado = false; // reset caso não tenha remédio
        }
    }
    else
    {
        Serial.println(fbdo.errorReason());
    }

    delay(1000);
}
