# Kraterkompisar

En liten, färdig artilleriduell i **Godot 4.6.3**. Daniel och Jesus möts på Skymningsskäret: en egen skärgårdsbana som bokstavligen går sönder under matchen.

## Spela

Två personer turas om på samma mobil eller dator. Starta duellen, flytta till ett bra läge, ställ in vinkel och kraft och skjut. Lämna sedan över skärmen. Den sista överlevande vinner.

- **A / D eller ← / →:** flytta. Varje tur har en begränsad gångsträcka.
- **J:** hoppa.
- **W / S eller ↑ / ↓:** ändra vinkel.
- **Q / E:** ändra kraft.
- **Tab:** byt mellan raket och studsbomb.
- **Mellanslag:** skjut.
- **M:** ljud av/på.
- **Esc eller ?:** hjälp och paus.
- **R eller ↻:** tillbaka till startskärmen. Starta därefter en ny duell.

På mobil använder du knapparna. Håll pilarna eller +/− intryckta. Du kan också trycka eller dra i himlen för att sikta. Gränssnittet anpassar sig till stående och liggande skärm. Liggande ger bäst överblick.

Varje tur är 40 sekunder. Vinden påverkar skotten. Raketer exploderar vid träff; studsbomber studsar och har en kort stubin. Explosioner ger skada och knuffar, men även höga fall är farliga. Vattnet innebär utslagning.

## Öppna i Godot

1. Installera Godot 4.6.3 Standard från [godotengine.org](https://godotengine.org/download/archive/4.6.3-stable/).
2. Importera `project.godot`.
3. Tryck F6/F5 för att spela.

Projektet använder GDScript och Compatibility-renderaren. Ingen .NET, databas, betalt API, kontoinloggning eller externa spelresurser behövs.

## Test och webbexport

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_game.gd
```

CI och byggskript beskrivs i [docs/deployment.md](docs/deployment.md). Webbversionen exporteras till `build/web/index.html` och måste serveras via HTTP(S), inte öppnas med `file://`.

En lokal server för exporterade filer:

```sh
python3 -m http.server 8000 --directory build/web
```

Öppna sedan http://localhost:8000. Webbexporten körs utan trådar och utan GDExtensions, så den behöver inte SharedArrayBuffer eller särskilda COOP/COEP-rubriker. WebGL 2 och en modern webbläsare krävs. Ljud aktiveras efter en knapptryckning.

## Projektstruktur

- `Game.gd`: spelfysik, turer, förstörbar terräng, originalgrafik, ljud och responsivt gränssnitt.
- `Main.tscn`: huvudscenen.
- `assets/`: ikon och paketerade typsnitt.
- `tests/test_game.gd`: deterministiska tester som kör den riktiga Godot-scenen.
- `scripts/`, `.github/`, `vercel.json`: bygg- och leveransflöde.
- `tooling/`: licenser och ursprung för Godots officiella webbmallar. Mallarna hämtas och hashkontrolleras av byggskriptet; inga motorbinärer behöver sparas i Git.
- `build/`, `.cache/`, `.godot/`: genererade filer; ska inte läggas i Git.

## Om figurerna och grafiken

Daniel är en påhittad, tecknad äventyrare med grön mössa och gul halsduk, inte en fotobaserad avbildning. Jesus är en lavendelfärgad ring med ansikte och små ben, inspirerad av sin runda avatar. Alla figurer, landskap, effekter och ljud skapas i Godot. Blender används inte i denna version.

Det här är ett eget, Worms-inspirerat spel med egna figurer och egen grafik. Inga Worms-filer, figurer, logotyper eller ljud ingår. Ingen koppling till Team17.

Godot är fri programvara under MIT-licensen: https://godotengine.org/license/ . DejaVu Sans ingår med sin licens i `assets/FONT-LICENSE.txt`.

## Avgränsning

Första versionen är en lokal tvåspelarduell på en bana. Jesus är en spelbar figur, inte en AI-motståndare. Ingen onlinemultiplayer, sparade matchresultat eller kontohantering ingår. Fungerande webbexport och tester följer med, men publicering kräver att rätt GitHub-/hostingkonto ansluts och att den första leveransen verifieras.
