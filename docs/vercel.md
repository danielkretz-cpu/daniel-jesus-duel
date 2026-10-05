# Valfritt alternativ: Vercel Hobby

Projektets färdiga CI/CD använder GitHub Pages. Vercel behövs inte för att
publicera spelet. `vercel.json` finns kvar om du senare vill byta värd.

## Innan du byter

- [Vercel Hobby](https://vercel.com/docs/plans/hobby) är gratis för personligt,
  icke-kommersiellt bruk. Välj inte Pro, en provperiod eller betalda tillägg.
- Produktionsadressen är offentlig även om GitHub-repot skulle vara privat.
  [Åtkomstskyddet på Hobby](https://vercel.com/docs/deployment-protection)
  skyddar förhandsversioner men inte produktionsdomänen.
- Läs [Vercels villkor](https://vercel.com/legal/terms) när du skapar konto.
- Ge Vercels GitHub-app åtkomst till endast det här repot via den officiella
  behörighetsdialogen. Klistra inte in en token i en chatt eller källkod.

## Inställningar

Importera repot i Vercel först när du vill aktivera den alternativa
publiceringen. En import kan starta en offentlig produktionsbyggning direkt.
Välj **Other**, repots rot och produktionsgren **main**. `vercel.json` anger:

- Installation: `bash scripts/install-build-tools.sh`
- Byggning: `bash scripts/build-web.sh`
- Publik utmapp: `build/web`
- Rätt MIME-typ för `.wasm` och `.pck`

Vercels Git-integration kör samma import, tester och export före sin
publicering. Ingen Vercel-token behöver sparas i GitHub. Den befintliga
GitHub Actions-konfigurationen fortsätter publicera till Pages tills dess
separata `deploy`-jobb tas bort; att aktivera Vercel stänger inte av Pages.

Kontrollerat 5 oktober 2026: [Hobby-planen](https://vercel.com/docs/plans)
inkluderar 100 GB dataöverföring och pausas om den fria kvoten överskrids.
Vercels [GitHub-integration](https://vercel.com/docs/git/vercel-for-github)
beskriver automatisk publicering och begärda behörigheter.
