# Revisão do artigo e do tratamento de dados

Data: 16/09/2026. Base: texto fornecido, código Flutter atual, testes e firmware da caixa em `Codigo/Esp32/Esp32.ino`. A montagem em standby não foi usada como critério de falha. Não foram acessados nem alterados registros remotos no Firebase.

## Correções no artigo

- Separação entre software implementado, integração física prevista e validação futura.
- Cadastro de medicamentos descrito com os campos reais e um estado atual por registro, sem suposto histórico completo de doses. Ação manual disponível: marcar atraso.
- Reconhecimento dos alarmes já implementados no firmware da caixa, distinguindo-os das notificações do celular e do vestível.
- Precisão sobre períodos, limite visual de 30 registros, PDF diário, usuário fixo e chamadas REST.
- Fórmula, referência exibida e limites alinhados à nova versão do algoritmo.
- Fundamentação específica com quatro artigos de 2023–2025 indexados no PubMed; referências novas em arquivo BibTeX separado.
- Ajustes de redação, pacote `amsmath` necessário para `operatorname`, remoção de pacote duplicado, afiliação dos autores consistente com a única instituição informada e imagens opcionais com dimensões limitadas.
- Nomes de hardware uniformizados conforme a tabela fornecida (ESP32 DevKitC e TMP117). Isso é correção de consistência interna, não confirmação de montagem ou aquisição desses componentes.

O dado da Sandbox foi delimitado à população investigada e ao conjunto de medicamentos de saúde mental, evitando atribuir crescimento uniforme a antidepressivos e ansiolíticos. A divulgação consultada informa inclusive queda no uso de ansiolíticos: [CRF/SE](https://crfse.org.br/noticia/1810/levantamento-aponta-aumento-de-18-6-no-uso-de-medicamentos-para-saude-mental-nos-ultimos-dois-anos). O estudo de TDAH foi contextualizado como população de uma organização de saúde da Califórnia: [Chung et al., PMID 31675080](https://pubmed.ncbi.nlm.nih.gov/31675080/).

## Código

Removidos pisos arbitrários de MAD e recálculo do centro após exclusão de outliers. MAD zero é explicitamente não classificável. Centro exibido e escores usam a mesma distribuição. Acrescentados tratamento de datas futuras, não finitos e duplicatas, interpretação compartilhada de aliases e identificação/separação de dados simulados. A exportação inclui origem sinalizada e versão do algoritmo, sem se apresentar como relatório de escores.

## Verificação realizada

- 14 testes direcionados aprovados: dois do arquivo original atualizado e doze novos testes de tratamento de dados.
- Análise estática dos sete arquivos Dart de implementação/teste alterados: nenhuma ocorrência.
- Conferência estrutural do LaTeX: ambientes, chaves e referências internas.
- Não houve validação clínica, ensaio físico ou execução de geração de dados contra o Firebase.

## Limites da entrega

Não foram fornecidos `references.bib`, `sbc-template.sty`, `sbc.bst` nem as imagens do artigo, e não há compilador LaTeX disponível. Por isso, não foi possível compilar e verificar visualmente o artigo completo. As chaves bibliográficas originais foram preservadas; sua resolução depende da bibliografia original. A auditoria das fontes concentrou-se na metodologia matemática e nas afirmações revisadas, não constitui conferência integral de todas as referências antigas.

Os testes executados são os relacionados à alteração, não a suíte completa: o projeto ainda contém um teste de contador padrão em `test/widget_test.dart` que não representa a aplicação atual. A interface e o PDF não foram inspecionados visualmente nesta revisão.

O conjunto mínimo de 20 amostras/14 dias/30 dias foi mantido como configuração experimental, sem alegar validação publicada. O método pode ser defendido como exploração estatística; não como detecção clínica validada nos três parâmetros. Consulte a matriz de evidência em `algoritmo_sinais_vitais.md`.
