#pragma once
// I2C direto preservado do firmware fornecido.
uint8_t mpuId = 0;
bool dispositivoPresente(uint8_t addr) {
  Wire.beginTransmission(addr);
  return Wire.endTransmission() == 0;
}

bool escreverRegistro(uint8_t addr,
                      uint8_t reg,
                      uint8_t valor) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.write(valor);

  return Wire.endTransmission() == 0;
}

bool lerRegistro(uint8_t addr,
                 uint8_t reg,
                 uint8_t &valor) {
  Wire.beginTransmission(addr);
  Wire.write(reg);

  if (Wire.endTransmission(false) != 0)
    return false;

  if (Wire.requestFrom(addr, (uint8_t)1) != 1)
    return false;

  valor = Wire.read();
  return true;
}

bool lerBytes(uint8_t addr,
              uint8_t reg,
              uint8_t *buffer,
              uint8_t quantidade) {
  Wire.beginTransmission(addr);
  Wire.write(reg);

  if (Wire.endTransmission(false) != 0)
    return false;

  if (Wire.requestFrom(addr, quantidade) != quantidade)
    return false;

  for (uint8_t i = 0; i < quantidade; i++) {
    buffer[i] = Wire.read();
  }

  return true;
}

// =====================================
// MPU - INICIALIZACAO
// =====================================

bool iniciarMPU() {
  if (!dispositivoPresente(MPU_ADDR))
    return false;

  uint8_t id;

  if (!lerRegistro(MPU_ADDR, 0x75, id))
    return false;

  Serial.printf("MPU WHO_AM_I: 0x%02X\n", id);

  if (id != 0x70 && id != 0x68)
    return false;

  mpuId = id;

  // Reset
  if (!escreverRegistro(MPU_ADDR, 0x6B, 0x80))
    return false;

  delay(150);

  // Acordar
  if (!escreverRegistro(MPU_ADDR, 0x6B, 0x01))
    return false;

  delay(100);

  // Habilitar acelerometro e giroscopio
  if (!escreverRegistro(MPU_ADDR, 0x6C, 0x00))
    return false;

  // Acelerometro +/- 2g
  if (!escreverRegistro(MPU_ADDR, 0x1C, 0x00))
    return false;

  // Giroscopio +/- 250 graus/s
  if (!escreverRegistro(MPU_ADDR, 0x1B, 0x00))
    return false;

  // Filtro digital
  if (!escreverRegistro(MPU_ADDR, 0x1A, 0x03))
    return false;

  return true;
}

// =====================================
// MPU - LEITURA
// =====================================

bool lerMPU(float &ax, float &ay, float &az,
            float &gx, float &gy, float &gz,
            float &temperatura) {

  uint8_t dados[14];

  if (!lerBytes(MPU_ADDR, 0x3B, dados, 14))
    return false;

  int16_t rawAX =
    (int16_t)((dados[0] << 8) | dados[1]);

  int16_t rawAY =
    (int16_t)((dados[2] << 8) | dados[3]);

  int16_t rawAZ =
    (int16_t)((dados[4] << 8) | dados[5]);

  int16_t rawTemp =
    (int16_t)((dados[6] << 8) | dados[7]);

  int16_t rawGX =
    (int16_t)((dados[8] << 8) | dados[9]);

  int16_t rawGY =
    (int16_t)((dados[10] << 8) | dados[11]);

  int16_t rawGZ =
    (int16_t)((dados[12] << 8) | dados[13]);

  ax = (rawAX / 16384.0f) * 9.80665f;
  ay = (rawAY / 16384.0f) * 9.80665f;
  az = (rawAZ / 16384.0f) * 9.80665f;

  gx = rawGX / 131.0f;
  gy = rawGY / 131.0f;
  gz = rawGZ / 131.0f;

  temperatura = mpuId == 0x68 ? (rawTemp / 340.0f) + 36.53f : (rawTemp / 333.87f) + 21.0f;

  return true;
}

