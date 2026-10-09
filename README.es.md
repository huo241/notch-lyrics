<div align="center">

# Notch Lyrics

**Letras sincronizadas y con desplazamiento, en el notch de tu MacBook.**

Un fork de [Boring Notch](https://github.com/TheBoredTeam/boring.notch) que añade un
panel de letras de verdad y divide el notch abierto en controles de reproducción y
letras — además de una pestaña del tiempo y un bloc que guarda directamente en Notas
de Apple.

[English](README.md) | [简体中文](README.zh-CN.md) | Español

<!-- Insignias -->
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black.svg)](#requisitos)
[![Fork of](https://img.shields.io/badge/fork%20of-TheBoredTeam%2Fboring.notch-orange.svg)](https://github.com/TheBoredTeam/boring.notch)
[![Release](https://img.shields.io/github/v/release/huo241/notch-lyrics?include_prereleases&sort=semver)](https://github.com/huo241/notch-lyrics/releases)
[![Downloads](https://img.shields.io/github/downloads/huo241/notch-lyrics/total)](https://github.com/huo241/notch-lyrics/releases)
[![Stars](https://img.shields.io/github/stars/huo241/notch-lyrics?style=flat)](https://github.com/huo241/notch-lyrics/stargazers)
[![Issues](https://img.shields.io/github/issues/huo241/notch-lyrics)](https://github.com/huo241/notch-lyrics/issues)

<!-- Botones rápidos -->
[![Descargar](https://img.shields.io/badge/⬇%20Descargar-DMG-2ea44f?style=for-the-badge)](https://github.com/huo241/notch-lyrics/releases/latest)
[![Star](https://img.shields.io/badge/⭐%20Dar%20una%20estrella-yellow?style=for-the-badge)](https://github.com/huo241/notch-lyrics/stargazers)
[![Reportar](https://img.shields.io/badge/🐞%20Reportar-un%20fallo-red?style=for-the-badge)](https://github.com/huo241/notch-lyrics/issues)
[![Original](https://img.shields.io/badge/⬆%20Proyecto%20original-boring.notch-lightgrey?style=for-the-badge)](https://github.com/TheBoredTeam/boring.notch)

</div>

---

## Por qué existe este fork

Boring Notch ya tenía un interruptor de letras, pero **solo mostraba una línea
de texto**: los datos de sincronización se descartaban antes de llegar a la
pantalla. Activarlo te daba una línea estática que cambiaba de texto mientras
sonaba la canción.

Este fork arregla tanto el flujo de datos como la presentación:

| | Original | Este fork |
|---|---|---|
| Visualización | Una línea, sin desplazamiento | **Ventana de 5 líneas con desplazamiento y línea actual resaltada** |
| Sincronización | Descartada | **Marcas de tiempo LRC desde LRCLIB** |
| Letras sin sincronía | Se mostraban como texto plano | Bloque estático — **nunca simula estar sincronizado** |
| Búsqueda | Solo `/api/search` | **`/api/get` para coincidencia exacta, luego `/api/search`** |
| Diseño | Todo apilado a la izquierda | **Reproductor a la izquierda, letras a la derecha** |
| Peticiones repetidas | Se volvían a pedir siempre | **En caché por canción** |
| Cambio de canción | Una respuesta tardía podía sobrescribir la canción nueva | **Protegido** |

También corrige varios fallos que ya existían en el proyecto original; consulta
[Correcciones incluidas](#correcciones-incluidas).

<div align="center">
  <img src="docs/assets/lyrics-demo.gif" alt="Demostración de Notch Lyrics" width="720" />
</div>

## Funciones

Todo lo que hace Boring Notch, y además:

- 📜 **Letras con desplazamiento** — la línea actual se resalta y las vecinas se atenúan
- 🎯 **Sincronía precisa** — guiada por marcas de tiempo LRC, con soporte para
  `[offset:]`, varias etiquetas en una línea y etiquetas por palabra
- 🧭 **Degradación honesta** — si solo hay texto sin sincronía verás un bloque
  estático desplazable, sin falsa sincronización, mientras se sigue intentando
  mejorar en segundo plano
- 🪟 **Diseño dividido** — detalles del reproductor a la izquierda, letras a la derecha
- 🔁 **Caché por canción** — la misma canción no genera peticiones repetidas
- 🛡️ **A prueba de carreras** — la respuesta tardía de una canción anterior no
  puede sobrescribir la actual

### Más allá de las letras

Dos pestañas más, con las mismas reglas: una única caja de notch, sin sorpresas de diseño.

- 🌤️ **Pestaña del tiempo** — condiciones actuales, curva de temperatura por horas y
  previsión a 7 días, con datos de [Open-Meteo](https://open-meteo.com) y **sin
  necesidad de clave de API**. Busca cualquier ciudad por su nombre —`苏州市`, `Suzhou`
  o `Tokyo` funcionan— o déjalo en manos de la ubicación automática por IP. La
  geocodificación usa Photon (OSM), así que también resuelve condados y distritos,
  no solo las grandes ciudades.
- ✍️ **Nota rápida** — un bloc dentro del notch. Escribe, pulsa Intro y el texto cae en
  la carpeta de Notas que elijas. Admite negrita / cursiva / subrayado / tachado; el
  borrador sobrevive al cierre del notch y, si falla la escritura, no se pierde nada:
  tienes un reintento.

<div align="center">
  <img src="docs/assets/weather-quicknote-demo.gif" alt="Pestaña del tiempo y nota rápida" width="720" />
</div>

## Requisitos

- **macOS 14 Sonoma** o posterior
- Mac con Apple Silicon o Intel
- Conexión a internet para buscar las letras (LRCLIB)

## Instalación

### Descarga

Descarga el `.dmg` más reciente desde
[**Releases**](https://github.com/huo241/notch-lyrics/releases/latest), ábrelo y
arrastra **Notch Lyrics** a `/Applications`.

### Primer arranque

Esta compilación está **firmada de forma ad-hoc** (sin cuenta de desarrollador de
Apple), así que macOS avisará de que el desarrollador no está identificado.
Elimina el atributo de cuarentena una vez:

```bash
xattr -dr com.apple.quarantine "/Applications/Notch Lyrics.app"
```

Después ábrela con normalidad.

> [!IMPORTANT]
> Como la firma es distinta a la del proyecto original, macOS la trata como
> **otra aplicación**: la primera vez tendrás que **volver a conceder los
> permisos de Accesibilidad, Automatización y Calendario**.

### Permisos recomendados

| Permiso | Para qué sirve |
|---|---|
| **Automatización** (`Music`) | Marcar como favorito, volumen, estado de reproducción |
| **Accesibilidad** | Sustituir el HUD del sistema |
| **Calendario / Recordatorios** | Pestaña de calendario (opcional) |
| **Cámara** | Espejo (opcional) |

## Uso

1. Abre la aplicación: el notch se convierte en tu panel de control.
2. Pasa el cursor por encima para expandirlo.
3. Reproduce algo en Apple Music o Spotify.
4. **El panel derecho muestra las letras**, desplazándose y resaltando mientras suena.

### Sobre las fuentes de letras

Las letras sincronizadas vienen de [LRCLIB](https://lrclib.net). Conviene saber dos cosas:

- **Las letras propias de Apple Music no sirven.** La propiedad `lyrics` de
  AppleScript solo devuelve texto plano; las líneas sincronizadas se dibujan
  mediante una API privada a la que los scripts no tienen acceso. Así que
  **incluso con Apple Music, la sincronía depende de LRCLIB**.
- **El controlador multimedia afecta a la carátula y al corazón.** Ajusta
  **Ajustes → Controlador multimedia → Now Playing** para que las carátulas de
  pistas en streaming funcionen y el botón de favorito responda. El modo
  `Apple Music` habla con Music.app por AppleScript, que no puede leer la
  carátula de pistas en streaming (URL track).

## Compilar desde el código fuente

### Requisitos previos

- **macOS 15.6** o posterior
- **Xcode 26** o posterior

### Pasos

```bash
git clone https://github.com/huo241/notch-lyrics.git
cd notch-lyrics
open boringNotch.xcodeproj
```

Después pulsa `Cmd + R`.

> [!NOTE]
> El proyecto descarga 12 dependencias de Swift Package. Si `Resolve Package
> Graph` se queda colgado, lo más probable es que sea la red: consulta
> [TROUBLESHOOTING.md](TROUBLESHOOTING.md#build-fails-at-resolve-package-graph)
> para una solución que evita la red.

## Pruebas

```bash
xcodebuild build -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

El analizador de LRC (`boringNotch/helpers/LyricsParser.swift`) no tiene
dependencias a propósito, para poder probarlo por separado:

```bash
swiftc -O boringNotch/helpers/LyricsParser.swift your_test.swift -o t && ./t
```

## Correcciones incluidas

Fallos encontrados en el proyecto original mientras trabajábamos en las letras,
ya corregidos aquí:

| Corrección | Síntoma original |
|---|---|
| `AppleScriptHelper` ahora serializa los scripts | `NSAppleScript` no es seguro entre hilos; las llamadas concurrentes fallaban o devolvían el resultado de la llamada **anterior** |
| Booleanos leídos con `AppleScriptBoolean` | `favorited` devuelve `'true'`/`'fals'`, para los que `booleanValue` siempre es `false` — el corazón nunca se encendía |
| Guarda de generación al marcar favorito | Un solo toque lanzaba escrituras solapadas que se pisaban entre sí |
| Guarda de intención en el corazón | Una lectura obsoleta deshacía el toque, así que el siguiente toque invertía lo contrario |
| Los scripts de AppleScript se ejecutan con un límite de 5 segundos | Un solo Apple Event que nunca recibía respuesta bloqueaba para siempre la cola serial de scripts: los siguientes se encolaban detrás y el panel entero se congelaba |
| El estado de reproducción se refresca solo | Tras dormir, o al cambiar el día, `com.apple.Music.playerInfo` deja de llegar en silencio y nada volvía a leer el estado: pulsar reproducir sí arrancaba la música, pero el icono y las letras se quedaban congelados en la pista anterior |

## Diferencias con el proyecto original

- El nombre de la app es **Notch Lyrics**; el identificador de paquete no cambia,
  así que tus preferencias actuales siguen funcionando.
- **La actualización automática está desactivada.** El appcast original publica
  compilaciones sin estos cambios, así que actualizar desde ahí los eliminaría
  sin avisar. Para reactivarla, apunta `SUFeedURL` en `boringNotch/Info.plist` a
  tu propio canal.

## Hoja de ruta

- [x] Letras con desplazamiento sincronizado
- [x] Diseño dividido reproductor / letras
- [x] Caché de letras por canción
- [x] Pestaña del tiempo con búsqueda libre de ciudades
- [x] Nota rápida que se archiva en Notas de Apple
- [ ] Resaltado palabra por palabra (karaoke)
- [ ] Tamaño de fuente y número de líneas configurables
- [ ] Caché de letras sin conexión

## Contribuir

Las incidencias y los pull requests son bienvenidos — ábrelos
[aquí](https://github.com/huo241/notch-lyrics/issues).

Como esto es un fork, valora si tu cambio corresponde mejor al
[proyecto original](https://github.com/TheBoredTeam/boring.notch). Las
correcciones que no son específicas de las letras suelen aportar más allí.

Consulta [CONTRIBUTING.md](CONTRIBUTING.md) para las normas del proyecto original.

## Agradecimientos

Este es un fork: la mayor parte del código es trabajo de otras personas.

- **[The Bored Team](https://github.com/TheBoredTeam/boring.notch)** — el Boring
  Notch original y todo lo que hace
- **[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)** — la
  fuente de Now Playing en macOS 15.4+
- **[NotchDrop](https://github.com/Lakr233/NotchDrop)** — base de la función Shelf
- **[LRCLIB](https://lrclib.net)** — la base de datos de letras de la que depende este fork
- Iconos: [@maxtron95](https://github.com/maxtron95)
- Web: [@himanshhhhuv](https://github.com/himanshhhhuv)

La lista completa está en [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).

Si quieres apoyar al proyecto original:
**[Ko-fi del autor original](https://www.ko-fi.com/alexander5015)**.

## Licencia

**GPL-3.0**, igual que el proyecto original — consulta [LICENSE](LICENSE).

Tal como exige la licencia, este fork se distribuye con su código fuente
completo y deja constancia de sus modificaciones. Si lo redistribuyes, mantén
la licencia, el código fuente y la atribución.
