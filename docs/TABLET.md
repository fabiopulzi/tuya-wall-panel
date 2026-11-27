# Instalando no tablet (Galaxy Tab S2 · LineageOS 21)

Passo a passo para rodar o painel no tablet pela primeira vez. Leva uns 15 minutos,
quase tudo é download.

## 1. No Mac: terminar o Android SDK (uma vez)

O Flutter, o Java 17 e as ferramentas do Android já estão instalados. Falta baixar as
peças do SDK — esse comando pede para **você aceitar as licenças do Google** (digite `y`):

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
sdkmanager --sdk_root=/opt/homebrew/share/android-commandlinetools "platform-tools" "platforms;android-36" "build-tools;36.0.0"
flutter doctor --android-licenses
```

Confira: `flutter doctor` deve mostrar `[✓] Android toolchain`.

## 2. No tablet: ativar a depuração USB (uma vez)

1. **Configurações → Sobre o tablet** → toque 7 vezes em **Número da versão**
   (aparece "Você agora é um desenvolvedor").
2. **Configurações → Sistema → Opções do desenvolvedor** → ative **Depuração USB**.
3. Ligue o tablet no Mac pelo cabo USB e, no tablet, toque em **Permitir**
   (marque "Sempre permitir deste computador").
4. O tablet precisa estar no **mesmo Wi-Fi** dos interruptores (não a rede de convidados).

Confira no Mac:

```bash
flutter devices
```

Deve aparecer algo como `SM T710 (mobile) • ... • android-arm`.

## 3. Rodar o painel

Na pasta do projeto:

```bash
flutter run --release --dart-define-from-file=tuya_credentials.json
```

A primeira compilação demora alguns minutos (o Gradle baixa dependências).

> No SM-T710 com LineageOS o `flutter run` compila mas falha ao instalar com
> `splice failed: EINVAL`. Instale sem streaming e abra o app pelo tablet:
>
> ```bash
> flutter build apk --release --dart-define-from-file=tuya_credentials.json
> adb install -r --no-streaming build/app/outputs/flutter-apk/app-release.apk
> ```

## 4. O que conferir

- [ ] O painel abre em tela cheia, deitado, com os cômodos da sua casa.
- [ ] No topo aparece **"Rede local 29/31"** (verde quando todos estão na rede; âmbar se
      alguns estiverem só pela nuvem). Em ~10 s ele deve subir até ~29.
- [ ] Tocar numa luz responde na hora (comando local, sem passar pela nuvem).
- [ ] **Teclas em paralelo:** desligue a "Cozinha entrada" — a outra tecla da cozinha deve
      atualizar em menos de 1 s (o próprio interruptor avisa o painel).
- [ ] Apertar um interruptor na parede atualiza o card no painel na hora.
- [ ] Feche e abra o app: ele abre instantaneamente (cache) e depois sincroniza.
- [ ] **Sem internet:** desligue a internet do roteador (Wi-Fi ligado) — as luzes
      continuam respondendo pelo painel.

## Personalizar o painel

Botão ⚙ no canto superior direito (ou o ⚙ dentro de um cômodo):

- **Arraste** uma tecla pela alça ⠿ (ou segure a linha) para reordenar, solte sobre outro
  cômodo na lista da esquerda para mover, ou sobre **Ocultas** para tirar do painel
  (bom para as teclas em paralelo).
- Toque no nome do cômodo ou no lápis da tecla para **renomear**; no ícone do cômodo para trocá-lo.
- **Novo cômodo**, **Excluir** (as teclas vão para Ocultas) e **Restaurar Smart Life**.
- No painel, **segure uma tecla** para renomear ou ocultar direto.

Nada disso muda o app Smart Life. Fica salvo no tablet e sobrevive a versões novas do app
(`adb install -r`); só se perde se o app for desinstalado ou os dados dele forem apagados.

## Modo painel (aba Painel em ⚙)

- **Protetor de tela:** relógio em tela preta depois de 1, 2, 5 ou 10 min sem toque (ou nunca).
  O relógio muda de lugar a cada minuto para não marcar a tela. O primeiro toque só acorda.
- **Brilho:** em uso, segue o brilho do Android (ligue o *brilho adaptativo* lá, se quiser);
  no protetor, fica no nível escolhido, e mais escuro das 22h às 6h.
- **Iniciar com o tablet:** toque em **Definir** e escolha **Painel Casa** como app de tela
  inicial (“Sempre”). Assim ele abre sozinho quando o tablet liga e no botão Home.
  Para usar outros apps, **Ajustes do Android** → Apps; para desfazer, **Trocar** e escolha
  o launcher original (Trebuchet / Launcher3).

## 5. Instalar de vez (sem o cabo)

```bash
flutter build apk --release --dart-define-from-file=tuya_credentials.json
adb install -r --no-streaming build/app/outputs/flutter-apk/app-release.apk
```

O app aparece no tablet como **Painel Casa**.

> As chaves da Tuya ficam embutidas nesse APK. Não compartilhe o arquivo `.apk`.

## Se algo não funcionar

| Sintoma | O que fazer |
|---|---|
| `flutter devices` não mostra o tablet | Troque o cabo (alguns só carregam), reautorize a depuração USB |
| Topo mostra "Via nuvem" / 0 locais | Confirme que o tablet está no Wi-Fi da casa, não em rede de convidados |
| Um dispositivo específico nunca fica local | Normal se ele estiver longe do roteador (ex.: *Interruptor Cozinha*, que hoje não responde na rede). Ele continua funcionando pela nuvem |
| O Smart Life fica mais lento para alguns aparelhos | Cada interruptor aceita poucas conexões locais; com o painel conectado, o Smart Life usa a nuvem — funciona igual |

## Ferramentas de diagnóstico (no Mac, mesma rede)

```bash
dart run tool/scan_lan.dart          # quais dispositivos anunciam na rede, IP e versão
dart run tool/local_status.dart      # lê o estado de cada um pela rede (não aciona nada)
dart run tool/hybrid_check.dart      # roda a pilha completa do app, sem interface
dart run tool/check_cloud.dart       # a casa como a nuvem vê
```
