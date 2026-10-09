# Functionele wijzigingen – Maiburg Transport interface (MBT)

Dit document beschrijft alle **functionele** wijzigingen in de extensie *Maiburg Transport interface* (publisher VBS, prefix `MBT`, ID-range 52100–52149). Technische refactorings zonder merkbaar effect voor gebruiker of beheerder worden hier niet opgenomen.

> **Onderhoud:** dit document wordt bij elke functionele wijziging bijgewerkt (zie `.github/copilot-instructions.md`). Nieuwe wijzigingen komen bovenaan, onder het kopje van de betreffende versie (of onder *Nog niet uitgebracht*). De versie staat in `app.json`.

## Inhoud

- [Nog niet uitgebracht](#nog-niet-uitgebracht)
- [28.0.261007.0](#2800261007) – Van der Werff: XML-export; Claassen: Excel-export; DHL: foutmelding capabilities opgelost, label via PDF
- [28.0.260930.0](#2800260930) – DHL, Bumbal, tussenscherm en labels
- [28.0.260921.0 en eerder – basisversie](#2800260921-en-eerder--basisversie)

---

## Nog niet uitgebracht

_Geen wijzigingen._

---

## 28.0.261007.0

### Van der Werff

- **XML-export beschikbaar.** De actie *Exporteren* werkt nu ook voor transporteur Van der Werff (connector `VDWERFF`): voor alle geselecteerde regels wordt één XML-bestand gemaakt (`VDWERFF_<datum><tijd>.xml`) en in de `outbound`-map van de Azure Blob-container gezet. Hiervoor moet bij de credentials van `VDWERFF` de `ContainerSasUrl` zijn vastgelegd; ontbreekt die, dan blijven de regels niet-geëxporteerd en staat de reden in de kolom *Foutmelding*.
- De XML heeft dezelfde indeling als de eerdere Claassen-XML (per magazijnverzending: zendingnummer, klantnaam, verzenddatum, colli en totaalgewicht). Dit is een eerste opzet; het definitieve Van der Werff-schema is nog niet vastgesteld.
- Labels, tracking en het verwerken van terugkoppelbestanden zijn voor Van der Werff nog niet gebouwd en geven de melding dat de koppeling nog niet is ontwikkeld.

### Claassen

- **Export naar Claassen is nu een Excel-bestand (XLSX) in plaats van XML.** De actie *Exporteren* in het tussenscherm maakt **één Excel-bestand voor alle geselecteerde regels** die aan de transporteur Claassen zijn gekoppeld (`CLAASSEN_<datum><tijd>.xlsx`). Het bestand wordt **in de `outbound`-map van de Azure Blob-container gezet** (zoals voorheen het XML-bestand, met de container-SAS-URL uit de credentials) en daarnaast, voorlopig, **aangeboden als download**. De eerdere XML-export staat nog in de code (`ExportFileToAzureXml`), maar is uitgezet.
- De regels gelden als **geëxporteerd** wanneer de upload naar Blob Storage is gelukt; de download is alleen een extra kopie. Mislukt de upload (bijv. ontbrekende SAS-URL of Azure-fout), dan blijven de regels niet-geëxporteerd en staat de reden in de kolom *Foutmelding*; het bestand wordt dan wel nog gedownload, zodat het handmatig verstuurd kan worden.
- **Opmaak** conform *Voorbeeld_Claassen.xlsx*: regel 1 is de koptekst (ongewijzigd overgenomen, kolom A t/m AD), daarna één regel per magazijnverzending:

  | Kolom | Inhoud |
  | --- | --- |
  | A | Vast `TR_DISTR1` |
  | B | Vast `Claassen Logistics Tilburg` |
  | C | Klantnummer (*Sell-to Customer No.* van de verkooporder) |
  | D | Naam klant (*Ship-to Name*) |
  | E | Straat + huisnummer (*Ship-to Address*) |
  | F | Postcode (*Ship-to Post Code*) |
  | G | Plaats (*Ship-to City*) |
  | H | ISO2-landcode (leeg land = land uit bedrijfsgegevens, anders `NL`) |
  | I | Leeg (kop *Levering*, leveringsnummer volgt later) |
  | K | Leverdatum (verzenddatum van de magazijnverzending, `dd.mm.jjjj`) |
  | L | Eén dag na kolom K |
  | M | Aantal colli |
  | N | Totaalgewicht (kg, afgerond op hele kilo's) |
  | O | Vast `KG` |
  | P | Vast `100-1` |

  Kolom I, J, Q en R (aantal pallets) en alle overige kolommen blijven voorlopig leeg.
- Wordt het downloaden geannuleerd, dan heeft dat geen invloed op de status: die wordt bepaald door de upload naar Blob Storage.

### DHL

- **Verlopen toegangstoken (HTTP 401 "not_authorized – Provide a valid access token") opgelost.** Een DHL-toegangstoken is slechts ca. 15 minuten geldig, maar werd tot 55 minuten hergebruikt. Daardoor mislukte o.a. het ophalen van een label kort na het aanmelden. Een token wordt nu maximaal 10 minuten hergebruikt; daarna wordt automatisch een nieuw token opgehaald. Geeft DHL toch een 401, dan wordt één keer opnieuw aangemeld en de aanroep herhaald (aanmelden van een zending en label ophalen).
- **Aanmelden van een zending – foutmelding "capabilities_retrieve_empty" (HTTP 400, "Could not find matching capabilities") opgelost.** De oorzaak was de gewichtsklasse (`parcelType`) in het bericht: de connector gebruikte de niet-bestaande waarde `LARGE` en een onjuiste indeling. Het `parcelType` wordt nu bepaald op het **gewicht per collo**, conform de DHL-lijst (zakelijke zendingen vanuit NL): tot 10 kg `SMALL`, 10–20 kg `SMALL_MEDIUM`, 20–31 kg `MEDIUM`, daarboven `PALLET`. Verder is aangepast:
  - **Gewicht per collo:** het totaalgewicht wordt verdeeld over het aantal colli (DHL verwacht het gewicht *per collo*). Is het gewicht onbekend (0), dan wordt geen gewicht meegestuurd.
  - **Landcode:** wordt altijd als ISO-code (bijv. `NL`) verstuurd, voor ontvanger en afzender. Is de landcode in BC leeg (eigen land), dan wordt het land uit de bedrijfsgegevens gebruikt en anders `NL`.
  - **Postcode:** spaties worden verwijderd en de postcode wordt in hoofdletters verstuurd (bijv. `3542 ad` → `3542AD`).
- **Verzendlabel (DHL) – nieuwe werkwijze via *Find labels* en *Get label*:** het label wordt nu in twee stappen opgehaald (DHL eCommerce API-gids, hoofdstuk 4):
  1. *Find labels* (`GET /labels?trackerCodeFilter=…`, bij een zendings-ID (GUID) als trackingnummer `?shipmentId=…`) zoekt het label-ID. Wordt niets gevonden, dan wordt gezocht op `?orderReferenceFilter=…` met het nummer van de magazijnverzending (bij het aanmelden als orderReference meegestuurd).
  2. *Get label* (`GET /labels/{labelId}` met `Accept: application/pdf`) levert het PDF-bestand, dat als download wordt aangeboden.
  - Bij meerdere gevonden labels (bijv. een zending met meerdere colli, of een opnieuw aangemelde zending met dezelfde orderReference) wordt het eerste label gedownload.
  - Is het toegangstoken verlopen (401), dan wordt één keer opnieuw aangemeld en de aanroep herhaald.
  - Is er geen label gevonden of mislukt het ophalen, dan toont de melding de reden ("Kon het verzendlabel niet ophalen bij DHL: …"). Antwoordt DHL met een lege respons, dan wordt dat als fout gemeld (met statuscode en content-type) in plaats van een leeg PDF-bestand aan te bieden.
  - Is het label succesvol gedownload, dan wordt een eerdere exportfout gewist: het vlag *Exportfout* op de magazijnverzending wordt uitgezet en de foutmelding verdwijnt uit het tussenscherm. De logregels in het transportlogboek blijven bewaard. In het tussenscherm wordt een foutmelding voortaan alleen getoond als er daarna geen geslaagde actie (export of label) voor dezelfde verzending is gelogd; dit geldt ook na een geslaagde nieuwe export.
  - De oude werkwijze via *Get multiple labels* (`POST /labels/multi`) blijft in de code beschikbaar (`GetLabelViaMulti`), maar wordt niet meer aangeroepen.
- **Trackingnummer:** wordt nu uit `shipmentTrackerCode` gelezen (terugval: `trackerCode` van het eerste collo, daarna `shipmentId`). Voorheen werd het zendings-ID als trackingnummer vastgelegd.
- **Foutanalyse:** bij een afwijzing door DHL bevat de melding in het transportlogboek nu ook het verzonden bericht ("… | Verzonden bericht: {…}"), zodat de oorzaak te herleiden is.

---

## 28.0.260930.0

### Tussenscherm "Transport Export Buffer"

| Wijziging | Toelichting |
| --- | --- |
| Reeds geëxporteerde verzendingen blijven zichtbaar | Het tussenscherm toont alle volledig gepickte magazijnverzendingen in de gekozen periode, ook als ze al zijn geëxporteerd (voorheen werden die verborgen). |
| Bevestiging bij opnieuw exporteren | Zijn er onder de geselecteerde regels al eerder geëxporteerde verzendingen, dan vraagt de actie *Exporteren* eerst om bevestiging: "Een of meer geselecteerde regels zijn al eerder geëxporteerd. Wilt u deze opnieuw exporteren?". |
| Alleen *Geselecteerd* is aanpasbaar | Alle overige kolommen zijn niet meer bewerkbaar. Regels kunnen niet meer worden verwijderd. |
| Filter wordt altijd hersteld | Na een export (ook als er niets was geselecteerd) wordt het filter op *Geselecteerd* en op connector weer opgeheven, zodat het scherm niet "leeg" achterblijft. |
| Nieuwe actie **Magazijnverzending** | Opent de magazijnverzending van de geselecteerde regel. |
| Nieuwe actie **Brondocument** | Opent het eerste brondocument (bijv. verkooporder) van de magazijnverzending. |
| Nieuwe actie **Label afdrukken** | Haalt het verzendlabel op bij de transporteur en biedt het aan als PDF-download (zie [Labels](#verzendlabels)). |

### Gewicht en aantal colli

- Het totaalgewicht van een verzending wordt nu correct berekend: het veld *Gewicht* op de magazijnverzendingsregel is al het **totaalgewicht van de regel** en wordt niet meer vermenigvuldigd met de te verzenden hoeveelheid. Het totaal wordt afgerond op hele kilo's.
- Het gewicht in het bericht is het totaalgewicht, afgerond op hele kilo's; het DHL-bericht verdeelt dit vanaf 28.0.261007.0 over de colli.

### Transportkoppeling-instellingen

- Nieuw veld **Account ID** (veld 11) op *Transport Connector Setup* (lijst en kaart): het account-/klantnummer bij de transporteur (bijv. DHL `accountId`).
- Bij het aanmaken van de connector **BUMBAL** worden automatisch de credential-placeholders `Email` en `Password` aangemaakt (zoals voor DHL al gebeurde met `UserId` en `ApiKey`), zodat de beheerder direct ziet welke waarden nog moeten worden ingevoerd op de pagina *Transport Connector Credentials*.

### Verzendlabels

- Nieuwe functie *Label afdrukken* voor transporteurs die labels ondersteunen (instelling *Labels Supported*).
- Controles vooraf, elk met een duidelijke foutmelding:
  - geen expediteur gekoppeld aan de magazijnverzending;
  - connector niet (correct) ingericht;
  - connector ondersteunt geen labels;
  - verzending nog niet succesvol geëxporteerd (geen trackingnummer).
- Het resultaat (gelukt of mislukt) wordt vastgelegd in het transportlogboek.
- **DHL:** zie 28.0.261007.0 voor de definitieve werking (PDF rechtstreeks via *Get multiple labels*).

### DHL

- Verzending wordt aangemeld met een volledig bericht: `shipmentId`, `orderReference` (nr. magazijnverzending), `accountId` (uit *Account ID*), ontvanger (uit ship-to van de verkooporder), afzender (uit bedrijfsgegevens), optie `DOOR` (geen handtekening) en collo-gegevens.
- **Ontvanger:** is er een ship-to contactpersoon, dan wordt de ship-to naam als bedrijfsnaam en de contactpersoon als voor-/achternaam gestuurd; anders de ship-to naam als persoon. Adres wordt gesplitst in straat, huisnummer en toevoeging; e-mail en telefoon worden meegegeven.
- **Afzender:** naam, adres, e-mail en telefoon uit *Bedrijfsinformatie*.
- **Collo:** aantal = totaal te verzenden hoeveelheid (minimaal 1), gewicht = totaalgewicht; `parcelType` wordt bepaald op gewicht (≤ 2 kg *SMALL*, ≤ 10 kg *MEDIUM*, anders *LARGE*; aanname, te bevestigen in de DHL-sandbox).
- Het trackingnummer wordt uit `trackerCode` gelezen (terugval op `shipmentId`).

### Bumbal

- **Authenticatie gewijzigd:** aanmelden via e-mail/wachtwoord (`/authenticate/sign-in`) in plaats van een API-key/Bearer-token. De sessietoken wordt in de header `Token` meegestuurd en lokaal gecachet; uit voorzorg wordt na 105 minuten opnieuw aangemeld (Bumbal laat sessies na 2 uur inactiviteit vervallen).
- **Aanmelden van een zending** (`POST /activity/set`) bevat nu:
  - `nr`, `reference`, `activity_type_name` (`dropoff`), `duration` (15 minuten, placeholder tot het tijdvenster is afgestemd);
  - `capacities` voor totaalgewicht (kg) en aantal;
  - `address`, `remarks` (*Uw referentie*, anders *Extern documentnr.*) en `communication` (telefoon/e-mail) uit de verkooporder;
  - `package_lines` uit de regels van déze magazijnverzending (dus alleen het werkelijk te verzenden aantal bij deelleveringen), met artikelnummer als barcode, omschrijving, aantal en volume;
  - `links` (`link_id` = nr. magazijnverzending, `provider_name` = `business_central`) zodat de zending later eenduidig terug te vinden is.
- Het activity-id uit `additional_data.activity_info.id` wordt als trackingnummer vastgelegd.
- **Status opvragen** gebeurt via `PUT /activity` met filter op id; de status komt uit `status_name`.
- Verzoeken sturen `Accept: application/json` mee, omdat Bumbal anders XML terugstuurt.
- Bumbal levert geen verzendlabel; *Label afdrukken* is hiervoor niet van toepassing.
- Track & trace-terugkoppeling is voorlopig polling via de status-opvraag (webhook nog af te stemmen met Bumbal).

### Algemene HTTP-koppeling

- De HTTP-helper ondersteunt nu een eigen naam voor de authenticatieheader (bijv. `Token` i.p.v. `Authorization`) en extra headers (zoals `Accept`). Bestaande aanroepen blijven ongewijzigd werken. Retry met backoff bij HTTP 429/5xx blijft van kracht.

### Overig

- Versie verhoogd van 28.0.260921.0 naar **28.0.260930.0**.
- Vertaalbestand (`Translations\*.g.xlf`) bijgewerkt voor de nieuwe teksten.

---

## 28.0.260921.0 en eerder – basisversie

Functionaliteit zoals opgeleverd in de eerste versies (uitgangspunt: Bouwplan Koppeling Transporteurs en FO "Koppeling met transporteurs" v1.1).

**Transporteurs**

| Transporteur | Type | Status |
| --- | --- | --- |
| DHL | API (REST/JSON) | Gebouwd |
| Bumbal | API (REST/JSON) | Gebouwd |
| Claassen Transport | Bestand (XML via Azure Blob Storage) | Gebouwd |
| Van der Werff | Bestand (XML) | Alleen voorbereid (stub, geen schema/mapping); XML-export toegevoegd in 28.0.261007.0 |

**Functies**

- **Transportkoppeling-instellingen** (*Transport Connector Setup*): per transporteur code, omschrijving, vervoerdersnr., type (API/Bestand), actief, track & trace en labels ondersteund, codeunit-ID, basis-URL en update-frequentie; kaart- en lijstpagina.
- **Credentialbeheer:** geheimen (gebruikers-ID, API-key, SAS-URL, tokens) worden in Isolated Storage bewaard en beheerd via *Transport Connector Credentials*.
- **Magazijnverzending uitgebreid** (tabel- en pagina-extensie) met expediteur (connector), trackingnummer, geëxporteerd-vlag, exportdatum/-tijd en exportfout.
- **Tussenscherm** (*Transport Export Buffer*): volledig gepickte magazijnverzendingen in een periode selecteren en exporteren, gegroepeerd per connector (API per verzending, bestand gebundeld). Toont klant, colli, gewicht, trackingnummer en laatste fout.
- **API-export** (DHL, Bumbal): per verzending aanmelden bij de transporteur en het trackingnummer terugschrijven op de magazijnverzending.
- **Bestandsexport** (Claassen): oorspronkelijk een XML-bestand per exportactie in de `outbound`-map van de Azure Blob-container (vanaf 28.0.261007.0 vervangen door een Excel-bestand, zie aldaar); terugkoppelbestanden worden uit de `inbound`-map gepolld.
- **Transportlogboek** (*Transport Log*): vastlegging van elke uitgaande/inkomende actie met status (o.a. succes/fout) en melding.
- **Vergrendeling van de expediteur:** zodra er een magazijnpick voor de verzending bestaat, kan de expediteur niet meer worden gewijzigd (*Whse Shpt Lock Mgt.*).
- **Machtigingen:** permissionsets *TRANSP-ADMIN* (beheer) en *TRANSP-USE* (gebruik).
- **Vertalingen:** Nederlands (nl-NL).
