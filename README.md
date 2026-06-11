# Downside

Encoste o mouse num canto da tela e veja na hora o conteúdo de uma pasta
da sua escolha (Downloads, por padrão) — num painel flutuante leve, com a
cara dos paineis nativos do macOS.

## Funcionalidades

- **Canto ativo**: leve o mouse ao canto configurado (padrão: inferior
  direito) e o painel desliza para dentro da tela. Afaste o mouse e ele
  some sozinho. Há um botão de 📌 para mantê-lo aberto.
- **Multi-seleção como no Finder**:
  - clique simples seleciona, clique duplo abre;
  - ⌘-clique alterna itens, ⇧-clique seleciona intervalo;
  - **clicar e arrastar em área vazia** desenha o retângulo de seleção;
  - ⌘A seleciona tudo, Esc fecha o painel.
- **Arrastar para fora**: arraste um arquivo do painel para o Finder,
  Mail, etc.
- **Menu de contexto**: Abrir, Mostrar no Finder, Copiar e Mover para o
  Lixo — agindo sobre toda a seleção.
- **Thumbnails Quick Look** com cache, atualização da pasta em tempo real
  (kqueue) e limite de 300 itens exibidos para ficar sempre rápido.
- **Design nativo**: app de barra de menus (sem ícone no Dock), painel
  não-ativante (não rouba o foco do app atual), material translúcido do
  sistema. Compilando com Xcode 26 no macOS Tahoe, o fundo usa o
  **Liquid Glass** nativo automaticamente.
- **Auto-update via Sparkle** + GitHub Releases: cada nova versão que
  publicarmos chega para o app instalado.

## Como compilar e rodar

Requisitos: macOS 14+, Xcode 16+ (Xcode 26 para o visual Liquid Glass) e
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Downside.xcodeproj
```

Em seguida, ⌘R no Xcode. O app aparece na **barra de menus** (ícone de
bandeja). Na primeira leitura da pasta Downloads o macOS pedirá permissão
de acesso — é a permissão normal de privacidade (TCC), conceda uma vez.

> O `.xcodeproj` não é versionado: ele é gerado a partir de `project.yml`.
> Rode `xcodegen generate` de novo sempre que esse arquivo mudar.

## Configurações

Ícone da barra de menus → **Configurações…**:

- pasta monitorada (qualquer pasta, começa em `~/Downloads`);
- canto da tela e atraso de ativação (50–500 ms);
- abrir ao iniciar a sessão;
- atualizações automáticas e verificação manual.

## Atualizações automáticas (Sparkle)

O app aponta para o appcast publicado nos releases deste repositório
(`SUFeedURL` no `Resources/Info.plist`). Para ativar o ciclo completo,
uma única configuração inicial é necessária:

1. Gere o par de chaves EdDSA com a ferramenta do Sparkle (baixe o
   [Sparkle](https://github.com/sparkle-project/Sparkle/releases) e rode
   `./bin/generate_keys`). Guarde a chave privada com segurança.
2. Cole a chave **pública** em `SUPublicEDKey` no `Resources/Info.plist`.
3. Crie o secret `SPARKLE_PRIVATE_KEY` no repositório (Settings →
   Secrets and variables → Actions) com a chave **privada**.
4. Publique uma versão criando uma tag:

   ```sh
   git tag v0.1.0 && git push origin v0.1.0
   ```

O workflow `.github/workflows/release.yml` compila o app, zipa, assina o
appcast e anexa tudo ao release. Os apps instalados detectam a nova
versão e se atualizam sozinhos.

> **Assinatura da Apple**: o build do CI sai sem Developer ID (suficiente
> para uso próprio; o Gatekeeper pode exigir clique-direito → Abrir na
> primeira execução). Para distribuição ampla, adicione assinatura
> Developer ID + notarização ao workflow.

## Arquitetura

```
Sources/
  App/        ponto de entrada, estado global e preferências
  HotCorner/  detecção do canto ativo (polling leve, sem permissões extras)
  Panel/      NSPanel não-ativante + controle de animação/auto-ocultar
  Views/      painel SwiftUI: grid, seleção, rubber band, células
  Models/     monitor da pasta (kqueue) e thumbnails (Quick Look)
  Settings/   janela de configurações
  Updates/    integração com o Sparkle
```

## Roadmap

- Quick Look com barra de espaço
- Arrastar **vários** arquivos selecionados de uma vez (drag session AppKit)
- Renomear inline e "Abrir com…"
- Ícone próprio do app
- Atalho de teclado global para abrir o painel
- Múltiplas pastas / abas
