# Neve no Windows — implementação experimental

Versão nativa separada em C#/.NET 10, WPF e Win32. O alvo principal é Windows 11 x64/ARM64. A compatibilidade pretendida com Windows 10 fica limitada às edições e versões atualmente suportadas pelo runtime .NET 10 (LTSC/Enterprise); não há promessa de suporte geral a Windows 10 Home/Pro. Consulte a [matriz oficial da Microsoft](https://learn.microsoft.com/en-us/dotnet/core/install/windows).

O código compila e os testes do núcleo passam. **A interface ainda não foi executada em uma máquina Windows.** A tarefa [#1](https://github.com/lucas375/neve-no-mac/issues/1) permanece aberta para essa validação; a implementação não deve ser tratada como uma versão Windows já validada para distribuição.

## Compilar e executar

Instale o [SDK .NET 10 oficial](https://dotnet.microsoft.com/download/dotnet/10.0). Na pasta `windows`, execute no PowerShell:

```powershell
.\build.ps1 -Runtime win-x64
.\artifacts\win-x64\NeveNoWindows.exe
```

Para Windows em ARM64, use `-Runtime win-arm64` e execute o arquivo correspondente em `artifacts\win-arm64`. Os arquivos de saída devem permanecer juntos. A publicação padrão depende do **.NET Desktop Runtime 10** da arquitetura correspondente; o SDK também o fornece no Windows. O script não instala componentes, não pede administrador e não altera configurações do sistema. Uma política local pode exigir a execução manual dos comandos abaixo; não é necessário reduzir a política de execução do PowerShell.

```powershell
dotnet run --project Neve.Core.Checks/Neve.Core.Checks.csproj -c Release
dotnet publish Neve.Windows/Neve.Windows.csproj -c Release -r win-x64 --self-contained false -o artifacts/win-x64
```

O app permanece na bandeja. Clique no floco de neve para abrir os ajustes; fechar os ajustes mantém a neve. Use **Sair** na bandeja ou no painel para encerrar. Não há instalação automática nem inicialização com o Windows.

## Recursos implementados

- Sobreposição transparente sobre janelas, sem roubar foco e com passagem de cliques.
- Uma cena por monitor, até oito monitores, com posicionamento físico Win32 e conversão para unidades WPF conforme o DPI de cada janela de sobreposição.
- Acúmulo irregular em trechos visíveis das bordas; a neve acompanha imediatamente a geometria consultada. O código consulta mais frequentemente enquanto o botão esquerdo do mouse está pressionado.
- Tratores na janela externa que estava em primeiro plano, em todas as bordas ou só na base. As rotas respeitam a oclusão e acompanham a posição local das janelas.
- Boneco decorativo, quantidade/velocidade/profundidade e tratores automáticos.
- Duas opções de vento: **De cima para baixo**, padrão, e **Lateral**. Sem bolas de neve ou gestos de captura do mouse.
- Ajustes azul-marinho/ciano e preferências locais em `%LOCALAPPDATA%\NeveNoWindows\settings.json`.
- Suspensão do temporizador e ocultação das sobreposições ao pausar, bloquear ou suspender a sessão. Redução da frequência e quantidade de flocos no modo de economia de bateria.

O núcleo limita cada monitor a 1800 partículas, 64 superfícies de janelas, 2048 amostras por superfície e 128 tratores. O desenho usa geometrias vetoriais e pincéis reutilizáveis; os caminhos de neve são atualizados em intervalos ou imediatamente quando a geometria muda. Esses limites evitam crescimento ilimitado dos dados do modelo; **não são uma medição do consumo gráfico real do Windows**.

## Diferenças e limites atuais

- Não inclui protetor de tela Windows (`.scr`) ou animação na tela de login/bloqueio seguro. O efeito é ocultado ao bloquear a sessão. Nenhuma configuração de segurança é alterada.
- Não implementa o gesto de sacudir janelas para desprender neve; fechar uma janela solta partículas. Não há integração específica com widgets ou barra de tarefas.
- Monitores/DPI alterados recriam a cena e limpam seu acúmulo. A troca de desktop virtual é filtrada pela visibilidade/cloaking exposta pelo Windows e ainda exige teste real.
- Bordas no limite superior da tela e janelas totalmente cobertas não recebem uma pilha visível. Aplicações com regras próprias de exibição, jogos em tela cheia exclusiva e overlays de terceiros exigem validação específica.
- O executável de desenvolvimento não possui assinatura de distribuição. A geração para terceiros ainda exige revisão em Windows e uma estratégia de assinatura/instalação adequada.

## Verificações realizadas

Ambiente: macOS arm64, SDK .NET 10.0.404 isolado, sem instalar runtime Windows no sistema.

- 10 verificações executáveis do núcleo passaram: oclusão; movimento e tratores; redimensionamento extremo; modos de vento; limpeza por superfície; rotas e fechamento; acúmulo irregular limitado; queda sem acúmulo; limites sob abertura/fechamento repetidos; normalização e persistência dos ajustes.
- Cross-build WPF/Win32 Release passou com zero avisos e zero erros.
- Publicações por RID `win-x64` e `win-arm64` geradas e tipos dos executáveis verificados. Um `dotnet build` no Mac, sozinho, não equivale a gerar um executável publicável para Windows; use `dotnet publish -r ...`.
- Código e arquivos preparados passaram pela checagem de segurança do repositório. Nenhum binário, preferência pessoal ou relatório bruto foi incluído no Git.

Os 16 testes e a medição de memória descritos no relatório principal são da versão macOS; não validam esta interface Windows.

Para repetir os testes do núcleo em qualquer plataforma com .NET 10:

```sh
dotnet run --project windows/Neve.Core.Checks/Neve.Core.Checks.csproj -c Release
```

## Validação pendente em Windows real

- [ ] Inicialização e encerramento pela bandeja; retomar após pausa/suspensão/bloqueio sem perda de cliques.
- [ ] Passagem de cliques e foco: teclado, rolagem e arraste dos aplicativos abaixo continuam funcionando.
- [ ] Janelas em primeiro plano, cobertas, minimizadas e fechadas; botão **Nesta janela** com os ajustes ativos.
- [ ] Monitores à esquerda/acima, DPI misto, hotplug e desktops virtuais.
- [ ] Vento vertical/lateral, neve irregular, boneco e tratores na escala correta.
- [ ] Consumo de memória, GPU e CPU durante uso prolongado e movimento de janelas.
- [ ] Executar e registrar versão/edição do Windows, arquitetura e runtime; validar separadamente qualquer edição Windows 10 pretendida.

## Referências oficiais

- [Windows em camadas e passagem de cliques com WS_EX_TRANSPARENT](https://learn.microsoft.com/en-us/windows/win32/winmsg/window-features)
- [Limites visíveis das janelas e DWMWA_EXTENDED_FRAME_BOUNDS](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowrect)
- [Atributos de cloaking do DWM](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute)
- [DPI por monitor no WPF](https://learn.microsoft.com/en-us/windows/win32/hidpi/declaring-managed-apps-dpi-aware)
- [Compilação Windows em outro sistema com EnableWindowsTargeting](https://learn.microsoft.com/en-us/dotnet/core/project-sdk/msbuild-props#enablewindowstargeting)
