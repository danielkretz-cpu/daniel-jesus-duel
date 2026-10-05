# Kraterkompisar

En liten artilleriduell i **Godot 4.6.3** med riktiga **3D-figurer och 3D-miljöer**. Spela lokal duell eller bjud in upp till sex vänner till fem egna, förstörbara arenor med originalgrafik och fyra vapen. Spelet behåller sin lättstyrda sidovy och samma tvådimensionella rörelse, sikte och fysik.

## Spela

Välj **Lokal duell** för att turas om på samma mobil eller dator. Välj **Online** för att spela på varsin skärm när onlineservern har aktiverats.

Online väljer alla ett eget namn. Värden skapar ett privat rum och delar en vanlig **vänlänk** eller den åttateckniga rumskoden. Länken förifyller rummet; vännen skriver sitt namn och väljer **Gå med**. Värden väljer arena och trycker **Starta matchen** när 2–6 spelare har anslutit. Inga spelarkonton behövs. Spelarna har olika färger, delar på turerna och utslagna spelare hoppas över. Den sista överlevande vinner.

Vänlänkar innehåller bara den offentliga rumskoden. De innehåller aldrig spelarens privata återanslutningsnyckel. Webbens delningsknapp öppnar enhetens vanliga delningsruta när den stöds; kopiera länk och rumskod fungerar också.

Om en levande spelare eller värden tappar nätverket pausas matchen. En utslagen gäst kan lämna utan att stoppa de andra, men värdens enhet måste vara kvar även om värdens figur är utslagen. Använd **Återanslut** i samma öppna spelflik. Värden behöver hålla sin spelflik öppen och i förgrunden eftersom den enheten räknar ut matchen. Om fliken laddas om eller stängs försvinner dess tillfälliga återanslutningsnyckel; skapa då ett nytt rum. Rum stängs efter två timmar. Spelarlistan och banan låses när matchen startar.

- **A / D eller ← / →:** flytta. Varje tur har en begränsad gångsträcka.
- **Mellanslag:** hoppa (J fungerar också).
- **W / S eller ↑ / ↓:** ändra vinkel.
- **Håll K:** ladda skottet. Kraften pendlar mellan 12 och 100 %; släpp när mätaren står rätt.
- **Tab:** byt mellan raket, studsbomb, banankluster och Freedom.
- **T eller Mål-knappen:** välj en annan levande motståndare för Freedom. När en tur börjar väljs den närmaste motståndaren.
- **Släpp K:** skjut med den visade kraften. På pekskärm: håll och släpp skottknappen.
- **M:** ljud av/på.
- **Esc eller ?:** hjälp och paus.
- **R eller ↻:** tillbaka till startskärmen. Starta därefter en ny duell.

På mobil använder du knapparna. Håll pilarna eller +/− intryckta. Du kan också trycka eller dra i himlen för att sikta. Gränssnittet anpassar sig till stående och liggande skärm. Liggande ger bäst överblick.

Varje tur är 40 sekunder. Vinden påverkar skotten. Raketer exploderar vid träff; studsbomber studsar och har en kort stubin. Explosioner ger skada och knuffar, men även höga fall är farliga. Vattnet innebär utslagning.

## Nya vapen och banor

- **Banankluster:** en banan spricker i fem fysiska småbananer vid toppen av kastet, efter 1,2 sekunder eller vid kollision. Varje småbanan exploderar och gör en egen krater. Huvudträffen ger högst 9 explosionsskada och varje del högst 11; terrängras och bottenfaror kan ge ytterligare skada.
- **Freedom:** en direkt projektilträff på motståndaren ger en målsökande missil. Det gäller raket, studsbomb och banan/delbanan, men inte enbart explosionsradie eller självträff. Varje spelare kan spara högst en. Den förbrukas när den avfyras, söker motståndaren och ger exakt **49 direkt skada** vid träff, utan splash, knuff eller ny Freedom-belöning. Terräng kan stoppa den. Låst ammunition och antal visas i gränssnittet.
- **Fem arenor:** Skymningsskäret (skärgård), Urtidsdjungeln (dinosaurieäventyr), Dubbelsolens öken (rymdvästern), Neonmetropolen (digital action) och Eldcitadellet (mörk fantasy). Banorna har olika höjdprofiler, färger och belysta lågpolygonmiljöer med säkra startytor. Referenserna är filmgenrer, med egna motiv och inga kopierade filmtillgångar.

Välj bana med pilarna på startskärmen före en lokal match eller innan du skapar ett onlinerum. Värdens val gäller online. En ny duell återställer mark, ammunition och hälsa. Återanslutning behåller den egna platsen, alla namn, vald bana, kratrar, ammunition, mål och alla flygande småbananer. Båda spelarna behöver samma spelversion; gamla rum stöds fortsatt av servern men blandade versioner kan inte dela rum.

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
godot --headless --path . --script res://tests/test_expansion.gd
godot --headless --path . --script res://tests/test_3d.gd
godot --headless --path . --script res://tests/test_multiplayer_six.gd
godot --headless --path . --script res://tests/test_menu.gd
godot --headless --path . --script res://tests/test_animation.gd
```

CI och byggskript beskrivs i [docs/deployment.md](docs/deployment.md). Webbversionen exporteras till `build/web/index.html` och måste serveras via HTTP(S), inte öppnas med `file://`.

En lokal server för exporterade filer:

```sh
python3 -m http.server 8000 --directory build/web
```

Öppna sedan http://localhost:8000. Webbexporten körs utan trådar och utan GDExtensions, så den behöver inte SharedArrayBuffer eller särskilda COOP/COEP-rubriker. WebGL 2 och en modern webbläsare krävs. Ljud aktiveras efter en knapptryckning.

## Projektstruktur

- `Game.gd`: oförändrad 2D-spelfysik, turer, ammunition, pixelbaserad terräng, ljud och responsivt gränssnitt.
- `World3D.gd`, `Projection3D.gd`: separat 3D-vy med fast ortografisk kamera och exakt projektion till spelkoordinaterna.
- `Terrain3D.gd`: verklig extruderad terränggeometri. Varje kollisionspixel och hål bevaras; bara berörda terrängdelar byggs om efter explosioner.
- `Fighter3D.gd`, `Projectile3D.gd`: animerade volymfigurer och projektiler, inklusive bananer och Freedom.
- `Environment3D.gd`: fem belysta 3D-dioramor med fyr, dinosaurie, dubbla solar, neonstad och eldcitadell.
- `MapThemes.gd`: fem deterministiska terrängprofiler och färgpaletter.
- `Main.tscn`: huvudscenen.
- `NetSession.gd`: versionsstyrd WebSocket-klient och privat 2–6-spelarrum.
- `StartMenu.gd`, `OnlineLobby.gd`, `MenuUI.gd`, `FriendInvite.gd`: tydlig meny, valda namn, fingerstora kontroller, vänlänkar och rumslobby.
- `network_config.json`: offentlig serveradress, ingen hemlighet. Tom adress visar tydligt att online inte är aktiverat.
- `online-server/`: Cloudflare Worker med privata 2–6-spelarrum och lokala tester.
- `tests/test_online_live.gd`, `scripts/test-online.sh`: två- och sexklienttester med riktiga Godot-klienter mot den lokala relayservern.
- `assets/`: ikon och paketerade typsnitt.
- `tests/test_game.gd`: deterministiska tester som kör den riktiga Godot-scenen.
- `scripts/`, `.github/`, `vercel.json`: bygg- och leveransflöde.
- `tooling/`: licenser och ursprung för Godots officiella webbmallar. Mallarna hämtas och hashkontrolleras av byggskriptet; inga motorbinärer behöver sparas i Git.
- `build/`, `.cache/`, `.godot/`: genererade filer; ska inte läggas i Git.

## Om figurerna och grafiken

Daniel är en påhittad, tecknad äventyrare med grön mössa och gul halsduk, inte en fotobaserad avbildning. Jesus är en lavendelfärgad ring med ansikte och små ben, inspirerad av sin runda avatar. Alla figurer, landskap, effekter och ljud skapas i Godot. Blender används inte i denna version.

Figurerna och projektilerna består av riktiga 3D-meshar, inte förrenderade sprites. En separat SubViewport visar världen bakom det vanliga 2D-gränssnittet. Kameran är fast, upphöjd och lätt vriden; projektionen kompenseras så att fötter, skott och sikte ligger på samma koordinater som kollisionsmasken. Ingen fri förflyttning på djupet har lagts till. Den breda markytan, klippfasetterna och de djupa kratrarna är riktiga meshytor. Grafiklagret ändrar inte kollisionsmasken. Det nya protokollet 3 hanterar de större rummen; servern fortsätter samtidigt stödja gamla protokoll 1 och 2.

Compatibility-renderaren använder enkla material, sammanslagna miljömeshar och begränsade effekter utan dyra eftereffekter eller dynamiska skuggor. Mobil får lägre intern 3D-upplösning med samma exakta bildformat. UI:t skalar självt; dubbel canvasskalning är avstängd så att menyns knappar behåller sin avsedda storlek. Figurerna har fjädrande squash/stretch, hoppförberedelse, landningsstuds, rekyl och träffreaktioner utan fördröjning av fysiken. Headless-speltester hoppar över renderingen; den särskilda 3D-testsviten kontrollerar meshmasker, kraterkanter, kamerans verkliga projektion, nätverkstillstånd och skärmrotation.

Det här är ett eget, Worms-inspirerat spel med egna figurer och egen grafik. Inga Worms-filer, figurer, logotyper eller ljud ingår. Ingen koppling till Team17.

Godot är fri programvara under MIT-licensen: https://godotengine.org/license/ . DejaVu Sans ingår med sin licens i `assets/FONT-LICENSE.txt`.

## Prestanda och nätverksrespons

Terrängens textur laddas upp högst en gång per bildruta, även vid bananregn och återanslutning. Oförändrade explosioner bygger inte om terrängen. Grafikupplösningen anpassas automatiskt efter belastningen utan att ändra text, sikteskoordinater eller fysik. Köade nätverkstillstånd slås ihop till det senaste kompletta läget i stället för att spelas upp långt efteråt.

Gästen får en kort lokal förhandsvisning av förflyttning på marken och tangentbordssikte/styrka, som sedan rättas mot värdens tillstånd. Hopp, skott, skada och terräng avgörs fortfarande av värden. Vid protokollets gräns på 500 kratrar visas ett meddelande och ytterligare terrängförstöring stoppas för den rundan; skotten fortsätter göra skada. En ny runda återställer terrängen.

Mätningar, säkerhetsgränser och reproducerbara tester finns i [prestandaguiden](docs/PERFORMANCE.md). Headless-mätningarna är CPU-tester, inte påståenden om FPS i en viss webbläsare eller telefon.

## Avgränsning

Spelet har lokal tvåspelarduell och privata onlinematcher för 2–6 spelare på fem banor. Jesus är en spelbar figur, inte en AI-motståndare. Online kräver en separat publicerad relayserver: GitHub Pages kan bara servera själva spelet. Se [onlineguiden](online-server/README.md). Utan serveradress fungerar lokal duell och onlinelobbyn förklarar vad som saknas.

Inga spelarkonton, chatt, publika rum, topplistor eller beständiga matchresultat ingår. Den som skapar rummet är matchvärd; detta är ett vänskapsspel, inte ett fusksäkert tävlingssystem. Host-migrering och återställning efter stängd/laddad-om flik ingår inte.

### Kompakta kontroller och laddade skott

Arenan använder hela skärmens bredd och renderas bakom genomskinliga kantkontroller. På dator visas små tangenttips, spelarkort, vapenval och laddmätare; på pekskärm finns minst 44-pixlars knappar. Stående läge behåller hela arenan utan att sträcka bilden och tipsar om liggande läge. Kamerans ortografiska projektion och pekkoordinater förblir exakt synkroniserade.

Skott laddas lokalt med en jämn triangelvåg (12–100–12 % på två sekunder). Ett tryck äger laddningen; extra fingrar eller tangentupprepning kan inte starta om eller släppa den. Fokusförlust, avbruten pekgest, meny, frånkoppling och turbyte avbryter utan skott. Gästens släpp skickar exakt vald `shot_power`; värden validerar tal, ändlighet, 12–100-gränser, tur, plats och sekvens före avfyrning. Protokoll 3 behålls och äldre gäster fungerar mot nya värdar. Nya gäster ber äldre värdar att ladda om i stället för att skjuta med fel kraft. Serverstödet ska publiceras före klienten.
