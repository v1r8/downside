# Downside para Windows

Porte do app Downside (macOS) para Windows, em **Flutter**. Convive com a
versão Mac no mesmo repositório, sem tocar no código Mac (que fica em
`../Sources`).

## Como funciona o ciclo (igual ao Mac)

Não se builda nada à mão: mudar o arquivo `VERSION` neste diretório dispara o
workflow `.github/workflows/windows-release.yml`, que no GitHub:

1. Builda o app Flutter para Windows (release).
2. Empacota num instalador (`DownsideSetup-<versão>.exe`) com Inno Setup.
3. Gera o `appcast-win.xml` (feed do auto-update, formato Sparkle/WinSparkle).
4. Publica tudo numa Release de **tag fixa `windows`** (com `make_latest:false`,
   para não interferir no canal de atualização do Mac).

A **primeira instalação é manual** (baixar o `DownsideSetup-*.exe` da Release
`windows`). Depois disso, o app se atualiza sozinho via WinSparkle.

## Marcos

- **M0** (atual): base — bandeja, janela e auto-update funcionando.
- **M1**: painel flutuante + hot corners + Downloads.
- **M2**: clipboard + previews.
- **M3**: pilhas + fichário + IA (Ollama→Claude).
- **M4**: busca + OCR nativo do Windows.
- **M5**: paridade de design + polish.

## Assinatura do auto-update

O canal usa assinatura DSA (WinSparkle). A chave privada fica no segredo do
repositório `WIN_SPARKLE_PRIVATE_KEY` (a ser configurado); a pública é embutida
no app. Enquanto a assinatura não estiver ativa, o auto-update roda sem
verificação (apenas durante a validação inicial do M0).
