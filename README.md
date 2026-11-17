# Neve no Mac

App nativo para macOS 13 ou superior, feito em Swift, AppKit e SwiftUI, sem dependências externas. Inspiração visual: Reel [@koiart_en](https://www.instagram.com/reel/DfzbIp2tbLc/).

Flocos caem **sobre todas as páginas e janelas abertas**, inclusive em tela cheia, e desaparecem ao sair pela borda inferior. A neve, o boneco e o trator limpa-neve são uma sobreposição transparente; o wallpaper atual permanece como está. Os flocos são animados na GPU com Core Animation.

O acúmulo nas bordas visíveis das janelas, o boneco e o limpa-neve vêm ativos e podem ser desligados separadamente. As pilhas têm contorno irregular e acompanham as janelas em coordenadas locais. Sacudir ou fechar uma janela solta parte da neve. O boneco e o limpa-neve são desenhos próprios feitos em código.

## Usar

Execute `zsh scripts/build-app.sh` e abra `dist/Neve no Mac.app`. Clique no floco da barra de menus para abrir diretamente o painel de ajustes azul-escuro/ciano. Fechar o painel mantém o efeito ativo.

O pacote inclui um ícone próprio de floco de neve ciano sobre azul-marinho, nas resoluções de 16 a 1024 pixels. Para encontrá-lo pelo Spotlight com esse ícone, copie `Neve no Mac.app` para **Aplicativos** pelo Finder e abra o app uma vez. Depois pesquise **Neve no Mac**. A indexação e a atualização do cache de ícones são feitas pelo macOS e podem levar algum tempo; o projeto não apaga caches do sistema. A compilação gera o `.icns` a partir de desenho vetorial em `scripts/make-icon.swift`, sem arquivos de imagem externos, e não instala nem reinicia o app em uso.

O vento tem duas opções: **De cima para baixo**, selecionada inicialmente, e **Lateral**. A queda vertical tem uma pequena variação natural sem atravessar a tela na diagonal. As preferências antigas são preservadas ao atualizar. O recurso de criar e lançar bolas de neve foi removido; a sobreposição deixa todos os cliques passar.

Quantidade, velocidade, vento, profundidade, boneco e limpa-neve automático são ajustáveis. As preferências ficam no UserDefaults do app. Há uma sobreposição por monitor, atualizada quando monitores são conectados ou removidos. O efeito pausa quando a sessão ou a tela dorme e reduz os flocos no modo de pouca energia. Os atalhos Command+, e Command+Q abrem os ajustes e encerram o app quando ele está ativo.

Os botões **Nesta janela**, **Em todas** e **Só na base da tela** enviam tratores à janela em primeiro plano, a todas as bordas visíveis ou ao chão. Os tratores acompanham a janela, respeitam a oclusão e limpam apenas o seu próprio trecho. Durante o movimento de janelas, a posição é consultada a 60 Hz; a atualização visual não usa animações de atraso.

## Protetor de tela

O módulo nativo `Neve no Mac.saver` usa o mesmo motor visual para mostrar neve, boneco e trator. Para compilar e instalar com o fundo escolhido:

```sh
zsh scripts/install-saver.sh /caminho/para/fundo.jpg
```

O módulo fica em `~/Library/Screen Savers/Neve no Mac.saver`. Ele é selecionado em **Ajustes do Sistema → Imagem de Fundo → Protetor de Tela → Personalizado → Outros**. O instalador preserva uma cópia da versão anterior em `~/Library/Application Support/NeveMac/Backups` e copia as preferências visuais atuais para o módulo. Para atualizar essa cópia após novos ajustes, execute o instalador novamente.

O protetor foi validado em tela cheia no macOS. Ele não desenha sobre o campo de senha ou sobre a tela de login do FileVault. O projeto não altera senha, Touch ID, políticas de bloqueio ou o tempo de início automático do protetor.

## Wallpaper de referência

O desenho de referência é o **Winter**, do [KoiArt](https://koiart.app/). Links públicos do autor:

- [Imagem principal, 1586 × 992](https://koiart.app/wallpapers/snow.jpg)
- [Night, 960 × 600](https://koiart.app/wallpapers/day/snow-night.jpg)
- [Dusk, 960 × 600](https://koiart.app/wallpapers/day/snow-dusk.jpg)

Os wallpapers e as capturas de referência não são redistribuídos neste repositório. O app de neve não aplica wallpaper. O protetor inclui somente a imagem fornecida ao instalador para exibi-la como fundo; sem esse argumento, usa um fundo azul-escuro. As imagens de referência continuam sendo do autor original. Este projeto é independente e não é afiliado ao KoiArt.

## Escopo desta versão

Esta é uma implementação própria da neve vista no vídeo. O boneco é decorativo. Não inclui presentes, Papai Noel, árvores de Natal, luzes ou outros climas. O limpa-neve percorre as bordas das janelas e a base da tela. A neve também usa a borda do Dock quando o sistema expõe uma geometria válida; Dock oculto e widgets não têm integração dedicada. O protetor usa apenas a base da tela, sem consultar as janelas abertas durante o bloqueio.

A lista de janelas é consultada apenas quando os recursos de acúmulo ou boneco estão ativos, para obter posição, tamanho e ordem. O app não captura imagens das janelas, não solicita gravação da tela ou acessibilidade, não usa rede e não inicia com o sistema.

## Verificar

```sh
zsh scripts/test.sh
swift build -c release
.build/release/NeveMac --render-preview /tmp/neve-preview.png
.build/release/NeveMac --memory-check
python3 scripts/security-check.py
```

Os testes cobrem o modo de neve contínua sem acúmulo, oclusão entre janelas, coordenadas em monitores à esquerda/acima, acompanhamento imediato, desprendimento da neve, limites e contorno irregular do acúmulo, rotas dos tratores, limpeza, migração das preferências e os dois modos de vento.

`NeveCore` contém a simulação; `NeveRendering`, o desenho compartilhado; `NeveMac`, o app e os ajustes; `NeveScreenSaver`, a integração com o protetor nativo. `scripts/verify-saver.swift` verifica o carregamento do bundle e produz uma imagem de referência.

O bundle é assinado localmente para testes. Distribuição para outros Macs exige a assinatura e notarização habituais da Apple.

A revisão de memória e segurança está em [docs/REVIEW.md](docs/REVIEW.md). O teste de memória cria uma cena fora da tela, sem ler preferências ou abrir janelas, e verifica o limite de camadas ociosas e a liberação da cena.
