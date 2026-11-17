# Revisão anterior à primeira publicação

Data: 16 de novembro de 2026. Ambiente de verificação: macOS 26.6.2, arm64. Escopo: código deste aplicativo e conteúdo preparado para o repositório público; não foi feita uma auditoria dos outros aplicativos do computador.

## Memória

O comando `.build/release/NeveMac --memory-check` exercita uma cena de 3840 × 2160, densidade máxima, 20 janelas, tratores, fechamento das janelas e limpeza. Repete seis ciclos de 180 quadros, com descarte de objetos temporários entre quadros. O teste não abre janelas e não lê preferências pessoais.

| Medida | Antes | Depois |
| --- | ---: | ---: |
| Camadas retidas após limpeza | 238 | 38 |
| RSS no fim do sexto ciclo | 29,69 MiB | 29,45 MiB |
| Crescimento de RSS do segundo ao sexto ciclo | 0,28 MiB | 0,27 MiB |
| Cena liberada ao encerrar | Sim | Sim |

O ganho comprovado é a redução da retenção de camadas ociosas. A pequena diferença de RSS fica sujeita à variação do alocador; não representa uma redução equivalente da memória total do computador. A medição fora da tela não inclui todo o consumo do compositor/GPU em um desktop real nem substitui uma observação de longa duração.

Correções realizadas:

- O conjunto reutilizável de camadas de neve desprendida retém no máximo 32 camadas ociosas.
- Movimento normal das janelas reaproveita o armazenamento das pilhas; o redimensionamento faz a reamostragem.
- Cada borda de janela usa no máximo 2048 amostras, inclusive com dimensões excepcionalmente grandes.
- A contagem de flocos não cria uma lista intermediária a cada quadro.
- Pausar o efeito, suspender a tela ou sair da sessão também pausa o emissor gráfico.

O `leaks` do macOS **não terminou zerado**: apontou 288 blocos / 18.816 bytes em três ciclos de `NSXPCConnection`, com pilhas de alocação de AppIntents/LinkServices da Apple. Um processo mínimo que apenas inicializa AppKit também apontou os mesmos três ciclos (280 blocos / 18.432 bytes). Não foram encontrados ciclos com raiz em objetos do projeto nesse teste, e a referência fraca da cena confirmou sua liberação. Esse resultado é registrado como uma limitação do teste; não equivale a uma certificação de ausência de vazamentos.

## Segurança e conteúdo público

A revisão manual cobriu os alvos Swift, armazenamento das preferências, consultas à lista de janelas, scripts de compilação/instalação e seleção dos arquivos publicados.

- Nenhuma dependência externa, requisição de rede, telemetria, captura do conteúdo de janelas ou armazenamento de credenciais no aplicativo.
- Ajustes numéricos decodificados são limitados aos intervalos suportados.
- A instalação recusa um destino que seja link simbólico ou pertença a outro bundle e mantém backup da versão anterior.
- Novas compilações sem imagem não preservam silenciosamente um wallpaper de uma compilação anterior.
- `dist`, `.build`, wallpapers, capturas e relatórios brutos de memória não entram no Git.
- O histórico usa o endereço `noreply` do GitHub, em vez de um endereço de e-mail pessoal.

`scripts/security-check.py` examina exatamente os blobs preparados no índice do Git. Procura padrões de chaves/tokens/senhas, URLs com credenciais e caminhos pessoais, recusa links simbólicos e limita a publicação a código e documentação. A própria checagem foi exercitada em um repositório temporário: aceitou conteúdo limpo e recusou uma credencial sintética preparada no índice mesmo com o arquivo de trabalho limpo; também recusou um link simbólico.

Resultado da revisão inicial: nenhum segredo correspondente aos padrões ou recurso privado/terceiro nos arquivos preparados para publicação. Isso não garante ausência de todas as vulnerabilidades possíveis. Consulte [SECURITY.md](../SECURITY.md) para o escopo de privacidade e o procedimento de revisão.

## Validação

- 16 testes de simulação, migração de ajustes, limites de memória e dados inválidos passaram.
- Compilações de produção do aplicativo e do protetor de tela verificadas.
- Assinaturas locais dos bundles verificadas.
- Medição de memória aprovada nos limites declarados pelo teste.
- Sintaxe dos scripts e conteúdo preparado no Git verificados antes da criação do repositório.
