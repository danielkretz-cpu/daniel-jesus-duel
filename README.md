# Kraterkompisar

En liten, färdig artilleriduell i **Godot 4.6.3**. Daniel och Jesus möts på Skymningsskäret: en egen skärgårdsbana som bokstavligen går sönder under matchen.

## Spela

Välj **Lokal duell** för att turas om på samma mobil eller dator. Välj **Online** för att spela på varsin skärm när onlineservern har aktiverats.

Online skapar den första spelaren ett privat rum och spelar Daniel. Den andra skriver in den åttateckniga rumskoden och spelar Jesus. Inga spelarkonton behövs. Bara den som har turen kan styra sin figur. Skjut, lämna en krater och försök bli den sista överlevande.

Om nätverket bryts pausas matchen. Använd **Återanslut** i samma öppna spelflik. Daniel behöver hålla sin spelflik öppen och i förgrunden, eftersom hans enhet räknar ut matchen. Om fliken laddas om eller stängs försvinner dess tillfälliga återanslutningsnyckel; skapa då ett nytt rum. Rum stängs efter två timmar.

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
godot --headless --path . --script res://tests/test_network.gd
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
- `NetSession.gd`, `OnlineLobby.gd`: privat rumslobby och WebSocket-klient.
- `network_config.json`: offentlig serveradress, ingen hemlighet. Tom adress visar tydligt att online inte är aktiverat.
- `online-server/`: Cloudflare Worker med privata tvåspelarrum och lokala tester.
- `tests/test_online_live.gd`, `scripts/test-online.sh`: två riktiga Godot-klienter mot den lokala relayservern.
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

Spelet har lokal tvåspelarduell och kodbaserad onlineduell på en bana. Jesus är en spelbar figur, inte en AI-motståndare. Online kräver en separat publicerad relayserver: GitHub Pages kan bara servera själva spelet. Se [onlineguiden](online-server/README.md). Utan serveradress fungerar lokal duell och onlinelobbyn förklarar vad som saknas.

Inga spelarkonton, chatt, publika rum, topplistor eller beständiga matchresultat ingår. Daniel är matchvärd; detta är ett vänskapsspel, inte ett fusksäkert tävlingssystem. Host-migrering och återställning efter stängd/laddad-om flik ingår inte.
