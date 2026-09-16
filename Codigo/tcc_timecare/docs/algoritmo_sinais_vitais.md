# Tratamento de sinais vitais — baseline-mad-v2

Revisão: 16/09/2026. Escopo: resumo descritivo e triagem estatística retrospectiva por pessoa e parâmetro. Não é detector de reação adversa, prova de ingestão, faixa de normalidade ou modelo preditivo clínico. A montagem do vestível está fora desta revisão.

## Evidência selecionada no PubMed

A busca dirigida priorizou publicações de 2021–2026; o núcleo metodológico abaixo é de 2023–2025. Não se trata de revisão sistemática. Foram conferidos os registros PubMed e, para as operações matemáticas, os métodos dos textos completos vinculados. Não foi localizada validação da combinação exata de parâmetros do TimeCare. Indexação no PubMed não equivale a validação clínica de uma adaptação.

| Fonte | O que sustenta | O que não sustenta |
|---|---|---|
| Bosch, Luther e Ihme (2025), [PMID 40234526](https://pubmed.ncbi.nlm.nih.gov/40234526/), DOI 10.1038/s41597-025-04955-4 | Os métodos centralizam frequência cardíaca pela mediana individual e normalizam por MAD. Sustenta o uso de estatística robusta por participante em dados cardíacos cotidianos. | Estudo de experiências de transporte com ECG; não valida alertas clínicos, SpO₂, temperatura ou o limiar 3,5 do TimeCare. |
| Buljan et al. (2023), [PMID 37749212](https://pubmed.ncbi.nlm.nih.gov/37749212/), DOI 10.1038/s41592-023-02011-w | Os métodos apresentam explicitamente `0,6745 × (x − mediana) / MAD` e `abs(z) > 3,5`. Sustenta a definição matemática e a convenção de triagem robusta. | Aplicação em proteômica, com amostras de referência e de teste. A transferência para sinais vitais e o uso retrospectivo são adaptações experimentais; não se transfere desempenho clínico. |
| Sund Levander e Grodzinsky (2024), [PMID 39685015](https://pubmed.ncbi.nlm.nih.gov/39685015/), DOI 10.3390/healthcare12232393 | Fundamenta considerar condições habituais individuais ao interpretar temperatura e saturação. | Não fornece a fórmula MAD usada aqui nem valida seus tempos, amostragem ou pesos de perfil. Corrige-se a atribuição anterior equivocada a “Bräuninger et al.”. |
| Wilson et al. (2025), [PMID 40242279](https://pubmed.ncbi.nlm.nih.gov/40242279/), DOI 10.1186/s44247-025-00151-x | Documenta divergências entre sensores vestíveis e medidas de referência e impacto sobre alertas. Justifica avaliar qualidade e concordância antes de usar resultados clinicamente. | Não fornece limiares para este hardware nem demonstra eficácia do TimeCare. |

As referências antigas da versão anterior não são usadas como justificativa das constantes atuais. Não se importam limites técnicos do Everion para MAX30102/TMP117.

## Operações implementadas e justificativa

Para cada parâmetro, com amostras numéricas elegíveis `x₁,...,xₙ`:

1. **Média descritiva:** `soma(xᵢ)/n`, apenas no período selecionado. É a definição aritmética de média das observações, sem inferência de normalidade. Não é média ponderada pelo tempo: períodos com coleta mais densa têm maior peso. Valores sinalizados estatisticamente continuam incluídos.
2. **Centro robusto:** `m = mediana(x)`. Para quantidade par, média dos dois valores centrais. Menor sensibilidade a extremos que a média; uso individual em frequência cardíaca documentado por Bosch et al.
3. **Dispersão robusta:** `MAD = mediana(abs(xᵢ − m))`, na unidade do parâmetro. Não confundir com desvio absoluto médio. Fórmula empregada por Buljan et al.
4. **Escore modificado:** `zᵢ = 0,6745 × (xᵢ − m)/MAD`, somente se `MAD > 0`. O fator aproxima o quantil 0,75 da normal padrão e torna a escala comparável à padronização por desvio-padrão sob referência normal. Isso não pressupõe que os sinais sejam normais e não fornece p-valor ou probabilidade de doença.
5. **Sinalização:** `abs(zᵢ) > 3,5`, estritamente. O corte é uma convenção estatística publicada em Buljan et al.; sua utilidade nos três sinais do TimeCare continua experimental. Não é limite fisiológico, intervalo de confiança nem taxa garantida de falsos positivos.

**MAD zero:** a mediana continua disponível, mas os escores são nulos e a tela informa ausência de escore. Retiraram-se os pisos de 1 bpm, 0,5 ponto percentual e 0,1 °C, que alteravam a fórmula sem validação para os sensores. Não se substitui zero por um epsilon arbitrário. Em SpO₂ inteira, MAD zero pode ser frequente; a ausência de classificação não significa normalidade. MAD positivo muito pequeno ainda pode amplificar escores: essa limitação exige avaliação experimental, não arredondamento silencioso.

**Sem descarte por escore:** os valores sinalizados permanecem na mediana/MAD usados na execução e no banco. Retirou-se o segundo cálculo da mediana após excluir outliers. Assim, centro exibido e escores são coerentes e uma variação fisiológica real não é automaticamente tratada como erro de sensor. A robustez não elimina mascaramento por múltiplos extremos ou mudanças persistentes.

## Parâmetros experimentais, sem validação clínica publicada

| Parâmetro | Configuração atual | Interpretação correta |
|---|---|---|
| Janela | `[agora − 30 dias, agora]` | Recorte de engenharia, não duração clinicamente estabelecida. |
| Contagem | Pelo menos 20 amostras únicas por parâmetro | Critério operacional provisório, não cálculo de poder ou tamanho amostral validado. |
| Observação | Ao menos 14 dias completos entre primeira e última amostra | Não exige 14 dias distintos com coleta, regularidade ou independência estatística. |
| Corte | `abs(z) > 3,5` | Convenção metodológica; aplicação fisiológica exploratória. |

Os três primeiros parâmetros foram preservados para continuidade dos experimentos, explicitamente sem atribuição indevida à literatura. Antes de alegar detecção validada, devem ser comparados em análise de sensibilidade. A tela usa “Calibrando” para formação de histórico estatístico; isso não é calibração de sensor.

## Contrato e fluxo dos dados

- `VitalReading.parse` é compartilhado por sinais vitais, ocorrências e PDF.
- Fonte: mapa em `user_test/sinais_vitais`. Instante: `timestamp`, depois `createdAt`, depois chave, conforme disponibilidade. Campo presente mas inválido não é mascarado usando a chave.
- Tempo numérico em **milissegundos** Unix; também aceita ISO 8601. Segundos não são convertidos por heurística; o emissor precisa obedecer ao contrato.
- Aliases iguais nas duas telas: `heartRate/heart_rate/bpm/frequencia_cardiaca`, `spo2/oxigenacao/oxygen`, `temperature/temperatura/temp`.
- Ausência e valores não finitos não viram zero. Um parâmetro inválido não apaga os outros parâmetros válidos do registro. Não há imputação, suavização ou interpolação.
- Registros sem instante interpretável, futuros ou sem métrica reconhecida não entram nas telas/exportação. Duplicatas exatas de instante, valores e marca de simulação são colapsadas na leitura. O algoritmo também elimina duplicatas de instante/valor por parâmetro. Medições conflitantes no mesmo instante não são resolvidas automaticamente.
- Não há limites clínicos de plausibilidade, índice de qualidade PPG ou correção por movimento. Os dados brutos permanecem no Firebase; não existe ainda log persistente de rejeições.
- `simulated=true` ou `source=simulated` identifica simulação. Referências e ocorrências de simulação são calculadas separadamente. O resumo usa registros não sinalizados como simulados, quando existem; caso contrário, usa a série de teste e informa isso. A ausência do marcador não comprova aquisição física.
- Média e referência podem usar janelas distintas: média nos últimos 1/7/30 dias; mediana/MAD na janela de 30 dias. PDF usa data de calendário escolhida e identifica a origem sinalizada, mas não exporta escores.
- Análise retrospectiva do conjunto: inclui a própria leitura avaliada e observações posteriores a ela. Os rótulos podem mudar com novas amostras e não são persistidos. Não é detecção prospectiva, nem avaliação causal.

## Validação e limites

Os testes cobrem cálculo manual de mediana/MAD/escore, histórico padrão mínimo, fronteiras temporais, MAD zero, MAD positivo pequeno, dados não finitos, duplicatas, aliases, leitura parcial e simulação. Testes sintéticos demonstram conformidade do software, não sensibilidade clínica.

Plano experimental antes de validar detecção: comparar janelas de 14/30/60 dias, mínimos de 20/40/60 observações e cortes de 3/3,5/4; medir disponibilidade de escore e taxa de sinalização em séries sintéticas com diferentes resoluções, densidades, ruído, extremos e mudança persistente. Esses valores são candidatos de experimento, não recomendações clínicas. Separar ajuste e avaliação; em avaliação prospectiva, usar somente dados anteriores à leitura e divisão temporal por participante, sem vazamento de informação.

Para aquisição física futura, comparar cada parâmetro com instrumento de referência, registrar local e condições de medição e relatar viés e limites de concordância com tratamento das medidas repetidas. Não converter temperatura cutânea em temperatura central sem modelo validado. SpO₂ é limitada superiormente e geralmente quantizada; distribuições assimétricas e MAD zero restringem a triagem bilateral.

Idade, sexo ao nascer, gestação, condições e medicamentos permanecem como contexto. Não há pesos clínicos, referência de coorte, período automático de adaptação após alteração de dose, NEWS2 ou inferência de reação adversa. O cliente atual ainda usa usuário fixo e não autentica suas chamadas REST; regras do banco em produção não foram verificadas nesta revisão.

## Rastreabilidade

- Algoritmo: `lib/services/vital_baseline_algorithm.dart`, versão `baseline-mad-v2`.
- Entrada compartilhada: `lib/services/vital_reading.dart`.
- Testes: `test/vital_baseline_algorithm_test.dart` e `test/vital_pipeline_test.dart`.
- Artigo: `docs/artigo_revisado.tex`.
- Referências adicionais verificadas: `docs/references_metodo.bib`.

A bibliografia original `references.bib`, o modelo SBC e as imagens não foram fornecidos. As novas entradas devem ser mantidas junto à bibliografia original; não foram inventados dados bibliográficos para as referências antigas.
