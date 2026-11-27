# Tuya Wall Panel

Central de comando de parede para uma casa automatizada com dispositivos **Tuya / Smart Life**,
pensada para rodar 24h num tablet Android fixo na parede.

> Alvo inicial: Samsung Galaxy Tab S2 8.0 (SM-T710) com LineageOS 21 (Android 14),
> tela 2048×1536 (≈ 1024×768 dp em paisagem).

## Objetivos

- Controlar os ~40 dispositivos da casa (interruptores de várias teclas, tomadas, filtro da piscina).
- Interface por **cards de cômodo**: fácil de tocar à distância, bonita e legível.
- **Rápido e resiliente**: comandos pela rede local, funcionando mesmo sem internet.
- Modo painel: tela cheia, inicia com o tablet, escurece quando ninguém está usando.

## Arquitetura

```
┌──────────────────────── Tablet (Flutter / Android) ────────────────────────┐
│                                                                            │
│   UI (cards de cômodo, cenas, detalhes)                                    │
│            │                                                               │
│      HomeController  ──  estado da casa (cômodos, dispositivos, canais)    │
│            │                                                               │
│      HomeRepository (interface)                                            │
│        ├── DemoRepository     → dados fictícios, para desenvolver o layout │
│        └── HybridRepository   → local primeiro, nuvem como reserva         │
│              ├── cache no tablet (abre na hora, funciona offline)          │
│              ├── TuyaDiscovery     → UDP 6666/6667/7000 (IP e versão)      │
│              ├── TuyaDeviceConnection → TCP 6668, 3.3/3.4/3.5, push        │
│              └── TuyaCloudRepository  → descoberta, chaves e fallback      │
└────────────────────────────────────────────────────────────────────────────┘
          │ HTTPS (descoberta, local keys, cômodos)        │ Wi-Fi local (controle)
          ▼                                                 ▼
   Tuya Cloud (openapi.tuyaus.com)                Interruptores / tomadas Tuya
```

**Estratégia híbrida**

1. **Nuvem** (Tuya OpenAPI) é usada para *descobrir*: lista de casas, cômodos, dispositivos,
   nomes das teclas e as `local_key` de cada aparelho. Os cômodos vêm direto do app Smart Life.
2. **Rede local** é usada para *controlar*: comandos criptografados direto no IP do dispositivo
   (protocolos 3.3 / 3.4 / 3.5). Resposta instantânea e sem depender da internet.
3. Se um dispositivo não responder localmente, o app cai para a nuvem automaticamente.

## Estrutura do código

```
lib/
  main.dart                   ponto de entrada, modo imersivo / tela sempre ligada
  app/theme.dart              design system (cores, tipografia, espaçamentos)
  models/                     Room, Channel, Scene, LocalDeviceInfo
  data/                       repositórios (demo, nuvem, híbrido) e cache
  tuya/tuya_cloud_client.dart cliente assinado da Tuya OpenAPI
  tuya/local/                 protocolo LAN: framing/cripto, conexão, descoberta
  state/home_controller.dart  estado e ações (otimista, refresh, pushes)
  ui/                         telas e widgets (dashboard, cards, detalhe do cômodo)
test/                         45 testes: protocolo (vetores oficiais AES/GCM),
                              dispositivo simulado 3.3/3.4/3.5, repositório, estado
tool/                         diagnósticos de linha de comando (ver docs/TABLET.md)
```

**Instalar no tablet:** veja [docs/TABLET.md](docs/TABLET.md).

## Configuração da Tuya Cloud (uma vez)

1. Entre em <https://platform.tuya.com> → **Cloud → Development → Create Cloud Project**.
   - *Industry*: Smart Home · *Development Method*: **Smart Home** · *Data Center*: **Western America** (contas do Brasil).
2. Na tela de serviços, mantenha *IoT Core*, *Authorization Token Management* e *Smart Home Basic Service*.
3. No projeto, aba **Devices → Link App Account → Add App Account**: escaneie o QR code com o app
   Smart Life (*Eu → ícone de leitura no canto superior*). Os dispositivos aparecem em *All Devices*.
4. Na aba **Overview**, copie `Access ID/Client ID` e `Access Secret/Client Secret` para
   `tuya_credentials.json` (copie de `tuya_credentials.example.json`; o arquivo é ignorado pelo git).

```bash
flutter run --dart-define-from-file=tuya_credentials.json
```

## Rodando

```bash
dart run tool/check_cloud.dart            # lista a casa vinda da Tuya Cloud (sem UI)

# preview no navegador com a casa real (a Tuya não aceita CORS, então use o proxy local)
python3 tool/dev_proxy.py us
flutter run -d chrome --dart-define-from-file=tuya_credentials.json \
  --dart-define=TUYA_BASE_URL=http://127.0.0.1:8787
```

```bash
flutter pub get
flutter run -d chrome                     # preview do layout com dados demo
flutter build apk --release               # APK para o tablet
adb install build/app/outputs/flutter-apk/app-release.apk
```

## Roadmap

- [x] Design system e dashboard de cômodos com dados demo
- [x] Cliente Tuya Cloud: casas, cômodos, dispositivos, nomes das teclas
- [x] Controle local (LAN) com push em tempo real e fallback para nuvem
- [x] Cache no tablet: abre na hora e funciona sem internet
- [ ] Primeiro teste no tablet
- [ ] Renomear teclas e reordenar cômodos no próprio painel
- [ ] Tela de configuração (credenciais sem recompilar)
- [ ] Cenas ("Boa noite", "Chegando em casa", "Apagar tudo")
- [ ] Modo painel: protetor de tela com relógio, brilho automático, iniciar no boot
- [ ] Controle de carga da bateria via tomada inteligente
