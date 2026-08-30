# EPEX MenuBar

Native macOS menubar-app die kwartiertarieven voor import en export toont.

## Starten

```bash
swift run EpexMenuBar
```

De app verschijnt in de macOS-menubalk. Klik op het tarief om de grafiek te openen. Beweeg over de grafiek om het exacte kwartier en de import/exportwaarde te zien.

## App-bundel maken

```bash
chmod +x scripts/package-app.sh
scripts/package-app.sh
open "dist/EPEX MenuBar.app"
```

De `.app` draait als menubar-app zonder Dock-icoon. Het package-script bouwt expliciet voor Apple Silicon (`arm64`) en controleert de binary met `lipo`.

In 1 stap bouwen en openen:

```bash
chmod +x scripts/run-apple-silicon.sh
scripts/run-apple-silicon.sh
```

## Data

Zonder configuratie haalt de app live kwartierprijzen op via de publieke Frank Energie GraphQL API:

- `resolution: PT15M`
- `Import app`: Frank-app component op basis van BELPEX
- `Import factuur`: Dynamisch SL FEB26 QH formule uit de tariefkaart
- `All-in import`: `allInPrice * 100`, dus de API-prijs in cent/kWh voor een extra kWh
- `EPEX export`: `marketPrice * 100`, dus cent/kWh
- `Export`: terugleverformule uit de tariefkaart

Je kunt ook een eigen endpoint instellen. De app verwacht dan een JSON-array met kwartierpunten:

```json
[
  {
    "start": "2026-07-09T00:00:00+02:00",
    "end": "2026-07-09T00:15:00+02:00",
    "importCentsPerKWh": 12.34,
    "exportCentsPerKWh": 8.91
  }
]
```

Zet een endpoint in `UserDefaults`:

```bash
defaults write be.eva.epexmenubar PriceEndpointURL "https://example.local/epex-prices.json"
```

Gebruik demo-data door de netwerkverbinding te blokkeren of tijdelijk een ongeldig endpoint te zetten; bij een laadfout valt de app terug op demo-data.
