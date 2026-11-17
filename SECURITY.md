# Segurança e privacidade

O aplicativo não faz requisições de rede, não envia telemetria e não usa dependências externas. Ele consulta a geometria e a ordem das janelas para posicionar a neve. Não captura o conteúdo das janelas. O protetor de tela usa apenas o fundo fornecido pelo usuário e a base da tela.

Preferências ficam localmente no UserDefaults. O projeto não solicita gravação de tela ou acessibilidade, não instala serviços privilegiados e não altera senha, Touch ID, FileVault ou a política de bloqueio. Os scripts de instalação atuam somente no protetor deste projeto, no diretório do usuário, e preservam uma cópia da versão anterior.

Arquivos compilados, wallpapers, capturas, credenciais e relatórios brutos de memória ficam fora do Git. Antes de publicar alterações, revise os arquivos preparados e execute:

```sh
git add .gitignore Package.swift README.md SECURITY.md Sources Tests scripts docs
python3 scripts/security-check.py
zsh scripts/test.sh
swift build -c release
.build/release/NeveMac --memory-check
```

A checagem automática examina os blobs preparados no Git, recusa links simbólicos e recursos fora da lista permitida, e procura padrões de credenciais e caminhos pessoais. Ela complementa a revisão manual; não demonstra ausência de todas as vulnerabilidades possíveis.

O bundle tem assinatura local de desenvolvimento. Uma distribuição para terceiros deve passar pela assinatura e notarização da Apple. Carregue apenas módulos de protetor de tela cuja origem você conhece: um arquivo `.saver` contém código executável.

Para comunicar uma vulnerabilidade, use o relato privado na aba **Security**, se estiver habilitado, ou o contato público do mantenedor no perfil do GitHub. Não publique credenciais ou dados pessoais em uma issue.
