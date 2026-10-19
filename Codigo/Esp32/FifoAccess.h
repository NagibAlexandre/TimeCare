#pragma once
#include <stdint.h>
// Cada registrador e enderecado separadamente; callbacks permitem teste com barramento simulado.
struct FifoPointers { uint8_t wr=0, ovf=0, rd=0; };
// Bits 3:0 = limiar FIFO_A_FULL, independente da media/taxa e do rollover.
inline bool acquisitionConfigMatches(uint8_t mode,uint8_t fifo,uint8_t spo2) {
  return mode==0x03 && (fifo&0xF0)==0x40 && spo2==0x27;
}
template<class Read>
bool readFifoPointers(Read read, FifoPointers &p) {
  return read(0x04,p.wr) && read(0x05,p.ovf) && read(0x06,p.rd)
    && !(p.wr&0xE0) && !(p.ovf&0xE0) && !(p.rd&0xE0);
}
template<class Read, class Write>
bool recoverFifo(Read read, Write write) {
  uint8_t mode=0, check=0;
  if (!read(0x09,mode) || (mode&7)!=3) return false;
  if (!write(0x09,mode|0x80)) return false;
  if (!read(0x09,check) || !(check&0x80)) return false;
  // Parar conversoes antes de limpar ponteiros: evita corrida com o produtor.
  if (!write(0x04,0) || !write(0x05,0) || !write(0x06,0)) return false;
  FifoPointers p;
  if (!readFifoPointers(read,p) || p.wr || p.ovf || p.rd) return false;
  if (!write(0x09,mode&0x7F)) return false;
  return read(0x09,check) && !(check&0x80) && (check&7)==3;
}
