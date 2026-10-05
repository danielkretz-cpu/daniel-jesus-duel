# Kraterkompisar online-server

En liten WebSocket-server för privata tvåspelarrum. Spelet ligger kvar på GitHub Pages. Servern körs i ett eget Cloudflare-konto på **Workers Free**, med en SQLite-backed Durable Object per rum. Inget betalkonto, domänköp, spelarkonto, extern signalserver eller TURN-tjänst behövs.

## Gratis drift och avgränsning

Behåll kontot på Workers Free. Gratisgränserna är hårda: när de nås avvisas fler anrop; ingen automatisk överdebitering på gratisplanen. Kontots andra Workers delar gränserna. Det finns ingen garanti för obegränsad eller oavbruten drift.

Kontrollerat mot Cloudflares dokumentation 2026-10-05:
- Workers: 100 000 anrop per dag på Free.
- Durable Objects: 100 000 anrop per dag, 13 000 GB-s per dag.
- SQLite: 5 miljoner lästa rader/dag, 100 000 skrivna rader/dag, totalt 5 GB.
- Hibernation-API används så att väntande rum kan vila utan att koppla ned spelarna.

[Cloudflare: Durable Objects-priser](https://developers.cloudflare.com/durable-objects/platform/pricing/)
[Cloudflare: Workers-priser](https://developers.cloudflare.com/workers/platform/pricing/)

Värdens Godot-klient räknar fysiken. Servern bestämmer spelarplatser, vidarebefordrar tillåtna inmatningar och sparar hela läget. Detta är avsett för vänskapliga matcher; en modifierad värdklient kan fuska. Ingen värdmigrering ingår. Om värden lämnar pausas matchen tills samma klient återansluter. Om en mobilwebbläsare fryser värdfliken behöver den öppnas igen.

## Lokal testning utan Cloudflare-konto

Kräver Node.js 22 eller senare. Från denna mapp:

```sh
npm ci
npm test
npm run dev
```

Den lokala servern finns på `ws://127.0.0.1:8787`. Den använder samma Worker-kod i Cloudflares `workerd`-runtime. Lokala rum försvinner när servern stoppas. Det behövs ingen inloggning.

I projektets `network_config.json`, sätt `server_url` till den lokala adressen när du testar i Godot. Använd alltid `wss://` för det publicerade HTTPS-spelet. Spara aldrig en lokal serveradress i en publicerad version.

Testerna använder riktiga WebSocket-anslutningar. De täcker rumsskapande, anslutning, avskilda rum, två spelarplatser, turkontroll, terrängdata, båda spelarnas återanslutning, samtidiga anslutningar, återställning från SQLite efter full omstart, pausad värd, rollförfalskning, fel token, för stora/felformade meddelanden, fel Origin och meddelandebegränsning.

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
7. Kontrollera `<adressen>/health`. Svaret ska innehålla `ok: true` och `protocol: 1`.
8. Sätt `server_url` i spelets `network_config.json` till samma adress med `wss://` i början, utan `/room`. Publicera sedan Godot-webbexporten via befintlig GitHub Pages CI.
9. Kontrollera två separata webbläsare/enheter: skapa rum, anslut med kod, skjut från båda, kontrollera samma krater/hälsa/tur, bryt anslutningen och återanslut.

Worker-namnet i dashboarden måste matcha `name` i `wrangler.jsonc`. Aktivera inte automatiska förhandsvisningar mot samma spelrumsmiljö. Begränsa gärna framtida byggutlösning till `online-server/**`; spelets egna ändringar behöver bara Pages-bygget.

[Cloudflare: GitHub-anslutning](https://developers.cloudflare.com/workers/ci-cd/builds/git-integration/github-integration/)
[Cloudflare: bygginställningar och byggtoken](https://developers.cloudflare.com/workers/ci-cd/builds/configuration/)

Alternativ för en utvecklare som redan har godkänd lokal inloggning: `npm run deploy`. Ingen inloggning eller behörighet skapas av projektets tester.

## Protokoll v1

Godot använder `WebSocketPeer` och JSON-textpaket. Servern är inte Godots RPC-protokoll.

Anslutningar, där BASE är den verifierade `wss://`-serveradressen:

- Skapa: `BASE/room?mode=create`
- Anslut: `BASE/room?code=ABCDEFGH`
- Återanslut: `BASE/room?code=ABCDEFGH&token=<din token>`

Servern skickar `welcome` med `protocol:1`, `room`, `seat` (0 värd/Daniel, 1 gäst/Jesus), `host`, en slumpad `token`, `peer_connected`, `host_connected`, `guest_connected`, `seq`, `input_seq`, `snapshot` (eller null) och `expires_at` (Unix-millisekunder). Token sparas bara internt i klienten, aldrig i delningslänken. Servern lagrar endast token-hashar. En återanslutning ersätter en äldre anslutning till just den verifierade spelarplatsen.

`presence` skickas när anslutningar ändras och innehåller `host_connected`/`guest_connected`. Klienterna pausar om någon saknas. En plats blir inte ledig för en främmande spelare när anslutningen bryts.

Värden skickar:

```json
{"type":"state","seq":1,"commit":true,"snapshot":{}}
```

`seq` måste öka. `snapshot` är hela matchläget, enligt Godot-klientens schema 1: fas/tur/aktiv spelare, vinkel/kraft/vapen/vind/klockor, två figurer, projektil, spår och hela ordnade kraterlistan. Servern vidarebefordrar bara värdens läge till gästen. Initialläget sparas alltid, normalt sparas högst en gång per sekund och viktiga `commit`-händelser högst fyra gånger per sekund. Vid normal frånkoppling sparas senaste läget. Ändringar i värdens `paused`-flagga sparas alltid direkt. Ett abrupt serveravbrott kan därför rulla tillbaka upp till ungefär en sekund.

Gästen skickar ett platt paket:

```json
{"type":"input","seq":1,"turn":2,"move":-1,"angle_axis":0,"power_axis":0,"action":"jump"}
```

Axlar är -1, 0 eller 1. Valfria fält: `aim:[face,angle]`, där face är -1/1 och angle är 5–85, samt `action` (`jump`, `fire` eller `weapon`). Servern tillåter detta endast från plats 1 under gästens aktuella sikttur och när värdens `paused`-flagga inte är satt. Vidarebefordrat paket innehåller även `seat:1`. Klienten fortsätter `seq` och `input_seq` efter återanslutning. Värden måste dessutom låta fjärrstyrda hållna knappar förfalla efter kort avbrott.

`{"type":"ping"}` besvaras med `{"type":"pong"}`. Rå text `ping`/`pong` stöds även som ett vilolägesvänligt heartbeat. Fel skickas som `{"type":"error","code":"...","message":"..."}`. Exempel: `room_not_found`, `room_full`, `invalid_token`, `room_expired`, `bad_message`, `forbidden`, `rate_limited`, `server_unavailable`.

## Integritet och skydd

- Rumskoder har 8 slumpade tecken och fungerar som inbjudningar. Dela bara med motspelaren. Ingen offentlig lista finns.
- Rummen har hård livslängd på två timmar. Ett Durable Object-alarm stänger anslutningarna och tar bort sparat matchläge och token-hashar.
- Ingen chatt, användarprofil, e-postadress eller matchhistorik samlas in. IP används endast kortvarigt i ett begränsat minne för enkel skapandebegränsning, inte i spelets databas.
- Applikationsloggning är avstängd. Anslutningstoken i återanslutningsadressen ska inte kopieras eller loggas. Infrastrukturleverantören kan fortfarande behandla vanlig anslutningsmetadata.
- Webbläsar-Origin kontrolleras mot spelets GitHub Pages-origin. Detta ersätter inte tokenkontroll; native Godot saknar Origin och en egen klient kan förfalska headers.
- 64 KiB per meddelande, 40 meddelanden/sekund per anslutning, högst 500 kratrar och 32 spårpunkter. Rumsskapande har en enkel minnesbaserad gräns på 10/minut/IP per Worker-instans; detta är inte en global DDoS-garanti.
- Hela kontots Free-gränser är sista skyddet mot kostnader. Uppgradera inte till Paid om kravet är noll kronor.
