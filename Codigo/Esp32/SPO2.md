# SpO2 — versão 1.2.0

> Atualização 1.3.0-quality: o firmware agora publica validade por parâmetro e foi compilado para ESP32 nesta integração. A descrição abaixo documenta a introdução da SpO₂ na versão anterior. Consulte `../tcc_timecare/docs/integracao_qualidade_sinais.md` para os estados adicionais, exclusão de falhas no app e passos de ativação. A placa ainda precisa ser gravada e testada.

O firmware usa `spo2_algorithm.h`, já incluído na biblioteca SparkFun MAX3010x. O algoritmo Maxim requer exatamente 100 pares RED/IR a 25 Hz, compatíveis com a configuração atual (100 Hz com média de quatro). São quatro segundos de aquisição, com 3960 ms entre primeira e última amostra. O BPM existente continua independente.

Cada janela de publicação de cinco segundos permite uma tentativa, usando os primeiros 100 pares contínuos após a estabilização. Não se reutiliza o resultado anterior. A coleta para SpO2 reinicia na fronteira da janela, perda de contato, clipping de qualquer canal ou falha de aquisição. A primeira janela após contato pode não conter amostras suficientes devido aos dois segundos de estabilização. Uma tentativa inválida só será repetida na próxima janela. Isso simplifica a rastreabilidade, mas deixa parte do sinal sem cobertura e não garante captura de eventos muito breves.

`spo2` é percentual inteiro, publicado apenas se o algoritmo sinalizar validade e o resultado estiver entre 1 e 100, sem falhas de aquisição na janela. Essa faixa verifica representação numérica, não normalidade clínica. Valores baixos não são descartados por distância do histórico. Nunca enviar zero, -999 ou um valor antigo como medição nova.

`spo2_status`: sensor_unavailable, acquisition_gap, no_contact, insufficient_data, algorithm_invalid ou unvalidated_estimate. `spo2_diagnostics` registra tentativa, validade algorítmica, candidato numérico quando válido e offsets do trecho efetivamente utilizado. `clinically_validated=false` e `quality.validated_sqi=false` permanecem: aceitação pelo algoritmo não comprova qualidade óptica nem precisão clínica. Movimento e baixa perfusão ainda podem produzir números aparentemente válidos.

O app já interpreta o campo `spo2`. O modelo de regras foi ajustado para permitir o número somente com status correspondente e validade algorítmica. As regras NÃO foram publicadas. Se estiverem em uso as regras antigas que exigem not_measured, elas rejeitarão os novos registros: atualizar o trecho correspondente antes de gravar o firmware. O esquema permanece versão 1, com campos adicionais e ampliação de status.

## Verificação necessária

Compilar Esp32.ino com todos os arquivos desta pasta e as bibliotecas descritas no LEIA-ME. Não foi possível localizar o compilador Arduino nesta sessão; a versão 1.2.0 ainda precisa de compilação e ensaio na placa. Não foi feita gravação nem publicação de regras.

Em bancada: verificar ~25 pares/s; ausência de número sem dedo; primeira leitura após estabilização e quatro segundos contínuos; nenhuma leitura atravessando retirada/recolocação, RED saturado, overflow ou erro I2C; ausência de sentinelas no Firebase; leitura no app; recuperação de rede sem criar medições repetidas. Comparar a SpO2 e os tempos com instrumento de referência. Testar movimento deliberado e baixa qualidade de contato. Registrar falsos positivos, falsos negativos e atraso de detecção, além do erro médio. Os testes de regras devem incluir escrita válida, status incompatível, falta de valor, zero, 101 e UID indevido no emulador antes de publicar.

## Proposta para discutir: qualidade, apresentação e eventos

Não é possível separar ruído instrumental e variação fisiológica só pela amplitude da mudança. Pequenos degraus também podem vir da quantização inteira do algoritmo. Não classificar automaticamente 1 ponto percentual como ruído.

1. Qualidade: combinar continuidade, clipping, amplitude pulsátil relativa ao DC, coerência RED/IR e movimento sincronizado. O MPU atual é lido a aproximadamente 1 Hz, insuficiente para caracterizar muitos artefatos rápidos; propor aquisição a 25–50 Hz e trechos PPG brutos para validação. Esses critérios precisam de calibração experimental.
2. Apresentação: experimentar mediana causal de três estimativas de qualidade aceitável para reduzir oscilação visual. Guardar sempre o candidato original e seu horário; não preencher lacunas com valores antigos. Três resultados espaçados cinco segundos implicam memória temporal de dez segundos e podem atrasar mudanças; medir esse atraso.
3. Eventos: avaliar os candidatos originais com qualidade, em paralelo ao valor suavizado. Marcar desvio individual como candidato imediatamente; confirmar persistência com dados novos, mantendo horário inicial e extremos. Um evento curto de boa qualidade deve continuar visível como transitório, mesmo que não se confirme. Referência pessoal não deve absorver rapidamente o próprio evento. Limites clínicos exigem definição específica e podem justificar caminho imediato independente da persistência.
4. Incerteza: qualidade ruim com queda de SpO2 gera aviso de medição inconclusiva/rever sensor, não afirmação de que o corpo está normal. Um outlier de boa qualidade é um evento potencialmente fisiológico, não prova da origem. Validar com referência, postura, atividade e sintomas.

Esses filtros e a classificação de eventos são proposta de próxima etapa, não foram ativados nesta mudança.

## Fundamentação

Badiola et al. (2025), Real-Time Subject-Specific Predictive Modeling of PPG Signals for Artifact-Resilient SpO2 Estimation Under Hypoxia. PubMed: https://pubmed.ncbi.nlm.nih.gov/41374551/ . Estudou 17 voluntários saudáveis em dessaturação controlada, instruídos a permanecer imóveis. Modelagem personalizada baseada nos quatro pulsos limpos anteriores obteve RMSE de 1,28 ponto percentual; os autores condicionam a aplicação a trechos corrompidos à integração com avaliação de qualidade. Isso sustenta investigar contexto individual e qualidade, não valida a mediana de três valores, este módulo MAX30102 ou a classificação de outliers proposta aqui.

A comparative study of accuracy in major adaptive filters for motion artifact removal in sleep apnea tests (2024). PubMed: https://pubmed.ncbi.nlm.nih.gov/38052880/ . Nesse arranjo, filtros adaptativos aumentaram o ruído da estimativa de SpO2 nas condições de baixa amostragem estudadas. Portanto, não presumir que um filtro mais complexo melhora o resultado; comparar com e sem processamento no nosso conjunto de dados.

Implementação de referência: https://github.com/sparkfun/SparkFun_MAX3010x_Sensor_Library/blob/master/src/spo2_algorithm.h . O algoritmo de referência e sua curva não equivalem à calibração clínica do conjunto sensor, montagem e local de uso.
