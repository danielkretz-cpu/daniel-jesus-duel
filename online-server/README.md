# Kraterkompisar online-server

En liten WebSocket-server för privata rum för 2–6 spelare. Spelet ligger kvar på GitHub Pages. Servern körs i ett eget Cloudflare-konto på **Workers Free**, med en SQLite-backed Durable Object per rum. Inget betalkonto, domänköp, spelarkonto, extern signalserver eller TURN-tjänst behövs.

## Gratis drift och avgränsning

Behåll kontot på Workers Free. Gratisgränserna är hårda: när de nås avvisas fler anrop; ingen automatisk överdebitering på gratisplanen. Kontots andra Workers delar gränserna. Det finns ingen garanti för obegränsad eller oavbruten drift.

Kontrollerat mot Cloudflares dokumentation 2026-10-05:
- Workers: 100 000 anrop per dag på Free.
- Durable Objects: 100 000 anrop per dag, 13 000 GB-s per dag.
- SQLite: 5 miljoner lästa rader/dag, 100 000 skrivna rader/dag, totalt 5 GB.
- Hibernation-API används så att väntande rum kan vila utan att koppla ned spelarna.

[Cloudflare: Durable Objects-priser](https://developers.cloudflare.com/durable-objects/platform/pricing/)
[Cloudflare: Workers-priser](https://developers.cloudflare.com/workers/platform/pricing/)

Värdens Godot-klient räknar fysiken. Servern bestämmer spelarplatser, vidarebefordrar tillåtna inmatningar och sparar hela läget. Detta är avsett för vänskapliga matcher; en modifierad värdklient kan fuska. Ingen värdmigrering ingår. Om värden eller någon levande spelare kopplas ned pausas matchen tills samma klient återansluter. En utslagen gäst kan kopplas ned utan att blockera resten; värden behövs även efter utslagning. Om en mobilwebbläsare fryser värdfliken behöver den öppnas igen.

## Lokal testning utan Cloudflare-konto

Kräver Node.js 22 eller senare. Från denna mapp:

```sh
npm ci
npm test
npm run dev
```

Den lokala servern finns på `ws://127.0.0.1:8787`. Den använder samma Worker-kod i Cloudflares `workerd`-runtime. Lokala rum försvinner när servern stoppas. Det behövs ingen inloggning.

I projektets `network_config.json`, sätt `server_url` till den lokala adressen när du testar i Godot. Använd alltid `wss://` för det publicerade HTTPS-spelet. Spara aldrig en lokal serveradress i en publicerad version.

Testerna använder riktiga WebSocket-anslutningar. De täcker rumsskapande, anslutning, avskilda rum, två spelarplatser, turkontroll, terrängdata, båda spelarnas återanslutning, samtidiga anslutningar, återställning från SQLite efter full omstart, pausad värd, rollförfalskning, fel token, för stora/felformade meddelanden, fel Origin och meddelandebegränsning. Protokolltesterna täcker även v1-kompatibilitet, uppgradering av äldre sparade rum, avvisade blandversioner utan förlorad spelarplats, samt fullständiga v2-kartor, ammunition och splitter vid återanslutning och omstart.

## Publicera med Cloudflares GitHub-anslutning

Gör detta först när mappen finns i GitHub-repots `main`-gren.

1. Logga in på [Cloudflare](https://dash.cloudflare.com/) och behåll Workers Free. Inget eget domännamn behövs.
2. Öppna **Workers & Pages**, välj att skapa en Worker och importera/ansluta ett GitHub-repo. Exakt knapptext kan ändras i dashboarden.
3. Godkänn Cloudflares GitHub-app själv. Välj **Only select repositories** och enbart `danielkretz-cpu/daniel-jesus-duel`.
4. Ange följande inställningar:
   - Worker/projektnamn: `kraterkompisar-online`
   - Produktionsgren: `main`
   - Root directory: `online-server`
   - Build command: `npm test`
   - Deploy command: `npm run deploy`
   - Inga egna hemligheter eller API-nycklar behövs i koden.
5. Cloudflare skapar en beständig byggtoken som gör att senare ändringar i den valda grenen kan publiceras automatiskt. Granska och godkänn detta själv i Cloudflare. Klistra inte in några token eller lösenord i chatt.
6. Starta bygget. `wrangler.jsonc` skapar SQLite-versionen av `GameRoom`, som stöds på Free. Första publiceringen visar en `https://kraterkompisar-online.<ditt-namn>.workers.dev`-adress.
7. Kontrollera `<adressen>/health`. Svaret ska innehålla `ok: true`, `protocol: 3` och `supported_protocols: [1, 2, 3]`.
8. Sätt `server_url` i spelets `network_config.json` till samma adress med `wss://` i början, utan `/room`. Publicera sedan Godot-webbexporten via befintlig GitHub Pages CI.
9. Kontrollera två separata webbläsare/enheter: skapa rum, anslut med kod, skjut från båda, kontrollera samma krater/hälsa/tur, bryt anslutningen och återanslut.

Worker-namnet i dashboarden måste matcha `name` i `wrangler.jsonc`. Aktivera inte automatiska förhandsvisningar mot samma spelrumsmiljö. Begränsa gärna framtida byggutlösning till `online-server/**`; spelets egna ändringar behöver bara Pages-bygget.

[Cloudflare: GitHub-anslutning](https://developers.cloudflare.com/workers/ci-cd/builds/git-integration/github-integration/)
[Cloudflare: bygginställningar och byggtoken](https://developers.cloudflare.com/workers/ci-cd/builds/configuration/)

Alternativ för en utvecklare som redan har godkänd lokal inloggning: `npm run deploy`. Ingen inloggning eller behörighet skapas av projektets tester.

## Protokoll v3: lobby, egna namn och 2–6 spelare

Den nya Godot-klienten använder v3. V1/v2 finns kvar oförändrade för äldre tvåspelarmatcher; ett rum låses till den version det skapades med. Blandade versioner avvisas innan en plats tilldelas eller en anslutning ersätts.

- Skapa: `BASE/room?mode=create&protocol=3&name=V%C3%A4rd&capacity=6&map_id=0`
- Anslut: `BASE/room?code=ABCDEFGH&protocol=3&name=Kompis`
- Återanslut: `BASE/room?code=ABCDEFGH&protocol=3&token=<privat token>`
- Inbjudan till spelets vanliga webbadress använder endast `?room=ABCDEFGH`, aldrig token eller namn. Länken öppnar anslutningsmenyn; spelaren väljer namn och ansluter själv.

Namn är 1–20 Unicode-tecken efter borttagning av kontroll-/formateringstecken och blanksteg runt namnet. Vinkelparenteser avvisas. Namn renderas som vanlig text. Dubblettnamn tillåts; spelarplatsen, inte namnet, bestämmer identitet och behörighet. Kapacitet är 2–6, standard 6. `map_id` är 0–4, standard 0.

`welcome` behåller token, seq, snapshot och de äldre anslutningsfälten. För v3 tillkommer `roster:[{seat,name,connected,alive}]`, `capacity`, `player_count`, `map_id`, `started`, `all_connected`, `can_start` och `playable`. Platserna är sammanhängande 0…N−1. `input_seq` gäller den återanslutande spelarens egen plats. Ingen annans token skickas ut. `presence` innehåller samma publika lobby-/anslutningsfält.

Före matchstart:

- Varje spelare kan skicka `{"type":"rename","name":"Mitt namn"}` för sin egen plats.
- Endast värden kan skicka `{"type":"lobby","map_id":2,"capacity":6}`; fälten är valfria. Kapaciteten får inte understiga antalet reserverade platser.
- Endast värden kan skicka `{"type":"start","map_id":2}`. Karta är valfri. Minst två spelare och samtliga reserverade platser måste vara anslutna; kapaciteten behöver inte vara fylld.
- Servern sparar starten innan den skickar `started` till alla. Värden skapar sedan det första fullständiga matchläget. Inga matchlägen eller inmatningar används före start.
- Namn, karta, spelarantal och platser fryses när matchen startar. Nya spelare får `match_started`; befintliga återkommer med sin privata token. En ny omgång med annan karta eller andra spelare sker i ett nytt rum.

Frånkoppling frigör inte en reserverad plats, även i lobbyn. Återanslut i samma spelklient med knappen Återanslut. Om någon lämnar permanent före start skapar värden ett nytt rum. Ingen värdmigrering eller automatisk ersättning sker. `playable` kräver att värden och varje levande spelare är anslutna. Utslagna gäster påverkar inte pausen. Klientens fokuspauseflagga gäller fortfarande.

Schema 3 har v2-fälten med följande ändringar:

- `fighters` och `freedom` har exakt N element, där N är antalet spelare vid start (2–6). Hälsa är heltal 0–100 och Freedom-ammunition heltal 0–1.
- `active`, projektilens `owner`/`target` och valt `target` ligger inom 0…N−1. Valt mål får inte vara aktiv spelare; projektilmål får inte vara dess ägare.
- I `aim` måste aktiv spelare och valt mål leva. Under flykt/landning får de nyligen ha slagits ut. Under `over` finns högst en levande spelare och `winner` är den spelarens plats, eller −1 vid oavgjort.
- Karta måste motsvara lobbyvalet. Projektiler och högst fem splitter behåller v2:s ändliga positions-/hastighets-, ålders-, studs- och vapengränser.

Gäster från plats 1…N−1 kan skicka v2:s inmatning samt `action:"target"` och valfritt `target`. Servern accepterar bara den autentiserade platsens aktuella, levande sikttur, rätt turnummer, stigande sekvens och opausad match. Målet måste vara en annan levande spelare. Förfalskade `seat`/`owner` ignoreras; endast serverns autentiserade plats skickas vidare. Värden kontrollerar detta igen och räknar skador/fysik, inklusive Freedom-skadan på exakt 49 HP. Servern vidarebefordrar och kontrollerar rimliga gränser, men är inte en separat fusksäker fysikmotor.

Nya fel inkluderar `invalid_name`, `not_ready`, `not_started` och `match_started`. För v3 betyder `fatal:false` att klienten ska visa felet och behålla anslutningen; anslutningsfel och för stora/för många paket stänger den. Högst 40 meddelanden/sekund/anslutning och fyra lobbyändringar/sekund/anslutning. Tvåtimmarsalarmet raderar också namn och reserverade platser. V3:s lobby, startflagga, namn, platser, privata token-hashar, per-spelarsekvenser och hela matchläget återställs från samma SQLite-lagring som äldre rum.

De riktiga workerd/WebSocket-testerna omfattar sex samtidiga platser, överbokning, namn, manuell start, versionsblandning, rätt tur för varje gäst, målval, utslagning/frånkoppling, återanslutning och full SQLite-omstart både före och under match.

## Protokoll v1 och v2

Godot använder `WebSocketPeer` och JSON-textpaket. Servern är inte Godots RPC-protokoll.

Anslutningar, där BASE är den verifierade `wss://`-serveradressen:

- Skapa: `BASE/room?mode=create&protocol=2`
- Anslut: `BASE/room?code=ABCDEFGH&protocol=2`
- Återanslut: `BASE/room?code=ABCDEFGH&token=<din token>&protocol=2`

Protokollet bestäms när rummet skapas och sparas med rummet. Utelämnad `protocol` betyder v1; äldre klienter och äldre lagrade rum utan protokollfält fortsätter därför fungera som v1. `protocol=1` är också giltigt. Okända, felaktiga eller upprepade protokollvärden och försök att ansluta med en annan version än rummets ger WebSocket-felet `version_mismatch`. Kontrollen sker innan en plats tilldelas eller en befintlig anslutning ersätts. Båda spelarna måste använda samma protokoll.

Servern skickar `welcome` med rummets `protocol` (1 eller 2), `room`, `seat` (0 värd/Daniel, 1 gäst/Jesus), `host`, en slumpad `token`, `peer_connected`, `host_connected`, `guest_connected`, `seq`, `input_seq`, `snapshot` (eller null) och `expires_at` (Unix-millisekunder). Token sparas bara internt i klienten, aldrig i delningslänken. Servern lagrar endast token-hashar. En återanslutning ersätter en äldre anslutning till just den verifierade spelarplatsen.

`presence` skickas när anslutningar ändras och innehåller `host_connected`/`guest_connected`. Klienterna pausar om någon saknas. En plats blir inte ledig för en främmande spelare när anslutningen bryts.

Värden skickar:

```json
{"type":"state","seq":1,"commit":true,"snapshot":{}}
```

`seq` måste öka. `snapshot` är hela matchläget: fas/tur/aktiv spelare, vinkel/kraft/vapen/vind/klockor, två figurer, projektil, spår och hela ordnade kraterlistan. `schema` måste motsvara rummets protokoll. Schema 1 behåller sina tidigare fält och vapengränser (0–1), utan krav på de nya v2-fälten.

Schema 2 har samma basfält samt:

- `map_id`: heltal 0–4.
- `freedom`: exakt två heltal 0–1, ett ammunitionsantal per spelare.
- `weapon`: heltal 0–3; splittertypen 4 får inte väljas som vapen.
- `projectile`: tomt objekt eller ett fullständigt projektilobjekt med `pos`/`vel` (två ändliga tal vardera, inom ±10000), `age` (0–10), `weapon` (heltal 0–3), `bounces` (heltal 0–4), `owner` och `target` (heltal 0–1). Målet måste vara motspelaren: `target == 1 - owner`.
- `fragments`: en lista med högst fem fullständiga projektilobjekt. Varje splitter har samma fält och gränser, men `weapon` måste vara 4. Tomma eller icke-objekt godtas inte som splitter.

Hela läget, inklusive karta, kvarvarande ammunition, projektil och samtliga splitter, vidarebefordras och sparas. Servern vidarebefordrar bara värdens läge till gästen. Initialläget sparas alltid, normalt sparas högst en gång per sekund och viktiga `commit`-händelser högst fyra gånger per sekund. Vid normal frånkoppling sparas senaste läget. Ändringar i värdens `paused`-flagga sparas alltid direkt. Ett abrupt serveravbrott kan därför rulla tillbaka upp till ungefär en sekund.

Gästen skickar ett platt paket:

```json
{"type":"input","seq":1,"turn":2,"move":-1,"angle_axis":0,"power_axis":0,"action":"jump"}
```

Axlar är -1, 0 eller 1. Valfria fält: `aim:[face,angle]`, där face är -1/1 och angle är 5–85, samt `action` (`jump`, `fire` eller `weapon`). Servern tillåter detta endast från plats 1 under gästens aktuella sikttur och när värdens `paused`-flagga inte är satt. Vidarebefordrat paket innehåller även `seat:1`. Klienten fortsätter `seq` och `input_seq` efter återanslutning. Värden måste dessutom låta fjärrstyrda hållna knappar förfalla efter kort avbrott.

`{"type":"ping"}` besvaras med `{"type":"pong"}`. Rå text `ping`/`pong` stöds även som ett vilolägesvänligt heartbeat. Fel skickas som `{"type":"error","code":"...","message":"..."}`. Exempel: `version_mismatch`, `room_not_found`, `room_full`, `invalid_token`, `room_expired`, `bad_message`, `forbidden`, `rate_limited`, `server_unavailable`.

## Integritet och skydd

- Rumskoder har 8 slumpade tecken och fungerar som inbjudningar. Dela bara med dem du vill spela med. Ingen offentlig lista finns.
- Rummen har hård livslängd på två timmar. Ett Durable Object-alarm stänger anslutningarna och tar bort sparat matchläge och token-hashar.
- Endast självvalda visningsnamn delas med spelarna i samma rum och sparas under rummets livslängd. Ingen chatt, kontoprofil, e-postadress eller matchhistorik samlas in. IP används endast kortvarigt i ett begränsat minne för enkel skapandebegränsning, inte i spelets databas.
- Applikationsloggning är avstängd. Anslutningstoken i återanslutningsadressen ska inte kopieras eller loggas. Infrastrukturleverantören kan fortfarande behandla vanlig anslutningsmetadata.
- Webbläsar-Origin kontrolleras mot spelets GitHub Pages-origin. Detta ersätter inte tokenkontroll; native Godot saknar Origin och en egen klient kan förfalska headers.
- 64 KiB per meddelande, 40 meddelanden/sekund per anslutning, högst 500 kratrar och 32 spårpunkter. Rumsskapande har en enkel minnesbaserad gräns på 10/minut/IP per Worker-instans; detta är inte en global DDoS-garanti.
- Hela kontots Free-gränser är sista skyddet mot kostnader. Uppgradera inte till Paid om kravet är noll kronor.
