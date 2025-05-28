# Documentação do Projeto

# Caixa Inteligente de Remédios

## 📦 Descrição do Projeto

Este projeto tem como objetivo auxiliar usuários no controle de medicações, automatizando lembretes e facilitando o gerenciamento dos remédios a serem tomados. A solução combina hardware (ESP32 com periféricos) e software (aplicativo e integração com Firebase) para garantir alertas precisos e armazenamento em nuvem.

---

## 🔧 Componentes Utilizados

### Hardware
- ESP32 Dev Module
- Display LCD 16x2 com I2C
- LEDs (vermelho, amarelo, verde)
- Buzzer (opcional para alerta sonoro)
- Fonte de alimentação 5V
- Botões (opcional para interação manual)
- Caixa física impressa ou artesanal

### Software
- Arduino IDE (código para o ESP32)
- Firebase Realtime Database
- Aplicativo mobile (Android ou multiplataforma)
- Biblioteca Firebase Arduino
- Biblioteca LiquidCrystal_I2C

---

## 📁 Estrutura do Projeto

PLMG-CC-TI5-2025-1-G15-TIMECARE/
- [/Codigo](./Codigo): Códigos utilizados (físico e virtual)
- [/Divulgacao](./Divulgacao): Slides e vídeos utilizados
- [/Documentacao](./Documentacao): Informações oficiais sobre o trabalho
- [../README.md](../README.md): Documentação principal


---

## 🚀 Como Usar

### 1. Configuração da Placa (ESP32)
- Abra o arquivo `.ino` na pasta [Esp32](./Esp32).
- Substitua os placeholders `"xxxxxxxxxx"` com o **nome da rede Wi-Fi** e **senha**.
- Faça o upload do código para a placa via Arduino IDE.

### 2. Uso do Aplicativo
- Instale o aplicativo no dispositivo móvel.
- Acesse a aba de cadastro de medicamentos.
- Adicione/remova remédios e configure os horários.
- O aplicativo enviará os dados para o Firebase.

### 3. Funcionamento da Caixa
- A placa ESP32 lê os dados do Firebase.
- Nos horários definidos:
  - Acende o LED correspondente.
  - Exibe informações no display LCD.
  - Emite alerta sonoro.

---

## 📊 Funcionalidades

- Cadastro dinâmico de medicamentos
- Sincronização em tempo real com o Firebase
- Alertas visuais (LEDs) e textuais (LCD)
- Modularidade e escalabilidade
- Aplicativo intuitivo para controle remoto

---

## 📌 Considerações

- É necessário acesso à internet para funcionamento completo.

---

## 📚 Créditos

**Desenvolvido por:** 

* Bruno Braga Guimarães Alves
* João Vítor de Freitas Scarlatelli
* Nagib Alexandre Verly Borjaili
* Vitor Dias de Britto Militão
* Vitor Lucio de Oliveira
* Yasmin Cassemiro Viegas


**Com a coordenação e apoio direto dos professores:**

* Matheus Alcântara Souza
* Rafael Henriques Nogueira Diniz

*Como parte do projeto da disciplina Trabalho Interdisciplinar V.*

---

