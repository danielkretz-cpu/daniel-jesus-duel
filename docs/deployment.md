# Publicera gratis med GitHub Pages

Projektet är gjort för ett **offentligt GitHub-repo** och en **offentlig spelbar
länk på GitHub Pages**. Ett GitHub Free-konto räcker. Ingen Vercel-inloggning,
egen domän, betald plan eller sparad API-nyckel behövs.

## Engångsinställning

1. Spara projektet i ett offentligt GitHub-repo. Roten ska innehålla
   `project.godot`, `export_presets.cfg`, `scripts/`, `tooling/` och `.github/`.
2. Öppna **Settings → Pages → Build and deployment → Source** och välj
   **GitHub Actions**.
3. Tillåt GitHub Actions för repot om funktionen är avstängd. De medföljande
   actions kommer från GitHubs egen `actions`-organisation och är låsta till
   exakta commit-ID:n.
4. Pusha till `main`, eller kör **Godot Web CI and Pages** via **Actions → Run
   workflow** på `main`.
5. När både `test-and-export` och `deploy` är gröna finns den verifierade
   speladressen i workflow-körningens `github-pages`-miljö och under Settings →
   Pages. Adressen har normalt formen `https://<ägare>.github.io/<repo>/`.

Publicera bara spelets filer. Lägg aldrig lösenord, åtkomstnycklar, privata
bilder eller andra personliga filer i repot. Både källkoden och det exporterade
spelpaketet blir tillgängliga för allmänheten.

## Automatisk CI/CD

Arbetsflödet `.github/workflows/web-ci.yml` kör följande:

1. Hämtar den aktuella källkoden.
2. Installerar låsta Node-beroenden med `npm ci` och kör relayserverns WebSocket-tester.
3. Verifierar och installerar **Godot 4.6.3**, importerar resurser, provstartar spelet, kör `tests/test_game.gd` och `tests/test_network.gd` och exporterar
   Web-versionen till `build/web/index.html`.
4. Kontrollerar att HTML, JavaScript, WASM och spelpaket finns och att motorn är
   riktig WebAssembly. Fel i Godot-loggen stoppar byggningen även om Godot skulle
   returnera exitkod 0.
5. Publicerar **endast från `main` och endast efter godkänd byggning**.

Pull requests kör tester och export men publicerar aldrig. Byggjobbet har bara
`contents: read`. Det separata publiceringsjobbet får endast `pages: write` och
`id-token: write`, vilka GitHub Pages kräver. GitHub skapar kortlivade
autentiseringsuppgifter för körningen; ingen personlig token eller hemlighet
behöver läggas in. Publiceringsartefakten sparas i **en dag**.

## Bygg och provspela lokalt

På Linux x86_64 behövs Bash, curl, unzip, sha256sum och Python 3:

```sh
bash scripts/install-build-tools.sh
bash scripts/build-web.sh
python3 -m http.server 8000 --directory build/web
```

Öppna `http://localhost:8000`. Web-versionen ska serveras via HTTP/HTTPS,
inte öppnas som en lokal fil. På andra system kan projektet öppnas och
exporteras från Godot 4.6.3-editorn med exportprofilen **Web**.

Editorn laddas ned från Godots officiella GitHub-release och verifieras mot en
låst SHA-256-kontrollsumma innan den körs. Vid första byggningen hämtas även
Godots officiella mallarkiv för alla plattformar, cirka 1,26 GB. Hela arkivets
SHA-256 kontrolleras, bara de två Web-mallarna packas upp och det stora arkivet
tas bort. Mallarna hashkontrolleras också separat på varje byggning.

GitHub Actions cachar editorarkivet och de två små Web-mallarna, sammanlagt
cirka 92 MB. Nästa byggning kan återanvända dem. Inga motorbinärer eller
genererade WASM-filer läggs i repot. Befintliga lokala mallar fungerar utan ny
nedladdning om deras kontrollsummor stämmer. Se
`tooling/template-provenance.json` för låsta versioner och kontrollsummor.

## iPhone och GitHub Pages

Spelet kör den riktiga Godot-motorn i WebAssembly med Compatibility-renderaren,
en enda tråd och utan GDExtension. Därför behövs inte egna COOP/COEP-headers,
som GitHub Pages inte låter projektet konfigurera. Relativa filsökvägar fungerar
även när spelet ligger under repots undermapp. Ljud aktiveras efter en tryckning.

Den officiella motorn är cirka 36 MiB före transportkomprimering. GitHub Pages
tillåter upp till **1 GB för den publicerade sidan** och har en mjuk gräns på
**100 GB trafik per månad**. Spelet ligger långt under storleksgränsen, men
mycket hög trafik kan kräva en annan värd.

## Kostnad och villkor

Kontrollerat 5 oktober 2026:

- GitHub Pages är tillgängligt på GitHub Free för **offentliga repon**.
- Standardrunners i GitHub Actions är kostnadsfria för offentliga repon.
  Välj inga större betalda runners eller tilläggstjänster.
- Den här konfigurationen kräver ingen betald hosting eller köpt domän.
- Användningen omfattas av GitHubs villkor och plattformsgränser. Pages är
  avsett för projektwebbplatser, inte kommersiella transaktions- eller SaaS-tjänster.

Officiella källor:
- [GitHub Pages-gränser](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits)
- [GitHub Pages med egna Actions-arbetsflöden](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
- [GitHub Actions och kostnader](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- [GitHubs användarvillkor](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service)

`vercel.json` och [Vercel-guiden](vercel.md) finns kvar som ett valfritt alternativ.
De behövs inte för GitHub Pages och aktiverar inget Vercel-konto automatiskt.


## Online på varsin skärm

GitHub Pages är en statisk värd. Onlinespelet behöver dessutom den lilla
relayservern i [`online-server/`](../online-server/README.md). Servern är en
Cloudflare Worker med SQLite-baserade Durable Objects. Spelarna behöver inga
konton, men ägaren behöver konfigurera och publicera servern på sitt konto.
GitHub-workflowet publicerar **inte** Cloudflare-servern och behöver inga
Cloudflare-nycklar.

Efter godkänd serverpublicering, sätt dess riktiga `wss://`-adress i
`network_config.json` och bygg/publicera spelet igen. `ALLOWED_ORIGIN` i servern
ska matcha spelwebbplatsens origin. Rums- och återanslutningsnycklar ska aldrig
sparas i Git, i spelkonfigurationen eller i delningslänkar. Konfigurationens
serveradress är offentlig, ingen hemlighet.

En tom serveradress är tillåten: lokal duell fungerar, medan onlinelobbyn
uttryckligen säger att onlineservern ännu inte är aktiverad. Serverkod, tester
och `node_modules` packas inte in i spelets PCK.

### Fullständigt lokalt nätverkstest

```sh
(cd online-server && npm ci && npm test)
bash scripts/build-web.sh
bash scripts/test-online.sh
```

Det sista kommandot startar en tillfällig Worker på loopback, kopplar upp två
riktiga Godot-klienter via WebSocket och verifierar båda spelarnas skott,
terrängsynkronisering, turordning, frånkoppling, återanslutning och paus när
värdens fönster hamnar i bakgrunden. Servern stoppas efter testet. Det kräver
varken Cloudflare-inloggning eller något externt spelarkonto.

Detta ersätter inte ett slutligt två-enhetstest mot den publicerade HTTPS/WSS-
adressen. WebGL 2, mobiltangentbord och verkliga mobilnät behöver kontrolleras
på de webbläsare som ska användas.
