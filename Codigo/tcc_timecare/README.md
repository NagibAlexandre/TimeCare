# TimeCare

Aplicativo Flutter para acompanhamento de medicamentos e sinais vitais enviados por ESP32.

## Estrutura esperada no Firebase Realtime Database

O aplicativo usa atualmente o usuário de demonstração em `user_test`:

```json
{
  "user_test": {
    "name": "Nome do paciente",
    "email": "paciente@exemplo.com",
    "idade": 65,
    "telefone": "+55 00 00000-0000",
    "remedios": {
      "-medicamentoId": {
        "name": "Losartana",
        "dosage": "50 mg",
        "scheduled_time": "2026-08-09T11:00:00.000Z",
        "instructions": "Após o café",
        "status": "off-time"
      }
    },
    "sinais_vitais": {
      "1754766000000": {
        "timestamp": 1754766000000,
        "bpm": 72,
        "spo2": 98,
        "temperatura": 36.5
      }
    }
  }
}
```

Para os sinais vitais, o identificador da medição pode ser o próprio timestamp. O campo `timestamp` pode ser Unix em milissegundos ou uma string ISO-8601. Também são aceitos os nomes `heartRate`/`heart_rate`, `temperature` e `temperatura`.

## Executar

```bash
flutter pub get
flutter run
```

## Simular sinais vitais sem ESP32

Use o script externo abaixo para inserir leituras plausíveis no mesmo nó que o aplicativo consulta. Ele requer somente Python 3:

```powershell
python tools/seed_vitals.py seed
```

Por padrão, insere 57 leituras a cada 6 horas, cobrindo 14 dias e permitindo calibrar a referência pessoal. Exemplos:

```powershell
# 96 medições a cada 15 minutos
python tools/seed_vitals.py seed --count 96 --interval-minutes 15

# Sem outliers artificiais
python tools/seed_vitals.py seed --outliers 0

# Apaga todas as medições do nó user_test/sinais_vitais
python tools/seed_vitals.py clear --confirm-clear
```

`clear` exige `--confirm-clear` para evitar uma remoção acidental. Antes de conectar o ESP32 real, execute esse comando para limpar os dados de demonstração.

Antes de publicar, configure regras do Firebase que restrinjam cada usuário ao seu próprio nó. O uso atual de `user_test` deve ser substituído pelo UID de autenticação quando o login for integrado.

## Fundamentação e limites do tratamento

A versão `baseline-mad-v2` usa mediana, MAD e escore robusto modificado para exploração retrospectiva. MAD zero não produz escore; não se aplicam pisos arbitrários nem exclusão automática de valores extremos. As telas e o PDF compartilham a interpretação dos dados; registros sinalizados como simulados são identificados, e as análises os mantêm separados dos demais.

As fontes recentes indexadas no PubMed, as fórmulas, os parâmetros experimentais e as limitações estão em [docs/algoritmo_sinais_vitais.md](docs/algoritmo_sinais_vitais.md). Os critérios de 20 leituras, 14 dias e janela de 30 dias não têm validação clínica para este protótipo. Dados de demonstração não garantem que haverá ocorrências: a série pode ter histórico insuficiente ou MAD zero.

O artigo revisado está em [docs/artigo_revisado.tex](docs/artigo_revisado.tex), com referências metodológicas adicionais em [docs/references_metodo.bib](docs/references_metodo.bib). Para compilá-lo, são necessários também a bibliografia original e os arquivos do modelo SBC.
